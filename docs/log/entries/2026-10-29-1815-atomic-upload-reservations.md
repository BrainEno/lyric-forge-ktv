# [2026-10-29 18:15] Reserve upload destination names and UUID temporary files

- Scope: Address issue #234 by removing the predictable `<destination>.part` file and check-then-delete flow. Each upload now creates a UUID-named temporary file exclusively and claims the final filename with an exclusively-created `.reserve` marker; concurrent same-name uploads must obtain different reservations.
- Files: `lib/features/transfer/data/services/http_media_hub_service.dart`, `test/features/transfer/http_media_hub_upload_test.dart`, and this work-log/handoff update.
- Validation: Added a deterministic concurrent upload test that gates both requests at the disk-space probe, uploads different byte sequences under the same filename, checks distinct returned names, validates both SHA-256 digests, and asserts no `.part`/`.reserve` leftovers. Final-head Flutter Quality Gate must pass; local Flutter/Dart commands are unavailable in this environment.
- Notes: This PR is stacked on PR #240's upload-resource guardrails branch to avoid competing edits to the same handler; rebase/retarget it after #240 merges. An abandoned reservation marker after process termination fails safe by preventing name reuse, but stale-marker cleanup remains a possible future housekeeping improvement.
- Commit: `security: reserve upload names and UUID temp files atomically`
