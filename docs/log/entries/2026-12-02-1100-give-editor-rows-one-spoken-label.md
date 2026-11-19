# [2026-12-02 11:00] Give editor rows one spoken label, name the remaining tap targets

- Scope: A walkthrough of A-04 for controls that can be tapped but have no name. A screen reader met each lyric editor row as loose pieces (number, start time, dash, end time, text, badges such as 复核 or 双擎); the playing row was only an icon, a hand-edited row only a dot and the selected row only a border, and editing the text or times, splitting, merging and deleting were behind a double click, a right click or a long press. Each row is now one node with a sentence label (`第 3 行，00:12.40 到 00:15.10，…，正在播放，待复核，优先级 60`), a real selected state, and every gesture-only edit as a custom action in menu order (`lyric_row_semantics.dart`, D-036). The inline editor's two times say which time they are and that a tap changes them, and the arrow between them is not read. Word timing chips read the word and its span and, when they can seek, say so. The fullscreen KTV surface is named and offers 显示播放控制 and 退出全屏 KTV as actions, because a screen reader claims tap and double tap and Esc needs a keyboard.
- Files:
  - New: `lib/features/lyrics/presentation/widgets/lyric_row_semantics.dart`, `test/features/lyrics/presentation/widgets/lyric_row_semantics_test.dart`.
  - `lib/features/lyrics/presentation/widgets/lyric_list_pane.dart`, `lyric_word_timing_strip.dart`.
  - `lib/features/player/presentation/widgets/fullscreen_ktv_interaction_surface.dart`, `test/features/player/fullscreen_ktv_interaction_surface_test.dart`.
  - `docs/decisions.md` (D-036), `artifacts/ui-audit/reports/issues.md` (status section for round 15).
- Validation:
  - Unit tests for the labels and the action list; widget tests with semantics enabled for the rows (one node, selection, tap, long press, actions run their callbacks), the inline editor, the word chips and the fullscreen surface.
  - Format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - Not heard on TalkBack or VoiceOver. About 15 unnamed `InkWell` / `GestureDetector` targets in the library, player bar and transfer screens are left for a later round (listed in the handoff).
- Commit: `Give editor rows one spoken label`
