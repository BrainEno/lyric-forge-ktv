# Local Whisper Transcription

## Purpose

LyricForge generates draft timed lyrics on desktop without requiring cloud ASR.

The production path is:

1. import local audio into a project;
2. prefer the separated vocal stem when available;
3. otherwise fall back to normalized audio, then original audio;
4. use FFmpeg to create a 16 kHz mono 16-bit PCM WAV;
5. run whisper.cpp locally;
6. parse segment timestamps and token probabilities;
7. write a draft LyricDocument back to the project;
8. let the user review and edit the draft;
9. reuse the same LyricDocument for desktop playback, remote mobile playback,
   and later KTV rendering.

## Required desktop tools

LyricForge does not bundle whisper.cpp or a Whisper model in this phase.

Configure these from the project detail screen:

- whisper-cli executable
- ggml Whisper model file
- FFmpeg executable
- language: auto / zh / en / ja / ko

The executable fields may be either:

- an absolute executable path, or
- a command available on PATH, such as `whisper-cli` or `ffmpeg`.

## Whisper command shape

LyricForge runs the equivalent of:

```text
whisper-cli
  -m <model>
  -f <16khz-mono-wav>
  -l <language>
  -ojf
  -of <output-base>
  -pp
```

`-ojf` is used because LyricForge needs segment offsets and token
probabilities. Segment offsets are treated as the authoritative lyric line
boundaries. Token probabilities are averaged only to create the editable
line-confidence hint.

## FFmpeg preprocessing

The transcription input is normalized with the equivalent of:

```text
ffmpeg -y -i <input> -vn -ar 16000 -ac 1 -c:a pcm_s16le transcription_input.wav
```

## Artifacts

Each project gets a transcription directory containing:

- `transcription_input.wav`
- `whisper_result.json`
- `backups/lyrics_<timestamp>.json` when lyrics existed before re-recognition

Existing user-edited lyrics are backed up before a re-recognition job replaces
the current LyricDocument.

## Progress and cancellation

The UI exposes:

- validation
- FFmpeg preprocessing
- Whisper transcription percentage
- JSON parsing
- completion
- cancellation
- deterministic failure messages

Cancellation kills the active local processing process and restores the project
out of the transcribing state.

## Confidence

Low-confidence lines are not removed.

The current draft threshold is 65/100. LyricLine.confidence stores the average
Whisper token probability for the segment. The document metadata records the
threshold and the number of low-confidence lines so the editor can highlight
them in a later UI refinement.

## Current limitations

- source separation is still a separate future pipeline stage;
- when no vocal stem exists, recognition falls back to normalized/original mix;
- project persistence is still backed by the current repository implementation;
- Whisper and model installation/download automation are not included yet;
- automatically generated lyrics are drafts and require user review.
