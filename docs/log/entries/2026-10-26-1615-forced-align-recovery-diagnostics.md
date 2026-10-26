# [2026-10-26 16:15] Recover ForcedAligner line matches with bounded diagnostics

- Scope: Make token-to-line ForcedAligner evidence resilient to a small number of extra returned spans without unbounded searching or silently treating partial coverage as complete.
- Files: lib/features/lyrics/domain/proofreading/proofread_result.dart, lib/features/lyrics/domain/proofreading/asr_first_pipeline.dart, test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart, docs/high_quality_asr.md, docs/handoff.md, docs/work_log.md, docs/work_log_archive.md, this entry.
- Validation: GitHub Actions Flutter Quality Gate run 40289442193 passed on implementation head 2f32facdde5c94832ef8808382985c8c6862176a. Work-log lint reported 0 errors and 0 warnings; all 704 tests passed and the repository quality gate passed. Local Dart/Flutter commands were not run because this environment has no Dart/Flutter SDK.
- Notes: This phase adds domain-level diagnostics only; service warnings and review-UI presentation are the next integration step. Skipped spans are not automatically classified as noise/ad-libs. Synthetic-span tests do not establish real Chinese, English, or Japanese audio timing accuracy.
- Commit: `Recover line matching around bounded extra spans`
