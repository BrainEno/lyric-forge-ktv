# Highest Quality Local ASR Mode

## Goal

Highest Quality mode is the accuracy-first desktop transcription path for
high-end NVIDIA systems.

The current target profile is:

- Windows desktop
- NVIDIA RTX-class GPU
- CUDA-capable native Qwen3-ASR runtime
- Qwen3-ASR 1.7B
- Qwen3 ForcedAligner 0.6B
- whisper.cpp large-v3 as an independent second opinion
- FFmpeg for deterministic audio preprocessing

This mode intentionally favors recognition quality over minimum runtime.

## Pipeline

```text
project audio
  -> prefer vocal stem
  -> normalized/original fallback when no vocal stem exists
  -> FFmpeg 16 kHz mono PCM
  -> Qwen3-ASR 1.7B
  -> Qwen3 ForcedAligner 0.6B
  -> Qwen-aligned LyricDocument
  -> Whisper large-v3 full-song second opinion
  -> time-overlap comparison
  -> conservative merge
  -> editable LyricDocument
```

Qwen remains the primary transcript and time-axis provider.

Whisper does not replace every disagreement automatically. It is used as an
independent second opinion. Automatic replacement is intentionally conservative;
other disagreements are surfaced in the lyric editor for review.

## Why full-song Whisper second opinion

The first implementation idea was to invoke Whisper only for already-suspicious
Qwen segments.

For Highest Quality mode this has two weaknesses:

1. a semantic Qwen error can still look structurally normal and therefore avoid
   the heuristic trigger;
2. repeatedly starting Whisper for small slices reloads the fallback model and
   can be slower than one full-song pass on a high-end GPU.

Highest Quality mode therefore runs one Qwen pass and one Whisper pass for the
whole song, then compares their timed results line by line.

## Qwen native runtime contract

LyricForge does not call Python from the Flutter UI and does not make Python a
required application runtime.

The current Qwen provider expects a local native executable compatible with this
command shape:

```text
qwen3-asr
  --device cuda
  --dtype bf16
  serve
  --model <Qwen3-ASR-1.7B model path>
  --host 127.0.0.1
  --port <ephemeral local port>
  --forced-aligner <Qwen3-ForcedAligner-0.6B model path>
```

The sidecar must provide:

```text
GET /healthz
POST /v1/transcribe
POST /v1/align
```

The currently evaluated reference implementation is the Rust/Candle
`qwen3-asr-rs` CLI. Its forced-aligner path mirrors the official Qwen
implementation: long audio is split into chunks no longer than 180 seconds,
timestamps are offset back to the original song timeline, merged, and repaired
for cross-chunk monotonicity. LyricForge therefore sends the full song once and
does not add a second competing chunking layer.

Request body:

```json
{
  "audio": "C:/path/to/input.wav",
  "language": "English",
  "return_timestamps": true
}
```

The language field is omitted for automatic language detection.

The reference server returns `{"results":[...]}`. LyricForge unwraps the
first result and accepts timestamp layouts including:

- `timestamps.items` (the current Rust/Candle forced-aligner shape)
- `segments`
- `words`
- `time_stamps`
- `timestamps.segment`
- `timestamps.words`

Each item must contain text/word plus start/end seconds.

This contract currently matches the native Rust/Candle Qwen3-ASR sidecar that
was evaluated during implementation. The contract is deliberately isolated so a
future native backend can replace it without changing project workflow or UI.

The lyric editor can optionally call `POST /v1/align` during ASR-first proofreading. It uses the same managed Qwen process, normalizes the selected vocal/original audio to 16 kHz mono WAV, and feeds validated spans into review-only token evidence. The review dialog reports incomplete coverage or runtime unavailability; neither outcome writes aligned timestamps into the source document. This option requires a runtime bundle built with the forced-alignment endpoint.

## Sidecar lifetime and GPU memory

The Qwen model and aligner stay loaded after a successful transcription so that
multiple songs can be processed without repeatedly reloading several gigabytes
of weights.

To avoid permanently reserving GPU memory, LyricForge automatically shuts down
the Qwen sidecar after 10 minutes of inactivity. Cancellation also terminates
the sidecar immediately.

## Qwen line construction

When the forced aligner returns segment timestamps, LyricForge uses them
directly.

When only word/character timestamps are returned, LyricForge groups them into
editable lyric lines using:

- punctuation boundaries
- pauses of roughly 650 ms or longer
- line duration limits
- line length limits

The forced aligner remains the timing authority.

## Independent-engine comparison

Whisper output is matched to Qwen lines by timestamp overlap with a small
padding window.

