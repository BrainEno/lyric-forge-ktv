# [2026-11-04 23:55] Move reference-first review reasons to presentation

- Scope: Replace the reference-first assembler's Chinese reason labels with typed `LyricProofreadV2ReferenceReason` codes, map all ten codes to the existing Chinese copy in presentation, and preserve the dialog's visible “依据” text. ASR review-item labels and explanations remain unchanged.
- Files: `lib/features/lyrics/domain/proofreading/proofread_review_proposal.dart`, `lib/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`, `test/features/lyrics/domain/proofreading/proofread_v2_review_assembler_test.dart`, `test/features/lyrics/presentation/lyric_review_strings_test.dart`, `test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart`, this entry, generated work-log navigation, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Temporary WASM `dart_style` formatter check => passed for all changed Dart files.
  - Flutter/Dart SDK => unavailable locally; local analyzer and Flutter tests were not run.
  - Pinned Flutter Quality Gate run `41862746358` => passed on PR #344 head `14853d6`, including formatting, analysis, work-log preflight, and the full test suite. This follow-up documentation commit still needs its own final-head check.
- Notes: PR #344 is open for review; do not merge without explicit user authorization. Issue #335 remains closed. This slice migrates only reference-first review-item reasons; ASR review-item reasons, explanations, native/KTV/runtime/icon workflows, and other specialist workstreams remain out of scope.
- Commit: `refactor: move reference-first review labels to presentation`
