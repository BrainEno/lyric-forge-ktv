# lyric_forge_ktv

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## iOS local build

The repository helper is **iOS Dev** and lives under `Scripts/`:

```bash
./Scripts/ios-dev build --run
```

For run commands, `flutter devices --machine` is the authority for targets that
Flutter can actually launch. `devicectl` is used only to diagnose physical iOS
devices that Xcode can see but Flutter cannot yet use, while `simctl` is used to
show installed simulators and boot a selected shutdown simulator.

The picker is intentionally single-select: use Up/Down to move, Enter to run,
and `q` to cancel. A shutdown Simulator is booted first and then must appear in
Flutter's device list before `flutter run` starts. A physical iPhone that is only
visible to Xcode/devicectl is shown as `Flutter unavailable`; iOS Dev retries
Flutter discovery and prints Xcode/device/`flutter doctor -v` diagnostics instead
of passing a system-only identifier to `flutter run`.

Useful variants:

```bash
./Scripts/ios-dev devices                 # show Flutter/Xcode iOS target status
./Scripts/ios-dev run                     # select one target and run Debug
./Scripts/ios-dev build --run             # same fast run path; no redundant pre-build
./Scripts/ios-dev build                   # build physical-device Debug (signing required)
./Scripts/ios-dev build --simulator       # build Simulator Debug
./Scripts/ios-dev build --run --clean     # clean explicitly, then run
./Scripts/ios-dev run --device <id>       # skip the picker; ID is still validated
```

The helper keeps development runs fast by reusing Flutter incremental build
artifacts. It does not run `flutter clean` unless `--clean` is provided, and it
only runs `flutter pub get` when `pubspec.yaml` / `pubspec.lock` are newer than
the local package configuration.

The iOS app uses CocoaPods for Flutter plugin modules such as `audio_service`,
`audio_session`, `just_audio`, and `file_picker`. iOS Dev checks for Flutter,
full Xcode, Xcode first-launch/license readiness, and CocoaPods before a build or
run. It never runs `sudo` automatically; if the active developer directory is
wrong it prints the `xcode-select --switch` command for the developer to review.

After pulling dependency changes, if CocoaPods needs a manual refresh, run:

```bash
flutter clean
flutter pub get
cd ios
pod install --repo-update
cd ..
open ios/Runner.xcworkspace
```

Build the app from `Runner.xcworkspace`, not `Runner.xcodeproj`. Opening the
project file directly does not load the CocoaPods workspace, which can surface
errors such as `Module 'audio_service' not found` in
`GeneratedPluginRegistrant`.

If Xcode still shows a stale plugin-module error, reset the local pods once:

```bash
flutter clean
rm -rf ios/Pods ios/Podfile.lock
flutter pub get
cd ios
pod install --repo-update
cd ..
open ios/Runner.xcworkspace
```
