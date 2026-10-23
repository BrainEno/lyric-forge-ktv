# [2026-10-24 01:10] Cover structural reference alignment mismatches

- Scope: Add regression tests for reference/ASR one-to-many and many-to-one line segmentation, including original-index preservation when empty reference lines are skipped.
- Files: test/features/lyrics/domain/services/lyric_alignment_service_test.dart, this entry, docs/work_log.md.
- Validation: Added three targeted regression tests. Flutter/Dart execution is unavailable in this environment; GitHub Actions must verify formatting, analysis, tests, and work-log consistency.
- Notes: These tests lock down existing diagnostic-only behavior. Structural mismatches remain explicit review candidates; no lyric text or timestamps are automatically changed.
- Commit: `Cover structural reference alignment mismatches`
