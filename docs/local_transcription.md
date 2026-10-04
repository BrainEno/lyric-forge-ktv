# Local Whisper Transcription

## Purpose

LyricForge generates draft timed lyrics on desktop without requiring cloud ASR.

The production path is:

1. import local audio into a project;
2. prefer the separated vocal stem when available;
3. otherwise fall back to normalized audio, then original audio;
4. use FFmpeg to create a 16 kHz mono 16-bit PCM WAV;
5. run the configured local ASR quality profile;
6. parse timestamps and confidence information;
7. write a draft LyricDocument back to the project;
8. let the user review and edit the draft;
9. reuse the same LyricDocument for desktop playback, remote mobile playback,
   and later KTV rendering.

## Required desktop runtime

Runtime and model setup is managed by the local ASR setup flow. The runtime
release bundle is still a separate distribution concern, but model locations
and managed model downloads no longer require the user to discover cache paths
manually.

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

Each project gets a transcription directory containing its runtime artifacts,
raw recognition result and lyric backups. Existing user-edited lyrics are
backed up before a re-recognition job replaces the current LyricDocument.

Project manifests themselves are persisted under the application support
`LyricForge/Data/projects.json` store. This means batch-created projects and
completed lyric results survive application restarts.

## Progress and cancellation

The UI exposes:

- validation
- FFmpeg preprocessing
- model loading / transcription percentage
- chunk progress for long audio
- result parsing and merging
- completion
- cancellation
- deterministic failure messages

Cancellation stops active local processing and restores the project out of the
transcribing state. Completed long-audio chunk checkpoints are preserved.

## Confidence

Low-confidence lines are not removed. Confidence remains available on
LyricLine for editor review and for the high-quality second-opinion policy.

## Resumable long-audio transcription

Long audio is processed as 3-minute chunks with an 8-second overlap. Each
completed chunk is checkpointed under the project's transcription output before
the next chunk starts. Restarting the same source resumes from those checkpoints
instead of rerunning completed inference. A chunk is retried up to three times;
cancellation keeps completed checkpoints. Overlap lines are merged by
normalized text and timing, preferring the higher-confidence duplicate. Short
audio continues through the existing whole-song path.

## Persistent batch queue

The import screen accepts either multiple selected audio files or a whole music
folder. Folder import scans recursively for MP3, FLAC, WAV, M4A, AAC and OGG
files. Selected files are added to a persistent, sequential transcription queue.

The queue is stored in `LyricForge/Data/transcription_queue.json` and provides:

- one-song-at-a-time processing to avoid competing for GPU / memory;
- automatic project creation for every accepted audio file;
- live per-song transcription and chunk progress;
- pause and resume while preserving already completed chunk checkpoints;
- restart recovery: an item interrupted while running returns to the waiting
  queue rather than being treated as failed;
- failure isolation: a bad song is marked failed and later songs continue;
- retry of failed items without duplicating their existing projects;
- source-path de-duplication, including case-insensitive de-duplication on
  Windows;
- environment-aware blocking: missing runtime/model setup pauses the queue
  instead of marking every song failed;
- clearing completed queue rows without deleting the generated projects.

Queue and project JSON writes are serialized and use temporary-file replacement
so concurrent UI/background mutations cannot overwrite each other's state.

## Current limitations

- source separation is still a separate future pipeline stage;
- when no vocal stem exists, recognition falls back to normalized/original mix;
- native ASR runtime release packaging is still blocked by the external build /
  release pipeline and is intentionally outside this queue slice;
- automatically generated lyrics are drafts and require user review.
