# [2026-10-26 15:30] Normalize multilingual forced-alignment text matching

- Scope: Improve token-to-line matching in ForcedAligner review evidence by sharing the app's Unicode-aware lyric tokenizer, so full-width Latin text and common Chinese/Japanese punctuation do not unnecessarily suppress evidence coverage.
- Files: lib/features/lyrics/domain/proofreading/asr_first_pipeline.dart, test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart, docs/high_quality_asr.md, docs/work_log.md, docs/work_log_archive.md, docs/work_log_index.md, docs/handoff.md, this entry.
- Validation: Added deterministic regression coverage for full-width Latin, Chinese, and Japanese text while asserting source lyrics and line timings remain unchanged. The full Flutter Quality Gate is the remote validation authority; no local Dart/Flutter SDK is available in this execution environment, so the new tests have not been run locally.
- Notes: These synthetic contract tests validate normalization/matching only. They do not establish acoustic timing accuracy; real-song Chinese/English/Japanese validation still requires an installed runtime containing `POST /v1/align`.
- Commit: `Normalize multilingual alignment text consistently`
