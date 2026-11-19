# [2026-11-24 12:40] Let the narrow line inspector sheet resize

- Scope: UI/UX audit E-05. On narrow layouts the line inspector opened in a modal sheet fixed at 88 % of the screen (96 % on short screens), so the lyric list the user was reviewing disappeared behind it and there was no way to see the surrounding lines while editing one. The new `LineInspectorSheet` opens at 62 % and shows 上一行 / 下一行 above the inspector for context; it rests at 40 %, 62 % or 92 % and can be dragged by its handle, or by the inspector itself when scrolled to the top. It still opens tall (92 %) when a new line is added and the text field is focused, and nearly full height on short screens, where 62 % leaves too little room to edit. The sheet now sits above the on-screen keyboard and has a labelled 关闭 button. The audit suggested evaluating a side drawer; a resizable bottom sheet keeps the thumb-reachable position and the existing actions, so the drawer was not pursued.
- Files:
  - `lib/features/lyrics/presentation/widgets/line_inspector_sheet.dart` (new: `LineInspectorSheet`, `LineInspectorSheetSizes`, `sizesFor`, `settleSize`, drag handle with close button, neighbouring lines).
  - `lib/features/lyrics/presentation/widgets/lyric_editor_content.dart` (`_showInspectorSheet` builds the new sheet and passes the neighbouring lines).
  - `lib/features/lyrics/presentation/widgets/lyric_inspector_pane.dart` (`LineInspector.scrollController` for the sheet's drag controller).
  - Test: `test/features/lyrics/presentation/widgets/line_inspector_sheet_test.dart` (new: sizes per layout, settle rules, open heights on phone / new line / short screen, neighbour lines, handle drags up and down, inspector pull-down, close button, keyboard inset).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Wide layouts keep the side inspector pane; the sheet is still capped at 720 px wide on medium widths.
  - Review decisions, delete, split, merge and word timing still close the sheet as before.
- Commit: `Let the narrow line inspector sheet resize`
