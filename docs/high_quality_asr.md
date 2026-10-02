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
qwen3_asr_cli
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
```

Request body:

```json
{
  "audio": "C:/path/to/input.wav",
  "language": "English",
  "return_timestamps": true
}
```

The language field is omitted for automatic language detection.

The response parser accepts common timestamp layouts including:

- `segments`
- `words`
- `time_stamps`
- `timestamps.segment`
- `timestamps.words`

Each item must contain text/word plus start/end seconds.

This contract currently matches the native Rust/Candle Qwen3-ASR sidecar that
was evaluated during implementation. The contract is deliberately isolated so a
future native backend can replace it without changing project workflow or UI.

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

Highest Quality mode currently requires manual paths for:

- native Qwen3-ASR runtime
- Qwen3-ASR 1.7B model directory
- Qwen3 ForcedAligner 0.6B model directory
- whisper.cpp runtime
- Whisper large-v3 model
- FFmpeg

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
