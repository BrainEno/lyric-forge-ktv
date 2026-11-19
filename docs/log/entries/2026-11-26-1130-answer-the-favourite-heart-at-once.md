# [2026-11-26 11:30] Answer the favourite heart at once

- Scope: Round 9 feedback that 收藏 felt unresponsive, for the heart itself. `LocalFavoriteButton` (player bar, album rows) disabled itself for every write and every reload, so a press greyed the heart for a moment and only then changed it. It now updates optimistically: the heart fills or empties on the press, fills in the accent (the button is `isSelected`, which the theme colours), pulses when it fills, and gives a selection click. The store's answer confirms it; a failed write puts the heart back and keeps the existing snack bar. A second press while a write is in flight is ignored, a reload caused by the write cannot undo the optimistic state, and the heart is disabled only until the first load has answered.
- Files:
  - `lib/features/player/presentation/widgets/local_collection_actions.dart`.
  - `test/features/player/presentation/widgets/local_favorite_button_test.dart` (new: immediate fill while the write is pending, accent and grey hearts, pulse on fill only, selection click, ignored second press, rollback with the snack bar, disabled before the first load).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The snack bar still goes through `ScaffoldMessenger.maybeOf`; `MaterialApp` puts the messenger above the chrome, so it reaches the page's scaffold from the player bar too.
- Commit: `Answer the favourite heart at once`
