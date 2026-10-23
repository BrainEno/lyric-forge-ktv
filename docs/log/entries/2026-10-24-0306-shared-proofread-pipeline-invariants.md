# [2026-10-24 03:06] Add shared proofread pipeline invariants

- Scope: Share one invariant assertion helper across reference-first and ASR-first tests; cover protected lines, deep input immutability, line IDs, ordered non-overlapping intervals, duplicate chorus, and known/missing audio duration.
- Files: test/features/lyrics/domain/proofreading/helpers/proofread_pipeline_invariants.dart, test/features/lyrics/domain/proofreading/reference_first_pipeline_test.dart, test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart, docs/lyric_proofreading_v2_plan.md, docs/work_log.md, docs/work_log_archive.md, docs/work_log_index.md, docs/handoff.md, this entry.
- Validation: Regression tests are added. GitHub Actions must verify formatting, analysis, targeted and full tests, and work-log lint; local Flutter/Dart commands are unavailable in this environment.
- Notes: An ASR-first row outside the known audio boundary is intentionally not silently retimed; it remains source-preserving and must be marked `timingConflict` with an amber verdict. This is explicit review evidence, not a safe accepted interval.
- Commit: `test: add shared proofread pipeline invariants`
