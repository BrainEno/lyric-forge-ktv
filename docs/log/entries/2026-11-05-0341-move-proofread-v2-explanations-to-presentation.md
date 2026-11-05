# [2026-11-05 03:41] Move Proofread V2 explanations to presentation

- Scope: Replace assembler-owned Proofread V2 explanation strings with immutable typed explanation codes and parameters; render the existing wording and order through `LyricReviewStrings` at the presentation call site. Preserve service-generated ForcedAligner warning text verbatim as a typed warning payload rather than changing its source or copy.
- Files: `lib/features/lyrics/domain/proofreading/proofread_review_proposal.dart`, `lib/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, `test/features/lyrics/domain/proofreading/proofread_v2_review_assembler_test.dart`, `test/features/lyrics/presentation/lyric_review_strings_test.dart`, this entry, generated work-log navigation, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Temporary WASM `@wasm-fmt/dart_fmt` formatter stability check => passed for all changed Dart files.
  - Local Flutter/Dart analyze and tests => not run because the pinned SDK is unavailable in this workspace.
  - Pinned Flutter Quality Gate run `41962868320` => passed on code/test head `53efbf2`, including work-log preflight, changed-Dart format, analysis, and the full test suite. Final PR-head checks remain authoritative after the documentation update.
- Notes: PR #346 was merged at baseline `efc3faa`. PR #347 is open for review; do not merge without explicit user authorization. Issue #335 remains closed. The ForcedAlignment service's warning-generation copy and unrelated review copy are outside this slice.
- Commit: `refactor: move Proofread V2 explanations to presentation`