Text disagreement is measured with normalized Unicode character-level
Levenshtein similarity so the same comparison path works for:

- English
- Chinese
- Japanese

A line is prioritized for review when:

- Qwen confidence is below the configured threshold;
- timing looks abnormal;
- repeated-token/hallucination heuristics trigger;
- Qwen and Whisper text similarity is low.

Only the highest-risk lines up to the configured per-song review limit are
stored as fallback candidates.

## Conservative automatic replacement

Whisper automatically replaces Qwen text only when the primary line is clearly
unreliable, for example:

- suspicious repetition in Qwen but not Whisper; or
- very low Qwen confidence plus materially stronger Whisper confidence.

The Qwen ForcedAligner timestamps are preserved even when Whisper text is
selected.

Other disagreements remain visible in the lyric editor as a Whisper candidate
with an explicit “use alternative” action.

## Lyric editor behavior

The editor now surfaces:

- low-confidence warning state
- confidence score
- whether Whisper was automatically selected
- alternative Whisper text when Qwen remains selected

A manual text edit is treated as user confirmation for that line and raises the
line confidence to 100.

Structural edits such as adding or deleting lines clear stale fallback index
metadata.

## Current runtime configuration

Highest Quality mode currently requires local runtime configuration for:

- native CUDA-enabled `qwen3-asr` runtime
- Qwen3-ASR 1.7B model reference
- Qwen3 ForcedAligner 0.6B model reference
- whisper.cpp runtime
- Whisper large-v3 model
- FFmpeg

The Qwen model fields can use the official Hugging Face IDs directly:

- `Qwen/Qwen3-ASR-1.7B`
- `Qwen/Qwen3-ForcedAligner-0.6B`

The native sidecar downloads/caches those models on first use, so a separate
manual model-directory setup is not required.

For the current high-end target machine, Qwen uses:

- device: `cuda`
- dtype: `bf16`

A later productization phase can add automatic model/runtime installation for
general users without changing the transcription architecture.

## Current limitation: source separation

Highest Quality ASR already prefers `AudioAsset.vocalPath`.

The repository does not yet contain the final local vocal/instrumental
separation backend. Until that stage is implemented, transcription falls back
to normalized audio or original audio when no vocal stem exists.

The next quality-critical pipeline stage is therefore local source separation.

## Arbitrary-text ForcedAligner boundary

The official Qwen3-ASR Python API exposes `Qwen3ForcedAligner.align(audio, text, language)`, returning item-level text and start/end seconds. That is a real arbitrary-text alignment API, but it is a Python library call, not evidence that every server wrapping the model exposes the same request contract.

LyricForge's currently pinned Rust/Candle sidecar is launched with `--forced-aligner` and the app calls `POST /v1/transcribe`. That request accepts audio and transcription options; it does not send the supplied lyric text as an alignment target. The existing timestamps therefore describe ASR output, not an arbitrary reference lyric aligned on demand. Do not use the `context` field as a substitute.

The repository now carries a patch against the pinned Rust/Candle source that adds `POST /v1/align` with explicit `audio`, `text`, and `language` inputs. It calls the loaded `Qwen3ForcedAligner.align` API directly and returns `results[0].items` with `text`, `start_time`, and `end_time` in seconds; it does not route through ASR `context`. The native build workflow applies the patch for Windows CUDA and macOS Intel bundles and runs an endpoint contract integration test. Until that native CI passes and a rebuilt bundle is installed, existing downloaded runtime binaries must still be treated as lacking this endpoint.

The Dart HTTP adapter validates non-empty spans, timestamp ordering, and audio-duration bounds. `ForcedAlignmentProofreadService` now passes explicit audio path, reference text, and language to `/v1/align`, then maps the returned spans into the ASR-first proofread proposal as review-only tokens. Incomplete line coverage returns a warning; request/runtime errors fall back to the ordinary proposal with a visible `forcedAlignmentUnavailable` note. Neither success nor failure edits source lyric text or timestamps. The native endpoint contract CI has passed, but existing installed runtime bundles still need rebuilding before they expose `/v1/align`; real-song accuracy and Chinese/English/Japanese coverage remain unverified.


## Forced-alignment evidence in proofreading proposals

