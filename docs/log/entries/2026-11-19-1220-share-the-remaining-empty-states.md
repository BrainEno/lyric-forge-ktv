# [2026-11-19 12:20] Share the remaining empty states

- Scope: UI/UX audit follow-up to C-05. Four private empty widgets were left after round 3: the dashboard's `_EmptyCard` (empty and failed shelves), the lyric list's `_ReviewQueueEmptyState` and `_FilteredEmptyState`, and the transcription queue's `_EmptyQueueState`, each with its own icon size, spacing and text styles. `AppEmptyState` gains an `inline` density for cards (icon, title and message in a row, actions at the end, stacked under the text when the card itself is compact) and the four widgets now render through it. The dashboard's failed shelves use the error colour instead of the muted one. When a filter hides every lyric line, both lyric-list empty states offer 显示全部歌词, wired to the editor's filter; the filtered state also explains what to do.
- Files:
  - `lib/core/widgets/app_empty_state.dart` (`AppEmptyStateDensity.inline`, `inlineIconSizeFor`, `inlineStacksActions`, `_buildInline` with status and footer).
  - `lib/features/home/presentation/screens/dashboard_screen.dart` (`_EmptyCard` keeps the card frame, adds `isError`).
  - `lib/features/lyrics/presentation/widgets/lyric_list_pane.dart` (`onShowAllLines`, `_showAllActions`, both states on `AppEmptyState`).
  - `lib/features/lyrics/presentation/widgets/lyric_editor_content.dart` (passes `onFilterChanged(LyricReviewFilter.all)`).
  - `lib/features/transcription/presentation/widgets/transcription_queue_panel.dart` (`_EmptyQueueState` on the panel density).
  - Tests: `test/core/widgets/app_empty_state_test.dart` (inline row vs. stacked by card width, heading semantics, no actions), `test/features/lyrics/presentation/widgets/lyric_list_pane_test.dart` (show-all action in both states, absent without a callback), `test/features/home/presentation/screens/dashboard_screen_test.dart` (both shelves use the inline density; error colour only on failures).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Copy, retry buttons (still `OutlinedButton` 重试) and the existing finders in the dashboard and list-pane tests are unchanged.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The inline density measures the card, not the window, so a narrow card on a wide screen stacks too; before, the dashboard checked the card width for this already.
- Commit: `Share the remaining empty states`
