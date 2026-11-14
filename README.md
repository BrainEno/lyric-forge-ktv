# LyricForge KTV

**A local-first music player, lyric workspace, and KTV production toolkit built with Flutter.**

LyricForge combines everyday local music playback with editable synchronized lyrics and desktop-first tools for transcription, alignment, and KTV recording. Your library and project files remain local; online access is needed only for tasks such as downloading runtimes or models.

## Features

- **Local music library and playback** — import local files, browse metadata and artwork, manage a queue, favorites and playlists, and resume recent listening.
- **Editable lyrics** — import and export LRC, adjust global timing offsets, audition individual lines, review alignment proposals, and keep manual edits protected from automatic suggestions.
- **KTV workflow** — practice with the original mix or an accompaniment track already referenced by a project, record and monitor a microphone on supported desktop setups, and work with take history and mix/project exports.
- **Local transcription and alignment** — desktop workflows can use Whisper.cpp and Qwen3-ASR with Qwen ForcedAligner. FFmpeg is used for consistent audio preparation. Recognition output is a draft for human review, not guaranteed ground truth.
- **Desktop-to-mobile Media Hub** — pair devices through the app, confirm the sharing scope, and transfer/play shared media over fingerprint-pinned HTTPS on a trusted private LAN or Tailscale network.
- **Offline-first design** — no cloud music catalog or mandatory cloud transcription service is required for normal local playback.

## Platform overview

| Platform | Intended use | Notes |
| --- | --- | --- |
| Windows desktop | Full local playback/library and KTV production workflow | Highest-quality ASR profile targets compatible Windows x64 runtimes; NVIDIA CUDA is supported when the matching runtime and model files are installed. |
| macOS desktop | Local playback/library and supported production workflows | Native runtime and device behavior depend on the installed build and CPU architecture. |
| Linux desktop | Local playback/library | Audio backend availability depends on the installed system libraries and packaged plugins. |
| Android | Mobile playback, library, synced lyrics, and Media Hub connectivity | Desktop-only transcription, source separation, and KTV recording flows are not promised on mobile. |
| iOS | Mobile playback, library, synced lyrics, and Media Hub connectivity | Building requires macOS, Xcode, and CocoaPods. |

Availability of ASR, microphone, native playback, and packaging features varies by operating system and installed runtime. Check the platform-specific requirements before relying on a production workflow.

## Install or run

If a release build for your platform is published, use the repository's **Releases** page. Otherwise, build from source:

1. Install Flutter **3.47.7**, the version pinned in [`.fvmrc`](.fvmrc). Use the Dart SDK bundled with that Flutter installation so `dart format` matches CI.
2. Install the platform toolchain required by Flutter (`flutter doctor -v` reports missing components).
3. Clone the repository and restore packages:

   ```bash
   git clone https://github.com/BrainEno/lyric-forge-ktv.git
   cd lyric-forge-ktv
   flutter --version
   flutter pub get
   ```

4. Inspect available devices and launch the app:

   ```bash
   flutter devices
   flutter run -d windows
   ```

   Replace `windows` with a device ID reported by `flutter devices` for your target platform.

### Desktop builds

