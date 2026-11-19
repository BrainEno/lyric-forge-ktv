# [2026-11-25 11:30] Pass the editor groups to the child panes

- Scope: UI/UX audit E-04 follow-up. Round 6 grouped the `LyricEditorContent` inputs, but the content still unpacked the groups again for its children: the toolbar took 21 arguments (eight of them the proofreading callbacks one by one, two the loop toggle), and the 校对 menu was built twice with the same twenty-argument mapping from `LyricBatchTextTool` to menu entries, once in the toolbar and once in the narrow app bar. `LyricProofreadMenuButton.forActions` now owns that mapping once; `LyricEditorToolbar` takes the `LyricProofreadActions` group (default `none`) and the `LyricAuditionControls` group instead (13 arguments); `InspectorPane` takes the `LyricLineEditActions` group instead of five row-edit callbacks, keeping only the split callback separate because the content binds the paused playhead into it first.
- Files:
  - `lib/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart` (`forActions` factory).
  - `lib/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart` (`proofread` and `audition` groups; local `_batchTool` mapping removed).
  - `lib/features/lyrics/presentation/widgets/lyric_inspector_pane.dart` (`edits` group).
  - `lib/features/lyrics/presentation/widgets/lyric_editor_content.dart` (passes the groups through).
  - `test/features/lyrics/presentation/widgets/lyric_editor_toolbar_test.dart` (constructions updated; loop chip reads and writes the audition group; the proofread group reaches the menu with batch tools routed by kind; no menu for `none`).
  - `test/features/lyrics/presentation/widgets/lyric_proofread_menu_button_test.dart` (`forActions`: every batch tool maps to its own entry and word timing editing stays out of the menu; document-level callbacks pass through; an empty group renders nothing).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the widget tests run in the PR's Flutter Quality Gate and the temporary format probe.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - `LyricListPane` keeps its flat parameters: its callbacks are row-indexed list gestures (tap, double tap, review toggles) rather than any of the existing groups.
- Commit: `Pass the editor groups to the child panes`
