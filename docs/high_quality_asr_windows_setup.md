# Windows RTX 5080 Highest Quality ASR Setup

This setup targets the current high-end development profile:

- Windows
- RTX 5080 16 GB
- 20 GB system RAM
- English / Chinese / Japanese songs
- quality-first local processing

## Components

LyricForge Highest Quality mode expects:

1. CUDA-enabled native `qwen3-asr.exe`
2. Qwen3-ASR 1.7B
3. Qwen3 ForcedAligner 0.6B
4. `whisper-cli.exe`
5. Whisper large-v3 ggml model
6. FFmpeg

The Qwen models can be referenced by Hugging Face ID and downloaded by the
native runtime automatically.

## Qwen native runtime

The current reference runtime is the Rust/Candle `qwen3-asr-rs` CLI. It
supports:

- Qwen3-ASR 0.6B and 1.7B
- CUDA
- f16 / bf16 / f32
- forced-alignment timestamps
- local HTTP serving
- official-style long-audio chunking and timestamp merge

Build a CUDA-enabled release binary from that runtime:

```text
cargo build --release -p qwen3_asr_cli --features cuda
```

The binary target is:

```text
target/release/qwen3-asr.exe
```

The CUDA build requires a compatible Rust toolchain, MSVC build environment,
NVIDIA driver and CUDA development environment. This is a developer-oriented
setup for the current phase; a later LyricForge runtime installer should hide
these steps from normal users.

## Recommended LyricForge settings

### Mode

```text
Highest Quality
```

### Qwen runtime

```text
qwen3-asr.exe
```

### Qwen model

```text
Qwen/Qwen3-ASR-1.7B
```

### Forced aligner

```text
Qwen/Qwen3-ForcedAligner-0.6B
```

### Device / dtype

```text
cuda / bf16
```

### Whisper fallback

Use `whisper-cli.exe` with the multilingual `ggml-large-v3.bin` model.

### Fallback policy

Recommended defaults:

```text
Review threshold: 70
Maximum highlighted disagreement lines: 20
```

Whisper is run once on the complete song as an independent second opinion.
LyricForge compares its timed segments with the Qwen/ForcedAligner timeline.

## First-run behavior

On the first Qwen run, model download and initialization can take much longer
than later songs.

The Qwen sidecar stays warm for 10 minutes after a job so multiple songs can be
processed without reloading both Qwen models. After the idle timeout it exits
and releases GPU memory.

## Memory strategy

Qwen remains the primary engine and timing authority. Whisper may run while the
Qwen sidecar is warm. On an RTX 5080 16 GB target this is intentionally
quality-first.

If real-world testing shows GPU memory pressure, the next optimization should
be a configurable policy that releases Qwen before the Whisper second-opinion
pass and reloads it only for the next song.

## Long songs

The native Qwen reference runtime mirrors official Qwen behavior when forced
alignment is enabled:

- maximum forced-aligner chunk: 180 seconds
- low-energy chunk boundaries
- per-chunk alignment
- global timestamp offset correction
- merged timestamp repair

A normal 4–6 minute song is therefore still submitted by LyricForge as one
logical transcription job.

## Arbitrary-text forced alignment endpoint

The pinned native runtime build now includes a separate `POST /v1/align` endpoint with this request contract:

```json
{
  "audio": "C:/path/to/input.wav",
  "text": "the exact reference lyric to align",
  "language": "English"
}
```

A successful response contains `results[0].items`, where each item has `text`, `start_time`, and `end_time` in seconds. This is distinct from `/v1/transcribe`; the server uses the already-loaded ForcedAligner and does not treat `context` as reference text. Existing runtime bundles do not gain this endpoint automatically: rebuild or reinstall the bundle produced by the updated native workflow. Native CI must pass before treating the endpoint as available.

## Validation checklist on the target PC

1. `qwen3-asr.exe --help`
2. confirm the binary was built with CUDA support
3. run the server once with the official 1.7B + aligner model IDs
4. confirm `GET /healthz`
5. configure Whisper large-v3 and FFmpeg
6. import one Chinese song, one English song and one Japanese song
7. run Highest Quality mode
8. verify Qwen timestamps, Whisper second-opinion metadata and editor warnings
9. repeat with a song longer than 3 minutes to verify long-audio alignment
10. test cancel during Qwen inference and during Whisper fallback

