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

For the normal local workflow, use the repository helper:

```bash
./ios-dev build --run
```

It discovers active iPhones and iOS Simulators, shows an interactive terminal
picker, and starts a Debug build on the selected device. Use Up/Down to move,
Space to select, and Enter to confirm and run.

Useful variants:

```bash
./ios-dev devices              # list active iOS devices
./ios-dev run                  # shortcut for ./ios-dev build --run
./ios-dev build                # build iOS Debug without launching
./ios-dev build --simulator    # build a Debug Simulator app
./ios-dev build --run --clean  # clean first, then select a device and run
./ios-dev build --device <id> --run  # skip the picker
```

The helper keeps subsequent runs fast by reusing Flutter build artifacts and
only runs `flutter pub get` when the dependency configuration is stale. If no
iOS device is active, it attempts to open Simulator and retries device discovery.

The iOS app uses CocoaPods for Flutter plugin modules such as `audio_service`,
`audio_session`, `just_audio`, and `file_picker`.

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
