# [2026-11-05 21:06] Normalize multilingual ASR fusion comparisons

- Scope: Add a shared Unicode-aware comparison path for dual-engine ASR fusion so Korean and other supported scripts are retained, common Latin diacritics compare consistently, and empty normalized text cannot be treated as agreement.
- Files: `lib/features/transcription/data/services/asr_text_comparison.dart`; `lib/features/transcription/data/services/high_quality_transcription_service.dart`; `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`; `test/asr_text_comparison_test.dart`; `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-05-2106-normalize-multilingual-asr-fusion.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate run `42034042102` passed on code head `012e2dacd7422aede1a6e4a9ca0f2ade9a8dc962`, including work-log preflight, changed-file formatting, analyze, and the full repository test suite. The formatter fixes were applied from the CI diff supplied by the user. A docs-only commit follows to record the result; verify its PR-head gate as well.
  - Local `flutter analyze` and focused Flutter tests => not run because Flutter/Dart SDK is unavailable; the pinned CI supplied the validation.
- Notes: Issue #317 remains open. This independently verifiable slice covers shared multilingual normalization/similarity and duplicate Korean fusion rows in either engine order; chunk-merge disagreement evidence and other issue acceptance criteria remain separate follow-up work. PR #353 remains open; no PR merge is authorized.
- Commit: `style: apply pinned ASR formatter output`
