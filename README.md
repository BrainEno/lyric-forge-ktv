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

The iOS app uses CocoaPods for Flutter plugin modules such as `audio_service`,
`audio_session`, `just_audio`, and `file_picker`.

After pulling dependency changes, refresh the generated Flutter/CocoaPods files:

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
