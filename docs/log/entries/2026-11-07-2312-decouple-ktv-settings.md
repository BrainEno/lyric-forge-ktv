# [2026-11-07 23:12] Decouple KTV export from transcription settings

- Scope: Remove player to transcription dependency by injecting the KTV FFmpeg setting at app assembly, preserving export and settings behavior.
- Files: KTV recording service and assembly, app services, dependency graph baseline and tests, KTV export tests and fixture, work-log navigation and handoff.
- Validation:
  - Pinned Flutter GitHub Actions run 43014094131 passed locked dependency install, dart format, focused KTV/architecture tests and flutter analyze --no-pub --no-fatal-infos lib test tool.
  - Work-log write/check run separately; inspect final PR checks. Local Flutter/Dart unavailable.
- Notes: Tests use real temporary files and persisted settings but a fake FFmpeg process; actual audio output, native hardware and platform-specific behavior were not validated. Other feature cycles remain.
- Commit: `Inject KTV FFmpeg settings through app assembly`
