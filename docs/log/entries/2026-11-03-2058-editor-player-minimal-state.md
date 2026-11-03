# [2026-11-03 20:58] Add scoped state management for editor and player bars

- Scope: Introduce observable editor document state and a scoped provider for the existing playback-session stream. Preserve service ownership, editing semantics, and the local-only nature of transient UI state.
- Files: `pubspec.yaml`, `pubspec.lock`, `lib/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart`, `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, `lib/features/player/presentation/widgets/global_player_bar.dart`, `lib/features/player/presentation/widgets/mobile_global_player_bar.dart`, `lib/features/player/presentation/widgets/playback_mode_controls.dart`, `lib/features/player/presentation/widgets/playback_queue_panel.dart`, `lib/features/player/presentation/widgets/playback_session_state_scope.dart`, `test/features/lyrics/presentation/controllers/lyric_editor_document_controller_test.dart`, `test/features/player/presentation/widgets/playback_session_state_scope_test.dart`, `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md`, `docs/handoff.md`, and generated work-log navigation files.
- Validation:
  - `flutter pub get --enforce-lockfile` => passed.
  - `dart format` on changed Dart files => passed.
  - `bash scripts/quality_gate.sh --skip-pub-get` => passed (changed-file format gate, analyzer, full test suite, and work-log preflight; workflow run 41639843885).
  - `dart tool/work_log.dart write` and `dart tool/work_log.dart check` => passed.
  - No real-song accuracy or physical-device playback result is claimed.
- Notes: The document controller now notifies after completed observable changes; project loading initializes it before the listening subtree builds. Desktop playback chrome forwards the existing session snapshot to its queue/mode controls, while mobile and desktop keep audio playback state on the existing audio stream. ASR algorithms and lyric-processing semantics are unchanged.
- Commit: `feat: add scoped state providers for editor and playback chrome`
