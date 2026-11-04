# [2026-11-04 19:46] Extend lyric undo regression coverage

- Scope: Extend PR #340 with the five controller regression categories and two history-layer checks from duplicate PR #339, plus a multi-step save-baseline undo/redo test. Replace `jsonEncode` string comparison with structural comparison of `LyricDocument.toJson()` so metadata map ordering does not create false dirtiness and full serialized strings are not allocated.
- Files: `lib/features/lyrics/domain/models/lyric_edit_history.dart`, `test/features/lyrics/domain/models/lyric_edit_history_test.dart`, `test/features/lyrics/presentation/controllers/lyric_editor_document_controller_test.dart`, this entry, and generated work-log navigation files.
- Validation:
  - `git diff --check` => passed before adding the work-log entry.
  - Targeted Flutter tests, formatter, analyzer, and `dart tool/work_log.dart check` => not run locally because Flutter/Dart SDK is unavailable; the pinned Flutter Quality Gate on the final PR head must validate them.
- Notes: The new save-baseline regression saves after two independent line edits, walks undo through both historical states, and redoes back to the saved state, checking both manual marks and dirtiness at each step. PR #340 remains the implementation PR; do not merge PR #339 alongside it. Re-evaluate whether to close #339 after the final #340 head passes CI.
- Commit: `fix: complete lyric undo state and baseline coverage`
