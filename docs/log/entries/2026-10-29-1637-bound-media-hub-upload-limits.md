# [2026-10-29 16:37] Bound Media Hub upload resources

- Scope: Partially address issue #224 by bounding incoming Media Hub audio uploads by declared and streamed byte size, idle/total request time, and concurrent request count. Oversized uploads are rejected with HTTP 413 and timed-out uploads with HTTP 408; saturated upload capacity returns HTTP 429 with Retry-After.
- Files: `lib/features/transfer/data/services/http_media_hub_service.dart`, `test/features/transfer/http_media_hub_upload_test.dart`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/handoff.md`, `docs/log/entries/2026-10-29-1637-bound-media-hub-upload-limits.md`.
- Validation:
  - Added regression tests for Content-Length preflight, chunked-body enforcement and rejection above the configured concurrency limit.
  - Final GitHub Actions quality-gate results must be checked on the PR head. Local Dart/Flutter commands are unavailable in this execution environment.
- Notes: Defaults are 2 GiB per file, 30 seconds idle time, 30 minutes total request time and two concurrent uploads. Remaining gap: portable free-disk-space preflight is not implemented because the current cross-platform service has no disk-space abstraction; keep issue #224 open until this is addressed and validated.
- Commit: `fix: bound Media Hub upload resources`
