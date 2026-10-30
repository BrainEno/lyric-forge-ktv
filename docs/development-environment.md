# Flutter and Dart development environment

## Single source of truth

The repository's active SDK pin is `.fvmrc` (`flutter: 3.47.7`). GitHub Actions reads this file through `.github/actions/setup-flutter/action.yml`; contributors should use the same Flutter installation because `dart format` is bundled with the Dart SDK that ships with Flutter.

The `.metadata` revision records Flutter project creation/migration provenance. It is not the active version selector; do not choose a different SDK solely from that revision. The canonical active pin is `.fvmrc`.

## Verify before formatting or testing

On macOS/Linux/Git Bash:

```bash
bash scripts/check_flutter_sdk.sh
dart format --output=none --set-exit-if-changed <changed-dart-files>
bash scripts/quality_gate.sh
```

On Windows PowerShell:

```powershell
.\scripts\check_flutter_sdk.ps1
dart format --output=none --set-exit-if-changed <changed-dart-files>
.\scripts\quality_gate.ps1
```

The SDK check validates the Flutter version against `.fvmrc`, reads Flutter's bundled `dartSdkVersion` from `flutter --version --machine`, and rejects a `dart --version` on `PATH` that does not match. The shell and PowerShell quality gates run this check before the work-log lint, dependency resolution, analysis, or tests. The iOS preparation and Android APK build scripts also run it before modifying/building project outputs.

If the check fails, update your local Flutter/Dart selection to the version in `.fvmrc`; do not work around it by formatting with another `dart_style` version. CI uses the same check after installing the pinned SDK.