## #448 manual verification: lyric-aware Whisper decoding and review flow

CI runs no inference. The steps below are the only way to get real-model
before/after numbers. Do not fill in the template with estimates: leave a cell
as `not measured` when a step was skipped.

### Preparation

1. Use the managed runtime, or a self-built `whisper-cli.exe`. In PowerShell,
   run `whisper-cli.exe -h 2>&1 | Select-String -Pattern "prompt|suppress-nst"`
   and record whether both flags are listed. If either is missing, LyricForge
   falls back to the standard arguments. That is expected, and the diagnostics
   show `已安全回退`.
2. Choose 3 songs you are allowed to use locally (one each in zh, en and ja,
   ideally each with a repeated chorus and one ad-lib). Write a reviewed
   `reference.lrc` for each **by hand** and keep it outside the repository
   (`corpus/` is git-ignored).
3. In each project, set the title and artist on the project card. Optionally
   add proper nouns as `recognitionTerms` in the project metadata. Never put
   lyric lines there.

### Runs per song

| Run | Settings | Export |
|---|---|---|
| A (before) | Recognition settings → turn off `Whisper 歌词增强解码`, Highest Quality | `A-fused.json` (the project's lyric JSON), plus `whisper.json` from the run's artifact folder |
| B (after) | Turn on `Whisper 歌词增强解码`, Highest Quality, then **重新识别歌词** on the project page (it backs up the current lyrics first) | `B-fused.json`, `B-whisper.json` |
| C (primary only) | Qwen only (or the Qwen raw output from run B's artifacts) | `qwen.json` |

The checkpoint fingerprint includes the decoding profile, so run B must not
reuse run A's chunks. Confirm that the progress log shows the chunks being
recognised again.

Build `corpus/corpus.json` with candidates `qwen-only`, `whisper-A`,
`whisper-B`, `fused-A` and `fused-B`. Add
`"secondaryRetention": {"primary": "qwen-only", "secondary": "whisper-B", "fused": "fused-B"}`
to each song, then run:

```powershell
dart run tool/asr_quality_report.dart --corpus corpus/corpus.json --output corpus/448-after.json
```

### Review-flow checks (Windows desktop, 1280x800 and a narrow window)

1. After recognition, the editor shows the collapsed `识别结果` card above the
   list. Expanding it shows the engines, total lines, `双引擎分歧`, `建议补入`
   and `待复核`, and no percentages. With a single engine, the card shows
   `不可用` instead of numbers.
2. `开始复核 N 行` (`复核` in a compact window) opens the existing review queue at the first pending row.
3. A `建议补入` row shows the Whisper text and the reason, plus `试听这一行`,
   keep and reject buttons. Keep marks the row as reviewed. Reject deletes the
   row, and Ctrl+Z restores it. The file on disk does not change until you
   press Save.
4. Manually edit a line, then re-run recognition: the edited line is protected,
   exactly as before.

### Results template

```markdown
| Song | Lang | Whisper build / flags advertised | Run | Effective profile | Lines (ref/hyp) | Line recall | CER | WER | Duplicate rate | Secondary-only rows (matched/total) | Retention | Start MAE |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | zh | | A | whisper-standard-v1 | | | | | | | | |
| | zh | | B | | | | | | | | | |
| | en | | A | whisper-standard-v1 | | | | | | | | |
| | en | | B | | | | | | | | | |
| | ja | | A | whisper-standard-v1 | | | | | | | | |
| | ja | | B | | | | | | | | | |

GPU / driver:
Model files (name, size):
Review-flow checks 1-4 (pass/fail + note):
Regressions observed and explanation:
```

## Current limitation

Highest Quality ASR already prefers an existing vocal stem, but the final
desktop source-separation backend has not yet been implemented. Until then the
workflow falls back to normalized/original audio.

Source separation is the next major quality stage.
