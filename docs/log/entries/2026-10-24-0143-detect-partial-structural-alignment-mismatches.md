# [2026-10-24 01:43] Detect partial structural alignment mismatches

- Scope: Detect one-to-many and many-to-one segmentation even when a long partial line already exceeds the ordinary pair threshold and would otherwise hide the structural mismatch.
- Files: lib/features/lyrics/domain/services/lyric_alignment_service.dart, test/features/lyrics/domain/services/lyric_alignment_service_test.dart, docs/work_log.md, docs/work_log_archive.md, this entry.
- Validation: Added regression tests for both partial-match cases. GitHub Actions will validate formatting, analysis, the full test suite, and work-log lint; local Flutter/Dart execution is unavailable in this environment.
- Notes: Structural detection only considers short consecutive windows with at least one unmatched neighbor and a meaningful similarity improvement. It continues to produce diagnostics only; it does not merge lines or change text/timestamps.
- Commit: `fix: detect partial structural alignment mismatches`
