# [2026-11-26 11:10] Answer library section presses

- Scope: Round 9 feedback that 收藏, 歌单 and the other library sections felt unresponsive. The section strip in `LocalMusicLibraryShell` swapped the body in a single frame and ignored a press on the open section. Each section press now bumps a per-section counter that pulses the chip icon with `AppTapPulse` (peak 1.3) and gives a selection click, including a press on the section already open. The body fades and rises in over 220 ms when the section changes (skipped for reduced motion, and not replayed for a re-press). When a section is opened from elsewhere (the router changes `initialIndex`, e.g. 歌单 from the player bar) the narrow, scrolling strip brings that chip into view.
- Files:
  - `lib/features/player/presentation/screens/local_music_library_shell.dart` (`_select`, stateful `_SectionStrip` with chip keys and `_revealSelected`, new `_SectionSwitcher`).
  - `test/features/player/presentation/screens/local_music_library_shell_test.dart` (new group: pulse wrappers, pulse and selection click on a press and a re-press, body fade, no fade on re-press, reduced motion, strip scrolled to an externally opened section).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The sections stay in an `IndexedStack`, so scroll positions and loaded lists survive the switch as before.
- Commit: `Answer library section presses`
