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

## Current limitation

Highest Quality ASR already prefers an existing vocal stem, but the final
desktop source-separation backend has not yet been implemented. Until then the
workflow falls back to normalized/original audio.

Source separation is the next major quality stage.
