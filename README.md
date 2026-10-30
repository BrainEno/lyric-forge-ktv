# LyricForge KTV

**A local-first music player, lyric workspace, and KTV production toolkit built with Flutter.**

LyricForge combines everyday local music playback with editable synchronized lyrics and desktop-first tools for transcription, alignment, and KTV recording. Your library and project files remain local; online access is needed only for tasks such as downloading runtimes or models.

## Features

- **Local music library and playback** — import local files, browse metadata and artwork, manage a queue, favorites and playlists, and resume recent listening.
- **Editable lyrics** — import and export LRC, adjust global timing offsets, audition individual lines, review alignment proposals, and keep manual edits protected from automatic suggestions.
- **KTV workflow** — switch between accompaniment and vocal playback, record and monitor a microphone on supported desktop setups, and work with take history and mix/project exports.
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

## License

LyricForge is distributed under the [MIT License](LICENSE). Third-party dependencies and local plugin integrations retain their respective licenses.

