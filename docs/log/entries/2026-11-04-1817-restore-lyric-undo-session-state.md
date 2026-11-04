# [2026-11-04 18:17] Restore lyric editor session state on undo

- Scope: Fix #325 by making lyric editor undo/redo restore the document together with manual-edit protection IDs and dirty state. Rebase historical dirty state when a save establishes a new baseline so undo is dirty relative to the saved document, while redo back to that saved state is clean.
- Files: `lib/features/lyrics/domain/models/lyric_edit_history.dart`, `lib/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart`, `test/features/lyrics/presentation/controllers/lyric_editor_document_controller_test.dart`, `docs/log/entries/2026-11-04-1817-restore-lyric-undo-session-state.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed for the implementation diff.
  - `flutter test test/features/lyrics/presentation/controllers/lyric_editor_document_controller_test.dart` => not run locally because Flutter/Dart SDK is unavailable. Pinned Flutter Quality Gate run `41813806024` passed on PR head `fd1f3e1`, including formatter, work-log preflight, analysis, and the full test suite.
  - Work-log harness `write/check` => not run locally because Dart SDK is unavailable; CI work-log preflight passed in run `41813806024`.
- Notes: The editor undo tests cover restoration/removal of manual marks, save/reopen without a revoked mark, clean-baseline undo, redo, and undo/redo across a save. PR #340 is open for review; do not merge until the final PR-head Flutter Quality Gate passes. No native, KTV recovery, runtime-release, icon, or other specialist workflow was changed.
- Commit: `fix: restore lyric editor session state on undo`
