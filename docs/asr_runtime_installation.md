# Managed ASR Runtime Installation

Elysium Player should not require normal users to understand executable paths,
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

Elysium Player uses an application-support runtime root:

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

Normal users never need to find or configure a Hugging Face cache. Elysium Player
downloads the supported Qwen model files into its own application-support
directory, validates that the required files are present, and passes those
local directories directly to the native runtime.

## Components

### FFmpeg

The installer first detects an existing executable from:

1. saved configuration;
2. Elysium Player managed directory;
3. system PATH.

If missing, Elysium Player installs a managed build.

Windows source:

```text
BtbN FFmpeg Builds
ffmpeg-master-latest-win64-lgpl.zip
```

Intel macOS source:

```text
evermeet.cx FFmpeg static Intel build
```

After extraction Elysium Player verifies `ffmpeg -version`.

### Whisper runtime

Whisper is included in the Elysium Player managed ASR runtime bundle. The bundle is
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
download percentage, transferred bytes, speed and remaining-time estimate. If
preparation fails, the progress display is explicitly marked as incomplete and
cannot show a success-like 100%. The setup dialog and transcription settings
allow copying or selecting the full diagnostic message for troubleshooting.

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
may otherwise fall back to direct access if no static proxy is available. The “Test download connection” action checks the Whisper large-v3 file plus the selected profile's Qwen ASR and ForcedAligner model files on both official Qwen sources. It uses the same configured HTTP proxy as the downloader.

For each Hugging Face model file, the preflight checks both the non-redirecting
`HEAD` response that installation uses to obtain a trustworthy ETag/size and a
one-byte `Range GET` through the download redirect. For each ModelScope model,
it checks the repository-file manifest, requires the exact weight filename and
SHA-256, and separately checks the file endpoint with a one-byte range request.
Qwen ASR and ForcedAligner are reported independently because either may be
available through a different official source. The active profile selects
Qwen3-ASR 1.7B on RTX 5080 or 0.6B on Intel Mac; the ForcedAligner remains 0.6B.

This avoids false positives where a file URL responds but the metadata needed to
start installation, or the other required model repository, is unavailable.
The test checks metadata and real response-body paths without downloading
gigabytes. Hugging Face large files may redirect to separate `hf.co` storage/CDN
hosts. The probe is not a full model download or runtime-load test.

Managed Qwen downloads prefer Hugging Face. If its file metadata cannot be read,
Elysium Player tries the official ModelScope manifest API. If an actual Hugging Face
file download fails, Elysium Player checks the matching ModelScope manifest. When
both sources agree on size and known SHA-256, a compatible partial can continue.
When their metadata differs, the Hugging Face partial is discarded and the
affected file is downloaded from byte zero using a ModelScope-specific partial
file, then verified against ModelScope's own size and SHA-256. Partials are
source-specific: a ModelScope retry may resume its own earlier partial, but it
never appends to a Hugging Face partial, even when the metadata matches. A failed
or inconsistent checksum still rejects the file. The same configured HTTP proxy
is used for both sources.
The proxy can be saved independently from model/runtime paths; an incomplete
recognition profile is reported inside Advanced Settings and does not block
saving the proxy.

### Qwen3-ASR runtime

The upstream Rust/Candle Qwen3-ASR project currently does not publish a normal
end-user binary release suitable for the Elysium Player setup wizard.

Elysium Player therefore builds managed runtime bundles itself from a pinned source
revision.

Runtime release tag:

```text
asr-runtime-v3
```

Assets:

```text
lyricforge-asr-runtime-windows-x64-cuda.zip
lyricforge-asr-runtime-macos-x64.zip
```

The application downloads only the asset matching the resolved hardware
profile.

The pinned upstream revision has an eager audio-attention layout issue: it
materializes the transposed Q/K/V tensors only for Metal, while this runtime's
Windows CUDA backend can reject the same strided views during the first
attention matmul. The runtime build applies
`tool/patches/qwen3-asr-eager-attention-contiguous.patch` to both platform
bundles, making those attention inputs contiguous on every backend. The macOS
runtime job runs a focused Rust regression test against non-contiguous Q/K
views before packaging the bundle.

The fix is published under the separate `asr-runtime-v2` tag. Each bundle
manifest records the patch revision, and the installer rejects archives that
lack the expected revision. Existing managed installs without a matching
revision marker are detected as outdated; one-click repair downloads the patched
runtime, stages and verifies it before replacing the current bundle, preserves
the downloaded model weights, and invalidates the old Qwen model-readiness
marker so native startup and health checks run again.

`asr-runtime-v3` additionally applies
`tool/patches/qwen3-asr-session-auth.patch` (revision suffix
`+session-auth-v1`). It adds the `--lyricforge-session-stdin` serve mode. In
this mode the runtime reads a per-launch secret from stdin, binds
`127.0.0.1:0` itself (with `SO_EXCLUSIVEADDRUSE` on Windows), announces the
bound port with an HMAC proof on stdout, requires HMAC-signed requests on every
route, signs every response, and exits when stdin closes. Both platform jobs
run the patch's Rust unit tests and the `session_auth_integration` tests
against `serve --mock` before packaging. Elysium Player refuses to start a runtime
that does not understand the flag, so `asr-runtime-v2` bundles are reported as
outdated and must be repaired. See "Local ASR runtime trust boundary" in the
README for the threat model.

The rolling `asr-runtime-v3` release also applies
`tool/patches/qwen3-asr-skip-unalignable-chunks.patch` (D-024). With
timestamps on, the pinned runtime aligns every chunk's text, and it fails the
whole request with HTTP 500 "tokenized word_list is empty" when a chunk decodes
to punctuation only. That happens with a sub-second tail, or with a lone "."
over an instrumental. The patch skips such chunks the same way empty ones are
skipped. Both platform jobs apply it after the session-auth patch, and the
bundle manifest lists it under `behaviorPatches`.

The patch is not part of `runtimePatchRevision`, the compatibility marker the
installer compares. Elysium Player does not depend on it: with a bundle built
before the patch, it retries the request once with 180 s chunks. Existing
installs therefore stay valid and do not need a repair. They pick up the patch
the next time the runtime is installed or repaired.

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

For the managed profiles, Elysium Player downloads the model repository files
itself. Large files are first written as `.part` files and use HTTP Range when
the server supports it, so an interrupted download can continue instead of
starting from zero.

After all required files are present, Elysium Player stores them under
`ASRRuntime/models/qwen/` and rewrites the machine-local transcription config
to those local model directories. The native Qwen sidecar therefore receives a
local `--model` path and a local `--forced-aligner` path instead of depending on
a hidden user-level Hugging Face cache.

During setup Elysium Player then starts the native sidecar and waits for `/healthz`.
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

## Deterministic downloader regression coverage

The test suite runs the managed Qwen downloader against a small local HTTP
server. It exercises real Dart HTTP requests for Hugging Face metadata, an
HTTP failure that triggers the official ModelScope manifest/file fallback,
valid byte-range continuation of an existing `.part` file, checksum-verified
promotion to the final filename, and rejection when source checksums disagree.
These tests do not download the real model files or replace the manual Windows
RTX 5080 acceptance test for a complete download and native dual-engine load.

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
create or update the rolling `asr-runtime-v3` prerelease.

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
