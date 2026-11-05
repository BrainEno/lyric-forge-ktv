# [2026-11-05 17:27] Move Proofread V2 summary copy to presentation

- Scope: Keep Proofread V2 effective strategy, verdict counts, dropped count, and optional reference coverage as structured domain summary data. Move strategy labels, reference-coverage rounding, count formatting, and the existing Chinese header copy into presentation without changing wording or ordering.
- Files: `lib/features/lyrics/domain/proofreading/proofread_review_proposal.dart`, `lib/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, assembler and presentation string tests, this entry, generated work-log navigation, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Temporary WASM `@wasm-fmt/dart_fmt` formatter stability check => passed for all changed Dart files.
  - Local Flutter/Dart analyzer and tests => not run because the pinned SDK is unavailable in this workspace.
  - Pinned Flutter Quality Gate run `42002659225` => passed on implementation head `599826c992432762222d86a53fffe10b3c965252`, including work-log preflight, changed-Dart format, analysis, and full tests. The updated final PR head must also pass before merge.
- Notes: PR #349 is open for review and is not authorized for merge. Exact current wording/order and Dart `round()` behavior are covered by presentation tests; domain tests assert structured data. Native, KTV recovery, runtime-release, icon, and other specialist workflows were not audited.
- Commit: `refactor: move Proofread V2 summary copy to presentation`
