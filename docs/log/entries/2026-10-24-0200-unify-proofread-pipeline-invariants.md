# [2026-10-24 02:00] Unify proofread pipeline invariant tests

- Scope: Share one invariant assertion helper across reference-first and ASR-first tests. Cover timeline ordering/non-overlap, 300 ms minimum ordinary duration, audio boundaries, verdict/output correspondence, unique non-null line IDs, protected-row preservation, reference-index uniqueness, and deep input immutability.
- Files: test/features/lyrics/domain/proofreading/shared_proofread_pipeline_invariants.dart, test/features/lyrics/domain/proofreading/reference_first_pipeline_test.dart, test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart, docs/lyric_proofreading_v2_plan.md, docs/work_log.md, docs/work_log_archive.md, this entry.
- Validation: Added shared checks and focused boundary/protected-input cases. GitHub Actions will verify formatting, analysis, full tests and work-log consistency; local Flutter/Dart execution is unavailable in this environment.
- Notes: ASR-first remains diagnostic-only for out-of-audio intervals: it flags the conflict rather than silently changing source timestamps. A valid line ending exactly at audio duration is accepted.
- Commit: `test: unify proofread pipeline invariants`
