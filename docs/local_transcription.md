# Local Whisper Transcription

## Purpose

LyricForge generates draft timed lyrics on desktop without requiring cloud ASR.

The production path is:

1. import one or many local audio files, or select an entire music folder;
2. add them to the persistent background transcription queue;
3. create projects one by one instead of running several large ASR jobs at once;
4. prefer the separated vocal stem when available;
5. otherwise fall back to normalized audio, then original audio;
6. use FFmpeg to create a 16 kHz mono 16-bit PCM WAV;
7. run the selected local recognition pipeline;
8. parse timestamps and confidence metadata;
9. write a draft LyricDocument back to each project;
10. let the user review and edit the draft;
11. reuse the same LyricDocument for desktop playback, remote mobile playback,
    and later KTV rendering.

## Beginner setup flow

The default setup UI is intentionally path-free for ordinary users.

1. Open the local lyric recognition setup dialog.
2. Keep **Highest quality** unless disk space is the main constraint.
3. LyricForge detects the current computer and selects a recommended profile.
4. Press **Prepare recognition environment** once.
5. LyricForge downloads and records managed runtimes/models in its own
   application-support directory.
6. Advanced executable/model paths remain available behind **Advanced
   settings**, but they are not part of the normal first-run path.

The setup UI shows component readiness, installation progress, the selected
hardware profile, and a clear ready state. Users should not have to locate a
Hugging Face cache or manually choose a model folder for the managed profiles.

## Batch import and queue UI

The batch import page is the normal entry point for preparing many songs.

- **Select audio** accepts multiple files from one or more locations.
- **Scan music folder** recursively discovers supported audio files.
- Selected files are summarized before they are added to the queue.
- Large selections stay visually compact; only a short preview is expanded.
- The persistent queue has a bounded-height list so hundreds of songs do not
  make the page grow indefinitely.
- Running items are emphasized; completed items are visually quieter; failures
  remain visible with retry controls.
- A compact desktop-wide queue bar sits above the persistent player bar while
  work remains. It shows the current song, overall completion, pause/resume,
  and a shortcut back to the full queue.

Leaving the import page does not stop queue processing.

## Managed local models

For managed high-quality profiles, Qwen model repositories are downloaded into
LyricForge's application-support directory instead of relying on a hidden
third-party cache location. Downloads use partial files and HTTP range requests
so an interrupted large model download can continue instead of restarting from
zero.

Managed profiles currently include:

- `Qwen/Qwen3-ASR-1.7B`
- `Qwen/Qwen3-ASR-0.6B`
- `Qwen/Qwen3-ForcedAligner-0.6B`

The managed model directory is passed to the native ASR runtime as a local path.
This avoids requiring ordinary users to understand `HF_HOME`, Hugging Face
cache layouts, or model IDs.

## Hardware profiles

The automatic profile resolver currently distinguishes the main supported
high-quality targets:

- RTX 5080 class Windows desktop: Qwen3-ASR 1.7B + ForcedAligner 0.6B, with
  Whisper as the second opinion/fallback path.
- Intel Mac: Qwen3-ASR 0.6B + ForcedAligner 0.6B, with the matching lower-memory
  settings selected automatically.

A matching already-managed local model directory is preserved when the profile
is re-resolved. A directory for the wrong Qwen model size is not silently
reused.

## Required desktop runtime

The managed installer still requires the native ASR runtime bundle to be
available for the current platform. Before downloading multi-gigabyte models,
LyricForge checks that the expected runtime release asset exists. This avoids a
user downloading all models only to discover afterward that the native runtime
cannot be installed.

The expected release currently remains `asr-runtime-v1` with platform-specific
runtime assets. Publishing that runtime bundle is a separate deployment task
from the managed-model and batch-queue work described here.

## FFmpeg preprocessing

The transcription input is normalized with the equivalent of:

```text
ffmpeg -y -i <input> -vn -ar 16000 -ac 1 -c:a pcm_s16le transcription_input.wav
```

## Artifacts

Each project gets a transcription directory containing processing artifacts and
checkpoints. Existing user-edited lyrics are backed up before a re-recognition
job replaces the current LyricDocument.

## Progress, persistence and cancellation

The UI exposes:

- environment validation;
- managed runtime/model setup progress;
- FFmpeg preprocessing;
- transcription progress;
- parsing/completion;
- queue-level pause/resume;
- per-song failure isolation;
- retry controls;
- deterministic failure messages.

Projects and the background queue are persisted as local JSON under the
application-support data directory. Writes are serialized and use temporary
files so UI changes and background completion do not compete for the same
persistence file.

If the app exits while a queue item is running, that item returns to the queued
state on the next launch. If project creation succeeded before the queue was
able to save its `projectId`, the durable `batchQueueItemId` metadata is used to
recover the existing project instead of creating a duplicate.

Ordinary song errors mark only that song as failed and processing continues.
Environment/model errors pause the whole queue so dozens of songs are not
incorrectly marked failed for the same missing prerequisite.

## Resumable long-audio transcription

Long audio is processed as 3-minute chunks with an 8-second overlap. Each
completed chunk is checkpointed under the project's transcription output before
the next chunk starts. Restarting the same source resumes from those checkpoints
instead of rerunning completed inference. A chunk is retried up to three times;
cancellation keeps completed checkpoints. Overlap lines are merged by
normalized text and timing, preferring the higher-confidence duplicate. Short
audio continues through the existing whole-song path.

## Confidence and review

Low-confidence lines are not removed. Automatically generated lyrics remain a
draft and require user review. The project keeps confidence/fallback metadata so
the editor can surface suspicious or disputed lines instead of hiding them.

## Current limitations

- source separation is still a separate future pipeline stage;
- when no vocal stem exists, recognition falls back to normalized/original mix;
- the native ASR runtime release still needs a reliable published distribution;
- automatically generated lyrics are drafts and require user review;
- the current batch/persistence/UI branch still requires a real Flutter SDK run
  for formatting, analyzer and targeted tests before merge.
