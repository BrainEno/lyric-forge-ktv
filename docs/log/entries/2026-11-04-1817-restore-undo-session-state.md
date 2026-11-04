# [2026-11-04 18:17] Restore manual edit marks and dirty state on undo and redo

- Scope: Fix #325 so generic Ctrl+Z/Redo restores the editor session state together with the document: undoing a text edit now removes the manual-edit protection mark it added and returns a clean document to `hasChanges == false`, and redo reapplies both, so revoked marks are never persisted by `documentForSave()`.
- Files: `lib/features/lyrics/domain/models/lyric_edit_history.dart`, `lib/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart`, `test/features/lyrics/domain/models/lyric_edit_history_test.dart`, `test/features/lyrics/presentation/controllers/lyric_editor_document_controller_test.dart`, this entry, and generated work-log navigation files.
- Validation:
  - `dart format` for the changed Dart files => passed via the pinned-toolchain Flutter Quality Gate, run 41812835381.
  - `flutter analyze --no-pub --no-fatal-infos lib test` => passed via the same run 41812835381.
  - Targeted `flutter test` for `lyric_edit_history_test.dart` and `lyric_editor_document_controller_test.dart`, plus the complete `flutter test` suite => passed via the same run 41812835381.
- Notes: Local Flutter/Dart SDK is unavailable in this environment; validation uses the repository-pinned CI toolchain. Snapshots store `hasChanges` as captured at edit time, so edit -> save -> undo restores the pre-save dirty value rather than recomputing it against the just-saved baseline; this matches the batch-snapshot contract and is recorded on PR #339 as a deliberate follow-up boundary. No UI behaviour changed beyond undo/redo semantics; batch undo, reference alignment and proofread protection paths are untouched.
- Commit: `fix: restore manual edit marks and dirty state on undo and redo`
