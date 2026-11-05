# [2026-11-05 01:18] Move ASR review reasons to presentation

- Scope: Carry ASR `ProofreadReason` values as typed reason codes on review items and map the 16 existing Chinese labels in presentation. Leave forced-alignment supplemental hints in `reasonLabel`, reference-first reason codes, and Proofread V2 explanations unchanged.
- Files: `lib/features/lyrics/domain/proofreading/proofread_review_proposal.dart`, `lib/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`, related assembler/string/dialog tests, this entry, generated work-log navigation, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Temporary WASM `dart_style` formatter check => passed for all changed Dart files.
  - Flutter/Dart SDK => unavailable locally; local analyzer and Flutter tests were not run.
  - Pinned Flutter Quality Gate => must pass on the final PR #345 head before this slice is considered validated.
- Notes: PR #345 is open for review; do not merge without explicit user authorization. Issue #335 remains closed. Native, KTV recovery, runtime-release, icon, and other specialist workflows are outside this slice.
- Commit: `refactor: move ASR review reasons to presentation`
