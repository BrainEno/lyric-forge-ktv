# [2026-10-29 18:15] Reserve upload destination names and UUID temporary files

- Scope: Address issue #234 by removing the predictable `<destination>.part` file and check-then-delete flow. Each upload now creates a UUID-named temporary file exclusively and claims the final filename with an exclusively-created `.reserve` marker; concurrent same-name uploads must obtain different reservations.
- Files: `lib/features/transfer/data/services/http_media_hub_service.dart`, `test/features/transfer/http_media_hub_upload_test.dart`, `docs/work_log.md`, `docs/work_log_index.md`, `docs/handoff.md`, and this entry.
- Validation: Added a concurrent same-name integration test that sends two different 256 KiB payloads, checks distinct returned names and HTTP 201 responses, verifies both SHA-256 digests, and asserts no `.part`/`.reserve` leftovers. Final-head Flutter Quality Gate must pass; local Flutter/Dart commands are unavailable in this environment.
- Notes: Both final-name selection and temporary-file creation use exclusive filesystem operations. A process crash may leave an orphan marker and UUID temp file; the marker fails safe by preventing name reuse. Physical-device upload behavior is still a separate smoke test.
- Commit: `security: reserve upload names and UUID temp files atomically`
