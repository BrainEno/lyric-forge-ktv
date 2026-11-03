# [2026-11-03 22:15] Defer immersive chrome notifications

- Scope: Fix the KTV screen lifecycle assertion where `AppChromeController.enterImmersive()` notified the app-level `ValueListenableBuilder` from `ImmersiveKtvScreen.initState`; defer both enter and exit notifications until after the frame and guard a pending enter if the screen is disposed first.
- Files: `lib/features/player/presentation/screens/immersive_ktv_screen.dart`, `test/features/player/presentation/screens/immersive_ktv_recording_test.dart`, `docs/work_log_index.md`, `docs/handoff.md`, and generated work-log navigation files.
- Validation:
  - `dart format` on changed Dart files => passed.
  - `flutter test test/features/player/presentation/screens/immersive_ktv_recording_test.dart` => passed, including ancestor-listener enter/exit regression.
  - `bash scripts/quality_gate.sh --skip-pub-get` => passed (analyzer, full test suite, work-log preflight; CI run 41651784524).
  - `dart tool/work_log.dart write` and `dart tool/work_log.dart check` => passed.
- Notes: App chrome remains hidden during the immersive route and restored on exit, but changes no longer synchronously dirty an ancestor during mount/unmount. No lyric editing, playback, recording, or recognition semantics changed; no physical-device result is claimed.
- Commit: `fix: defer immersive chrome notifications until frame end`