The ASR-first proofread pipeline accepts validated alignment spans and attaches them to matching review rows as `TimedLyricToken` evidence. It normalizes alignment text with the shared Unicode-aware lyric tokenizer, including full-width Latin forms, CJK characters, and common Chinese/Japanese punctuation, then matches contiguous span text against each draft line in source order. The matcher can recover across up to 12 unmatched spans before a line and considers at most 128 spans for a single line candidate; consumed spans are never reused, and a failed row does not automatically block later rows from matching. These are hard safety bounds, not permission to guess. The domain result carries `ProofreadAlignmentDiagnostics` with total/matched line counts, line coverage, skipped span count, and unmatched line indices (zero-based in the model). The service marks alignment as requested even when a successful response contains zero spans, so the result reports zero coverage rather than silently treating the response as “not requested”. Incomplete diagnostics produce a warning with line coverage, skipped-span count, and one-based unmatched lyric row numbers. The review dialog displays those diagnostics in a dedicated summary block; an empty successful response therefore shows zero coverage and does not claim that token evidence was produced. Skipped spans are not automatically classified as noise or ad-libs. The original lyric text and line-level timestamps remain unchanged. The current `/v1/align` response provides token text and start/end times but no calibrated confidence score, so `TimedLyricToken.confidence` is `null` for ForcedAligner evidence. Do not infer model confidence from the presence or duration of a span. Contract tests cover English, full-width Latin, Chinese, Japanese text normalization, bounded recovery, repeated lines and diagnostics invariants, but synthetic spans do not prove actual audio timing accuracy; real-song coverage still requires a rebuilt runtime bundle and manual audio validation.


## Repeatable ForcedAligner quality evaluation

A small corpus of manually checked token intervals can be used to compare captured `POST /v1/align` spans against reference times. The evaluator reports normalized-text recall/precision, unmatched reference/output spans, mean/median/p95/max absolute boundary error, and the rate of boundaries within a configured tolerance. Results are grouped overall and by language.

```bash
dart run tool/forced_alignment_eval.dart docs/evaluation/forced_alignment_corpus.json --output build/forced_alignment_report.json
```

The corpus uses schema version 1, a non-empty `samples` array, unique sample IDs, language names, optional `audioDurationMs`, and `referenceSpans`/`actualSpans` arrays. Each span contains `text`, integer `startMs`, and integer `endMs`. Optional settings are `toleranceMs` (default 150) and `maxGroupSpans` (default 8). Ordered bounded matching accepts different span grouping without inventing intermediate timestamps.

**Important:** no real audio or fabricated gold data is shipped with this tool. Reference intervals must be manually checked against the same original audio; synthetic tests validate the evaluator logic only. Keep separate Chinese, English, and Japanese samples and include repetitions/ad-libs before setting quality thresholds.

## Capture real local ForcedAligner results

The evaluator has a `capture` subcommand that calls a local `POST /v1/align`
endpoint, stores the returned spans as `actualSpans`, and converts
`start_time`/`end_time` seconds to integer milliseconds. It only accepts a
loopback host (`localhost`, `127.0.0.1`, or another loopback IP) and the exact
`/v1/align` path; lyrics and local file paths are never sent to an arbitrary
remote service.

Prepare a UTF-8 text file containing the exact lyric text sent to the aligner,
and a separate JSON file of manually checked reference intervals. The reference
file may be a JSON array or an object with a `referenceSpans` array:

```json
[
  { "text": "hello", "startMs": 1250, "endMs": 1510 },
  { "text": "world", "startMs": 1540, "endMs": 1850 }
]
```

Start a rebuilt local native runtime on a known loopback port, then capture the
first sample from PowerShell:

```powershell
dart run tool/forced_alignment_eval.dart capture `
  --endpoint http://127.0.0.1:8000/v1/align `
  --audio "D:/Songs/example.wav" `
  --text-file "D:/Songs/example.txt" `
  --reference "D:/Songs/example-reference.json" `
  --id en-example-01 --language English `
  --duration-ms 214000 `
  --output "D:/Evaluation/forced_alignment_corpus.json"
```

For the next song, keep the same corpus and use `--append-to` instead of
`--output`:

```powershell
dart run tool/forced_alignment_eval.dart capture `
  --endpoint http://127.0.0.1:8000/v1/align `
  --audio "D:/Songs/chinese-song.wav" `
  --text-file "D:/Songs/chinese-song.txt" `
  --reference "D:/Songs/chinese-song-reference.json" `
  --id zh-example-01 --language Chinese `
  --duration-ms 198000 `
  --append-to "D:/Evaluation/forced_alignment_corpus.json"
```

The tool validates sample IDs, span order and duration bounds before writing.
An empty `items` array is preserved as an empty actual result so evaluation can
report zero recall instead of hiding a failed alignment. Reference intervals
must be manually checked against the same audio file; this workflow does not
claim model accuracy until the corpus has been reviewed and evaluated.
