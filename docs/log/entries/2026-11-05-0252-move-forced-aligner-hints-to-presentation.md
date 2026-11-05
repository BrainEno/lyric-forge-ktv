# [2026-11-05 02:52] Move ForcedAligner supplemental hints to presentation

- Scope: Replace the assembler's free-form ForcedAligner supplemental labels (“词级对齐 N 词” and “缺少词级对齐证据”) with typed alignment-hint codes, map those codes to the existing Chinese labels in presentation, and show them in the Proofread V2 dialog. Preserve token evidence, proofread/reference reason codes, existing wording, and Proofread V2 explanations; do not migrate other copy.
- Files: `lib/features/lyrics/domain/proofreading/proofread_review_proposal.dart`, `lib/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`, related assembler/composer/string/dialog tests, this entry, generated `docs/work_log.md`, `docs/work_log_index.md`, `docs/work_log_archive.md`, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Temporary WASM `@wasm-fmt/dart_fmt` formatting check => passed for all changed Dart files.
  - Local Flutter/Dart analyze and tests => not run because the pinned SDK is unavailable in this workspace.
  - Pinned Flutter Quality Gate run `41957730303` => passed on code/test head `083874f`, including work-log preflight, changed-Dart formatting, analysis, and the full test suite. The final PR-head check remains authoritative after this documentation update.
- Notes: PR #346 is open for review and must not be merged without explicit user authorization. Issue #335 remains closed. This slice does not alter reference/proofread reason mappings, Proofread V2 explanations, native, KTV recovery, runtime-release, icon, or other specialist workflows.
- Commit: `refactor: move ForcedAligner hints to presentation`
