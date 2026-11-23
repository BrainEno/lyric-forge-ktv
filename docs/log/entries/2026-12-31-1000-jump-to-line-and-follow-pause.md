# [2026-12-31 10:00] Jump to a lyric line and pause following while browsing

- Scope: round 47, user request: friendlier UI, chosen area 歌词校对：Ctrl+G 跳行 + 跟随播放可手动滚动 (D-067).
  - Domain: `LyricLineLocator.locate(document, text)` reads a row number (`45`, `第 45 行`, `#45`, full-width digits) or a time (`1:05`, `65s`, `65 秒`, `65.5`) and `rowAt(document, time)` picks the row sung then (latest-starting covering row, else the next row, else the last); `LyricLineLocation` carries the row, the time or the problem in words.
  - `lyric_line_jump.dart`: `LyricJumpToLineDialog` / `showLyricJumpToLineDialog` (live preview, error text, confirm disabled until valid, prefilled with the selected row), `LyricLineJumpController` (request id + target), `LyricLineJumpHost` (keeps one controller for the stateless editor content), `LyricJumpStrings`, `LyricListFollowStrings`.
  - Content: Ctrl/⌘+G through `LyricEditShortcuts.onJumpToLine`, 跳到行 at the top of `LyricEditorOverflowMenu` (`jumpToLineKey`); a hidden row resets the filter to all; the row is selected with `review.onSelectLine` (no sheet on phones).
  - List pane: every row is wrapped in `_ListRowFrame` (records its context for measuring, flashes after a jump, same structure for every row so no row state is lost); `_reveal` measures with `RenderAbstractViewport.getOffsetToReveal`, or estimates by the average row height and measures again (up to `revealAttempts`); a jump clears a search that hides the row and focuses the list; ↑/↓ keep the selected row visible (`keepVisibleOffset`).
  - Following: user drags, flings, wheel and scroll-bar drags (`UserScrollNotification` with a direction, `ScrollUpdateNotification` with drag details), arrow keys and jumps pause it for `followPause` (5 s, restarted each time); a playhead move meanwhile shows 回到正在播放的第 N 行 (`LyricListPane.resumeFollowKey`) and is caught up when the pause ends; a paused song never snaps back; inline editing defers following until the edit ends. Following now measures the playing row instead of assuming 68 px rows; `LyricListNavigation.followTarget` was removed with its tests.
  - Toolbar: the 跟随播放 chip explains the pause in its tooltip. Shortcut panel: Ctrl/⌘+G in the 歌词校对 group.
- Files:
  - New: `lib/features/lyrics/domain/services/lyric_line_locator.dart`, `lib/features/lyrics/presentation/widgets/lyric_line_jump.dart`.
  - Changed: `lib/features/lyrics/presentation/widgets/{lyric_list_pane,lyric_list_logic,lyric_editor_content,lyric_edit_shortcuts,lyric_editor_toolbar}.dart`, `lib/features/search/domain/keyboard_shortcut_catalog.dart`.
  - Tests: `test/features/lyrics/domain/services/lyric_line_locator_test.dart`, `test/features/lyrics/presentation/widgets/lyric_line_jump_test.dart`, `test/features/lyrics/presentation/screens/lyric_editor_jump_to_line_test.dart`, `test/features/lyrics/presentation/widgets/{lyric_list_logic_test,lyric_edit_shortcuts_test}.dart`.
  - `docs/decisions.md` (D-067), `docs/handoff.md`, `docs/lyric_proofreading_ux_review.md` §6 items 6 and 9.
- Validation:
  - No Dart SDK in the sandbox; format, analyze and tests run in a temporary branch CI probe.
- Notes:
  - The editor screen is unchanged (1198 lines); everything is wired in the content widget.
  - Times typed in the box are lyric times as the list shows them, not shifted by the global offset.
- Commit: `Jump to a lyric line and let following wait while browsing`
