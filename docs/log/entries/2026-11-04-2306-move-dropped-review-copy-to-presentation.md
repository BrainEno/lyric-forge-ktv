# [2026-11-04 23:06] Move dropped-item review copy to presentation

- Scope: Remove the `reasonLabel` field from `LyricProofreadV2DroppedItem`, stop the assembler from assigning dropped-item labels, and centralize the existing default-excluded / checkbox-to-restore guidance in presentation. Leave other Proofread V2 review-item reason labels and explanations untouched.
- Files: `lib/features/lyrics/domain/proofreading/proofread_review_proposal.dart`, `lib/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`, related assembler/composer/dialog tests and `test/features/lyrics/presentation/lyric_review_strings_test.dart`, this entry, generated `docs/work_log.md` and `docs/work_log_archive.md`, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Repository search confirmed dropped-item constructors no longer take `reasonLabel`; review-item `reasonLabel` usage remains in scope only for review rows.
  - Flutter/Dart SDK => unavailable locally; a temporary WASM `dart_style` formatter check passed for all changed Dart files, but local analyzer/tests were not run.
  - Pinned Flutter Quality Gate run `41855390338` => passed on code/test head `1960357`, including changed-file formatting, analysis, work-log preflight, and the full test suite. A later docs-only handoff update requires a final-head check on PR #343.
- Notes: PR #343 is open for review and must not be merged without explicit user authorization. Issue #335 is already closed and is not reopened. The native, KTV recovery, runtime-release, icon, and other specialist workflows remain outside this slice.
- Commit: `refactor: move dropped review copy to presentation`
