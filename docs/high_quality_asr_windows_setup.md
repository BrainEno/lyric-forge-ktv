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
- per-process HTTPS serving bound to IPv4 loopback on an OS-assigned port
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

A successful response contains `results[0].items`, where each item has `text`, `start_time`, and `end_time` in seconds. This is distinct from `/v1/transcribe`; the server uses the already-loaded ForcedAligner and does not treat `context` as reference text. The endpoint is available only over the per-process pinned TLS/Bearer session; the child accepts `--port 0`, not a reserved fixed port, and missing credentials fail closed. The managed app passes the token through the child environment, reads the port and public certificate from that child's stdout pipe, and authenticates health/transcribe/align requests without following redirects. Existing runtime bundles do not gain this endpoint or security boundary automatically: reinstall the bundle produced by the updated native workflow. Native CI must pass before treating the endpoint as available.

This protects the managed session from unrelated local listeners, not from same-user software that can inspect process environments or memory, or from administrators/debuggers. CI mock runtimes validate protocol behavior only: they do not verify a real NVIDIA GPU, driver/antivirus policy, installed package behavior, real-song timing accuracy, or Chinese/English/Japanese coverage. Complete the target-PC checklist below after installing the rebuilt bundle.

## Validation checklist on the target PC

1. `qwen3-asr.exe --help`
2. confirm the binary was built with CUDA support
3. install the managed runtime and official 1.7B + aligner models
4. verify the app-managed HTTPS health check (pinned certificate and Bearer token)
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
