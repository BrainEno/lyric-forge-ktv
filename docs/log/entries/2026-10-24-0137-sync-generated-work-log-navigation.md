# [2026-10-24 01:37] Repair work-log generation and legacy commit parsing

- Scope: Make the work-log writer regenerate the active summary, sync the index snapshot date, and retain navigation links for entries that age out of the active window. Parse legacy plain-text Commit fields for display without treating them as verified Git subjects.
- Files: tool/work_log.dart, test/work_log_tool_test.dart, AGENTS.md, docs/work_log_index.md, docs/work_log.md, docs/work_log_archive.md, this entry.
- Validation: Added regression coverage for generated navigation idempotency and legacy Commit parsing. GitHub Actions is the validation source for analyzer, full tests, and work-log lint; local Dart/Flutter execution is unavailable in this environment.
- Notes: Existing stage-grouped archive navigation and the curated body of the index remain intact. Only the archive block marked as generated is managed automatically; only backticked Commit values are checked against Git history.
- Commit: `fix: repair work-log generation and legacy commit parsing`
