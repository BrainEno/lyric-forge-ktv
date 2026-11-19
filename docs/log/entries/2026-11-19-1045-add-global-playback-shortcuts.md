# [2026-11-19 10:45] Add global playback shortcuts

- Scope: UI/UX audit A-02. Desktop playback could only be controlled with the mouse outside the lyric timing dialogs. `GlobalPlaybackShortcuts` wraps the routed shell (inside the lyric-availability sync) and maps Space to play/pause, Ctrl/⌘ + → / ← to next/previous song and Shift + → / ← to a 5-second skip, clamped to the song. The desktop player bar tooltips name the keys ("暂停（空格）", "下一首（Ctrl+→）", "⌘" on macOS).
- Files:
  - `lib/features/player/presentation/widgets/global_playback_shortcuts.dart` (new: `commandFor`, `run`, `withHint`).
  - `lib/app/app.dart` (mounts it around the routes when services are initialised), `global_player_bar.dart` (tooltips with key hints).
  - Test: `test/features/player/presentation/widgets/global_playback_shortcuts_test.dart` (new: real key events, text field, focused button, empty queue, last song, seek clamping, hints).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. `app_assembly_contract_test` still finds `buildPlaybackLyricsResolver(services)` in `app.dart`.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The handler is a non-focusable `Focus` ancestor, so it only sees keys the focused widget declined: text fields keep Space and arrows (`DefaultTextEditingShortcuts` stops them), the tap-sync / word-tap / word-timing dialogs keep theirs (they return `handled`), and Space toggles playback only while a focus scope rather than a control is focused, so a keyboard-focused button still activates.
  - Hardware media keys are not handled here; the system media handler already receives them and handling both would toggle twice.
  - Keys pass through unhandled when the queue is empty or there is no next song.
  - Slightly above the 300-line guideline (about 155 lines of code, 190 of tests); the code is one goal and splitting the tests off would leave it unverified.
- Commit: `Add global playback shortcuts`