```bash
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

Run a build only on a host with the corresponding platform toolchain installed.

### Android build

```powershell
.\scripts\build_android_apk.ps1 -Mode release
```

The helper copies the generated APK to `release/android` and writes a SHA-256 sidecar. Review its signing warning before distribution; a local debug-signed package is suitable for testing, not an app-store release.

### iOS build

On macOS, install Xcode and CocoaPods, then run:

```bash
flutter pub get
cd ios
pod install
cd ..
flutter build ios --no-codesign
```

When using Xcode, open `ios/Runner.xcworkspace` rather than `Runner.xcodeproj` so the CocoaPods workspace is loaded. A signed device build requires the appropriate Apple development team and signing setup.

## Local ASR requirements

Transcription and alignment runtimes and model weights are separate from the normal music-player experience. Use the application's runtime/setup workflow for supported platforms, and allow enough disk space for the models and normalized audio. Model downloads require network access; inference runs locally once the required assets are installed.

Highest Quality mode can combine a full-song Whisper transcript with a Qwen3-ASR second opinion and forced alignment on supported desktop configurations. It favors evidence and reviewability over minimum runtime. Compare results with a manually checked reference before judging lyric recall or timestamp accuracy.

## Media Hub security

Media Hub sharing is stopped until you explicitly confirm the sharing scope. Pairing pins the desktop's HTTPS certificate fingerprint; requests use Bearer authorization, and listeners are restricted to detected private-LAN/Tailscale IPv4 addresses. Do not expose the service through an untrusted public interface. Browser-based clients are not supported.

Authenticated incoming uploads accept only the local library's audio filename extensions (MP3, FLAC, WAV, M4A, AAC, and OGG). This is a filename check, not content validation or malware scanning; only pair with devices you trust.

## Local ASR runtime trust boundary

The desktop app runs Qwen3-ASR and the ForcedAligner in a separate native process (`qwen3-asr serve`) and talks to it over loopback HTTP. The trust boundary is that process's HTTP listener. Before this change, any local process could reach it and ask it to read arbitrary file paths.

- **Who is trusted.** Only the LyricForge process that started the runtime. Other local processes, browser pages, other users and the network are untrusted. Media Hub pairing and its Bearer token are unrelated and do not grant access to this API.
- **Authentication.** For every launch, LyricForge generates a fresh 256-bit secret with `Random.secure()` and writes it to the child's **stdin** (`--lyricforge-session-stdin`). The secret is never put on the command line, in an environment variable, in a URL, in a log or on disk. Each request carries an HMAC-SHA256 signature over the method, path, timestamp, a random nonce and the SHA-256 of the body. The runtime checks the signature before any route handler runs, including `/healthz` and CORS preflights. It also rejects stale timestamps (±120 s) and replayed nonces, and answers everything else with `401` and `Connection: close`. Session mode removes the permissive CORS layer.
- **Server identity.** The runtime signs every response (nonce, status and body hash) with the same secret. The client discards any body without a valid proof, so a plain `200 OK` from whatever owns the port is never trusted. If a running session returns an unproven response, LyricForge stops that runtime.
- **Port ownership.** LyricForge no longer reserves a port and then releases it. The runtime binds `127.0.0.1:0` itself and reports the bound port, together with an HMAC proof, on its private stdout pipe. On Windows the listener sets `SO_EXCLUSIVEADDRUSE` before `bind`, so a same-user process cannot co-bind with `SO_REUSEADDR`. macOS and Linux never enable `SO_REUSEPORT` on the listener, so a second bind fails. The launcher refuses non-loopback `--host` values. All platforms use one launch interface (`QwenRuntimeLauncher`) with a small platform policy adapter.
- **Credential lifecycle.** The secret lives only in the memory of the two processes. It is zeroed on the Dart side when the session closes, fails, is cancelled, idles out, changes configuration or is disposed, and when the runtime exits. A restarted runtime always gets a new secret, so the old one is useless. When LyricForge exits or closes the pipe, the runtime sees EOF on stdin and terminates.
- **Fail closed.** If the runtime does not prove its identity, the launch fails with an environment error. This covers a missing proof, a squatted port, a forged ready line and an unpatched runtime. In every such case no audio path, lyrics or context is sent, and the child process is terminated.

Threat model and known limits:

- Mitigated: other local processes and users calling `/v1/transcribe`, `/v1/align` or other routes; port squatting and fake `/healthz` responders; replaying captured requests; drive-by requests from browser pages; reusing a secret from a previous session.
- Not mitigated: any code running as the **same OS user** that can read LyricForge's or the runtime's memory, attach a debugger, inject into either process, or replace the runtime binary. Such code can obtain the secret, and the OS gives no isolation between same-user processes for this. Loopback HTTP is unencrypted, but it never leaves the machine, so this requires the same local privileges. Use OS account separation for untrusted software.
- The protection requires a runtime built with `tool/patches/qwen3-asr-session-auth.patch` (release `asr-runtime-v3`). Older managed runtimes are detected as outdated and must be repaired or updated. LyricForge does not fall back to unauthenticated mode.

## Development and tests

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request. The active Flutter SDK pin is `.fvmrc`; CI uses the shared setup action. Common checks are:

```bash
flutter analyze --no-pub --no-fatal-infos lib test
flutter test
dart tool/work_log.dart check
```

The active Flutter version is recorded in [`.fvmrc`](.fvmrc). Read [`CONTRIBUTING.md`](CONTRIBUTING.md) for contribution, validation, and work-log expectations; the full architecture and engineering rules are in [`AGENTS.md`](AGENTS.md).

## Project layout

- `lib/features/` — feature modules, each split into presentation, domain, and data layers.
- `lib/core/` — shared application infrastructure and responsive layout.
- `packages/` — maintained local plugin integration/forks used by the application.
- `scripts/` — development, build, and quality-gate helpers.
- `docs/` — architecture, environment setup, work log, and engineering decisions.

## Scope and limitations

LyricForge is an actively developed open-source project. Automatic transcription and alignment are review aids; they can omit words, select incorrect alternatives, or produce inaccurate timestamps. Native audio behavior, microphone latency, device pairing, and packaged ASR runtime availability should be verified on the target device before a long recording session.

The current app cannot generate separated vocal/accompaniment tracks; source separation remains a planned desktop capability. On desktop, project details can import an existing accompaniment file or an existing vocal stem into app storage. The accompaniment can be used for KTV playback; the vocal stem is preferred for transcription and forced alignment. Choose tracks aligned with the original song: the app does not synchronize or verify their contents. The referenced file must be accessible for playback; otherwise use the original mix. If that project is already playing, switch to another song and reopen the project player to load the new track.

## License

LyricForge is distributed under the [MIT License](LICENSE). Third-party dependencies and local plugin integrations retain their respective licenses.

