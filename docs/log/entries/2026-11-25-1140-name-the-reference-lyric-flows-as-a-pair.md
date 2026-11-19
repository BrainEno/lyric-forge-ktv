# [2026-11-25 11:40] Name the reference lyric flows as a pair

- Scope: UI/UX audit E-02. The 校对 menu offered 「参考歌词纠正」 and 「逐行智能纠错（保留时间戳）」, two names for the two ways of using pasted reference lyrics that could only be told apart by reading their subtitles. Worse, both flows (and the reference step of 智能校对) opened the same input dialog, titled 参考歌词纠正 and explaining that it would fill missing rows and infer timing, which is the opposite of what the text-only flow does. A new `ReferenceLyricPurpose` (`alignment`, `textOnly`, `proposal`) carries one title, menu subtitle and dialog explanation per flow. The menu entries now read 「参考歌词：纠正文字和时间轴」 and 「参考歌词：只改文字」, and `showReferenceAlignmentDialog` takes the purpose (default `alignment`), so the dialog opened from 只改文字 says that timestamps stay unchanged and the one opened from 智能校对 says it feeds a proposal that is confirmed row by row.
- Files:
  - `lib/features/lyrics/presentation/widgets/reference_alignment_dialog.dart` (`ReferenceLyricPurpose`; `purpose` on the dialog and its show function).
  - `lib/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart` (menu titles and subtitles come from the purpose).
  - `lib/features/lyrics/presentation/controllers/lyric_editor_proofreading_coordinator.dart` (text-only and proposal flows pass their purpose).
  - `test/features/lyrics/presentation/widgets/reference_alignment_dialog_test.dart` (each purpose titles the dialog after its own flow; the text-only copy never promises new timing; the pair shares a prefix and carries no version number; default purpose).
  - `test/features/lyrics/presentation/widgets/lyric_proofread_menu_button_test.dart`, `lyric_editor_toolbar_test.dart`, `test/features/lyrics/presentation/screens/lyric_editor_save_conflict_test.dart` (new labels).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the affected widget tests run in the PR's Flutter Quality Gate and the temporary format probe.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The review dialogs that follow (参考歌词智能纠错, 参考歌词纠错与校时复核) keep their titles; they already describe the review step rather than the choice of flow.
  - 「智能校对」 already lost its 「V2」 suffix in the menu; the internal `proofreadV2` identifiers are not user-facing and stay.
- Commit: `Name the reference lyric flows as a pair`
