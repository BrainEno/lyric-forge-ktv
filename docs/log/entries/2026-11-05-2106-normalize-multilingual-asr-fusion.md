# [2026-11-05 21:06] Normalize multilingual ASR fusion comparisons

- Scope: Add a shared Unicode-aware comparison path for dual-engine ASR fusion so Korean and other supported scripts are retained, common Latin diacritics compare consistently, and empty normalized text cannot be treated as agreement.
- Files: `lib/features/transcription/data/services/asr_text_comparison.dart`; `lib/features/transcription/data/services/high_quality_transcription_service.dart`; `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`; `test/asr_text_comparison_test.dart`; `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-05-2106-normalize-multilingual-asr-fusion.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - Changed Dart files formatted with `@wasm-fmt/dart_fmt@0.4.0`; `git diff --check` => passed.
  - `flutter analyze` and focused Flutter tests => not run locally because Flutter/Dart SDK is unavailable; pinned CI validation pending.
- Notes: Issue #317 remains open. This independently verifiable slice covers shared multilingual normalization/similarity and duplicate Korean fusion rows in either engine order; chunk-merge disagreement evidence and other issue acceptance criteria remain separate follow-up work. No PR merge is authorized.
- Commit: `style: align ASR regression with pinned formatter`
