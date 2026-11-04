# [2026-11-04 23:06] Move dropped-item review copy to presentation

- Scope: Remove the `reasonLabel` field from `LyricProofreadV2DroppedItem`, stop the assembler from assigning dropped-item labels, and centralize the existing default-excluded / checkbox-to-restore guidance in presentation. Leave other Proofread V2 review-item reason labels and explanations untouched.
- Files: `lib/features/lyrics/domain/proofreading/proofread_review_proposal.dart`, `lib/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`, related assembler/composer/dialog tests and `test/features/lyrics/presentation/lyric_review_strings_test.dart`, this entry, generated `docs/work_log.md` and `docs/work_log_archive.md`, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Repository search confirmed dropped-item constructors no longer take `reasonLabel`; review-item `reasonLabel` usage remains in scope only for review rows.
  - Flutter/Dart SDK => unavailable locally, so formatter, analyzer, and Flutter tests were not run locally.
  - Pinned Flutter Quality Gate => required on the final PR #343 head; status should be checked on the PR before treating the slice as complete.
- Notes: PR #343 is open for review and must not be merged without explicit user authorization. Issue #335 is already closed and is not reopened. The native, KTV recovery, runtime-release, icon, and other specialist workflows remain outside this slice.
- Commit: `refactor: move dropped review copy to presentation`
