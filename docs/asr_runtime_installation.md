# Managed ASR Runtime Installation

LyricForge should not require normal users to understand executable paths,
model directories, CUDA flags, Rust, Cargo, or FFmpeg installation.

The normal desktop flow is:

```text
Generate lyrics
  -> detect hardware
  -> inspect local runtime
  -> show missing components
  -> one-click install / repair
  -> verify runtime and models
  -> save machine-local configuration
  -> continue transcription
```

Manual paths remain available only under Advanced Settings.

## Managed runtime directory

LyricForge uses an application-support runtime root:

```text
LyricForge/ASRRuntime/
  downloads/
  bundle/
    bin/
  ffmpeg/
    bin/
  models/
    whisper/
  state/
```

The exact operating-system application-support prefix is resolved by
`path_provider`.

Qwen Hugging Face model caching is currently controlled by the native Qwen
runtime. LyricForge does not expose that cache directory to normal users.

## Components

### FFmpeg

The installer first detects an existing executable from:

1. saved configuration;
2. LyricForge managed directory;
3. system PATH.

If missing, LyricForge installs a managed build.

Windows source:

```text
BtbN FFmpeg Builds
ffmpeg-master-latest-win64-lgpl.zip
```

Intel macOS source:

```text
evermeet.cx FFmpeg static Intel build
```

After extraction LyricForge verifies `ffmpeg -version`.

### Whisper runtime

Whisper is included in the LyricForge managed ASR runtime bundle. The bundle is
built by GitHub Actions from a pinned whisper.cpp revision.

The application verifies `whisper-cli --help` after installation.

### Whisper large-v3

Managed path:

```text
ASRRuntime/models/whisper/ggml-large-v3.bin
```

The model is downloaded from the whisper.cpp Hugging Face repository. Downloads
use a `.part` file and HTTP Range when supported so interrupted downloads can
resume.

Expected SHA-256:

```text
64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2
```

A failed checksum deletes the final model instead of silently accepting a
corrupt file.

### Qwen3-ASR runtime

The upstream Rust/Candle Qwen3-ASR project currently does not publish a normal
end-user binary release suitable for the LyricForge setup wizard.

LyricForge therefore builds managed runtime bundles itself from a pinned source
revision.

Runtime release tag:

```text
asr-runtime-v1
```

Assets:

```text
lyricforge-asr-runtime-windows-x64-cuda.zip
lyricforge-asr-runtime-macos-x64.zip
```

The application downloads only the asset matching the resolved hardware
profile.

### Qwen models

Users do not select Qwen model folders.

The hardware profile chooses the model IDs:

RTX 5080:

```text
Qwen/Qwen3-ASR-1.7B
Qwen/Qwen3-ForcedAligner-0.6B
CUDA / BF16
```

Intel Mac:

```text
Qwen/Qwen3-ASR-0.6B
Qwen/Qwen3-ForcedAligner-0.6B
CPU / F32
```

During setup LyricForge starts the native sidecar and waits for `/healthz`.
This forces first-run model download and model loading to complete before the
environment is marked ready.

A ready marker records model ID, aligner ID, device, and dtype. Changing any of
those invalidates the marker and causes the setup wizard to prepare the new
configuration.

## Beginner UI

Normal users see component states:

- Installed
- Pending installation
- Advanced/manual

The default actions are:

- Automatically install recognition environment
- Re-check
- Cancel installation
- Done

Normal users can choose only a high-level recognition scheme:

- Highest quality / dual-engine review
- Whisper-only / lower disk use

They do not select executable or model paths.

## Advanced UI

Advanced Settings keeps manual overrides for development and recovery:

- runtime executable paths
- model IDs / local model paths
- FFmpeg path
- hardware profile
- language
- review thresholds

The advanced UI is not part of the first-use path.

## Runtime build pipeline

`.github/workflows/build-asr-runtime.yml` builds:

Windows x64 CUDA:

- pinned qwen3-asr-rs
- pinned whisper.cpp
- CUDA runtime dependencies
- qwen3-asr.exe
- whisper-cli.exe

Intel macOS:

- pinned qwen3-asr-rs with Accelerate
- pinned whisper.cpp with Accelerate
- qwen3-asr
- whisper-cli

Pull requests build and smoke-check artifacts. Pushes to main additionally
create or update the rolling `asr-runtime-v1` prerelease.

This keeps Rust/Cargo/CUDA build tooling out of the end-user setup flow.

## Failure behavior

The installer does not silently fall back to fake paths.

If installation or verification fails:

- the component remains not ready;
- the error is shown in the setup wizard;
- transcription is blocked until required components are ready;
- the user can retry installation;
- Advanced Settings remains available for manual recovery.

The project file stays portable because machine-local executable/model paths
remain in the local transcription settings rather than project metadata.
