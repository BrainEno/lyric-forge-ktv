# [2026-11-18 23:12] Group the proofreading menu into labelled sections

- Scope: UI/UX audit C-02 and E-02 (roadmap phase 2). The 校对 menu listed up to 20 flows with a single divider, and its first entry exposed an internal version number (智能校对 V2). The menu now has four labelled sections (智能纠错, 文本整理, 时间轴与打轴, 对比与回滚), and a section is shown only when at least one of its flows is available. The no-reference flow is called 智能校对 in the menu and 歌词智能校对 in its dialog title. The flows, callbacks and constructor API are unchanged.
- Files:
  - `lib/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart`: `LyricProofreadAction` is now an enhanced enum that carries its `LyricProofreadGroup`, so every action has exactly one section by construction. Values are declared in menu order, with 清理识别文本 first among the text tools. A non-interactive `_GroupHeader` (`Semantics(header: true)`) replaces the old single `startsNewGroup` divider. The new `smartProofreadTitle` constant keeps tests and UI on one string. The button tooltip lists the four sections instead of every flow.
  - `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`: dialog title without "V2".
  - Tests: `lyric_proofread_menu_button_test.dart` (new: section order by on-screen position, headers are not `MenuItemButton`s, empty sections and dividers hidden), and the label update in `lyric_editor_save_conflict_test.dart` and `chunk_project_editor_review_integration_test.dart`.
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the widget tests run in the PR's Flutter Quality Gate. Changed lines were kept within 80 columns. The same temporary formatter probe as the name restore confirmed the layout; its single reflow (one test header that fits on one line) is applied. The section mapping is an enum field rather than an `||`-pattern switch, so formatter output is predictable.
  - `rg "智能校对 V2"` in `lib/` and `test/` => no matches. Dated reviews and work-log entries keep the historical name.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Each section adds a short header (about 30 px). The full editor menu is therefore slightly taller, and Material menus scroll or move up on short windows. A collapsible `SubmenuButton` layout would be shorter but needs an extra click and changes keyboard navigation, so it was not used.
  - Internal identifiers (`onProofreadV2`, `LyricProofreadV2*`, file names) keep "V2"; they are not user-visible.
- Commit: `Group the proofreading menu into labelled sections`
