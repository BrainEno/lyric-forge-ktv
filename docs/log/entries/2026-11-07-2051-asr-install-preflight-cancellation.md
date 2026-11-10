# [2026-11-07 20:51] Guard ASR installation preflight cancellation

- Scope: Avoid starting ASR downloads after cancellation during installation preflight and reject overlapping installs on the same manager.
- Files: Storage preflight runtime manager, cancellation tests, handoff, generated work log, index and archive.
- Validation:
  - dart format changed Dart files => passed on pinned SDK.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed on pinned SDK.
  - flutter test --no-pub storage_preflight_install_cancellation_test.dart asr_storage_preflight_test.dart asr_runtime_health_test.dart (full paths under test/features/transcription/) => passed on pinned SDK.
- Notes: Cancellation waits for in-flight preflight operations; it cannot undo invalidation or cleanup. Shared-caller ownership, external UI preflight, isInstalling visibility, resource leases, and real-device validation remain follow-ups.
- Commit: `Guard cancellation during ASR installation preflight`
