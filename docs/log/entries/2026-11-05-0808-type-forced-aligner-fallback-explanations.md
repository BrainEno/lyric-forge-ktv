# [2026-11-05 08:08] Type ForcedAligner fallback explanations

- Scope: Remove free-form warning strings from `ForcedAlignmentProofreadOutcome`; carry alignment availability and diagnostics only, derive typed Proofread V2 explanation codes for unavailable alignment or missing diagnostics, and map the existing fallback wording in presentation. Keep partial-match details in the existing structured diagnostics UI and preserve review-only behavior.
- Files: `lib/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart`, `lib/features/lyrics/domain/proofreading/proofread_review_proposal.dart`, `lib/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, related service/assembler/string tests, this entry, generated work-log navigation, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Temporary WASM `@wasm-fmt/dart_fmt` formatter stability check => passed for changed Dart files.
  - Local Flutter/Dart analyzer and tests => not run because the pinned SDK is unavailable in this workspace.
  - Pinned Flutter Quality Gate run `41991774355` => passed on code/test head `99a40a0`, including work-log preflight, changed-Dart format, analysis, and the full test suite. Final PR-head checks remain authoritative after the documentation update.
- Notes: PR #347 was merged at baseline `0131b0d`. PR #348 is open for review; do not merge without explicit user authorization. ForcedAligner partial-match detail remains represented by `ProofreadAlignmentDiagnostics` and displayed in the diagnostics UI; no raw service warning string remains.
- Commit: `refactor: type ForcedAligner fallback explanations`
