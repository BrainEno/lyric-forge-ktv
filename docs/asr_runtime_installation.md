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
  -> download managed models with resume support
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
    qwen/
      Qwen--Qwen3-ASR-1.7B/
      Qwen--Qwen3-ASR-0.6B/
      Qwen--Qwen3-ForcedAligner-0.6B/
  state/
```

The exact operating-system application-support prefix is resolved by
`path_provider`.

Normal users never need to find or configure a Hugging Face cache. LyricForge
downloads the supported Qwen model files into its own application-support
directory, validates that the required files are present, and passes those
local directories directly to the native runtime.

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
resume. Connection setup is bounded to 30 seconds and a download with no
response data for 60 seconds is retried automatically from the retained
partial file. If Hugging Face remains unreachable, installation reports the
network error and can be resumed later without discarding downloaded bytes.
The setup screen separates the estimated overall environment preparation
progress (download, verification and installation) from the active file's
download percentage, transferred bytes, speed and remaining-time estimate.

Expected SHA-256:

```text
64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2
```

A failed checksum deletes the final model instead of silently accepting a
corrupt file.

### Download proxy

Model and managed runtime downloads use the same proxy selection:

1. An optional HTTP proxy entered in Advanced Settings.
2. Proxy environment variables recognized by Dart (`https_proxy`, `HTTPS_PROXY`,
   and related variables).
3. The Windows static system proxy or macOS HTTP/HTTPS system proxy. Linux
   currently relies on proxy environment variables rather than desktop proxy
   settings.
4. Direct connection when no proxy is configured.

Use a URL such as `http://127.0.0.1:7890`. Credentials in proxy URLs, SOCKS
proxies, and PAC/WPAD auto-configuration are not supported. If the system uses
PAC/WPAD, enter a local HTTP proxy address manually; automatic proxy discovery
may otherwise fall back to direct access if no static proxy is available. The “Test download connection” action makes a one-byte HTTP Range GET against
both the Whisper large-v3 and Qwen3-ASR large-file endpoints, follows redirects,
and uses the same configured HTTP proxy as downloads. This checks a real response
body path without downloading gigabytes. Hugging Face serves large model files
through separate storage/CDN hostnames, not only `huggingface.co`; the proxy must
permit the relevant `hf.co` and `huggingface.co` subdomains. The probe is not a
full model download or runtime-load test. No third-party mirror is selected
automatically.
The proxy can be saved independently from model/runtime paths; an incomplete
recognition profile is reported inside Advanced Settings and does not block
saving the proxy.

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

For the managed profiles, LyricForge downloads the model repository files
itself. Large files are first written as `.part` files and use HTTP Range when
the server supports it, so an interrupted download can continue instead of
starting from zero.

After all required files are present, LyricForge stores them under
`ASRRuntime/models/qwen/` and rewrites the machine-local transcription config
to those local model directories. The native Qwen sidecar therefore receives a
local `--model` path and a local `--forced-aligner` path instead of depending on
a hidden user-level Hugging Face cache.

During setup LyricForge then starts the native sidecar and waits for `/healthz`.
This verifies that both managed model directories can actually be loaded before
the environment is marked ready.

A ready marker records model path, aligner path, device, and dtype. Changing any
of those invalidates the runtime marker and causes the setup wizard to prepare
the new configuration.

The RTX 5080 highest-quality path requires roughly 6.5 GB for Qwen +
ForcedAligner in addition to the approximately 3.1 GB Whisper large-v3 model.
The setup UI therefore treats model preparation as a long-running resumable
operation rather than asking the user to download files manually.

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
- a failed Qwen upgrade preserves the selected highest-quality mode and reports the Qwen-specific error; prepared Whisper files may remain on disk, but are not persisted as a silent Whisper-only mode change;
- unfinished model files remain as resumable `.part` downloads;
- the error is shown in the setup wizard;
- transcription is blocked until required components are ready;
- the user can retry installation;
- Advanced Settings remains available for manual recovery.

The project file stays portable because machine-local executable/model paths
remain in the local transcription settings rather than project metadata.
