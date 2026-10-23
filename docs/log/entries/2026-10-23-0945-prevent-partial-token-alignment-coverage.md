# [2026-10-23 09:45] Prevent partial token alignment from inflating coverage

- Scope: Make token-alignment completeness explicit and report zero coverage whenever candidate or dynamic-programming safety limits prevent a complete alignment. Preserve unique anchors as diagnostics without presenting them as complete coverage.
- Files: lib/features/lyrics/domain/proofreading/reference_token_aligner.dart, test/features/lyrics/domain/proofreading/reference_token_aligner_test.dart, this entry, docs/work_log.md, docs/work_log_archive.md.
- Validation: Added a regression case with surviving unique anchors and a DP gap exceeding the cell budget. GitHub Actions must run the full analyzer, tests, and work-log check; local Flutter/Dart is unavailable here.
- Notes: This is fail-closed confidence reporting, not a change to the anchor search or lyric mutation path. Incomplete alignment retains diagnostic matches but cannot claim reference coverage.
- Commit: Prevent partial token alignment from inflating coverage
