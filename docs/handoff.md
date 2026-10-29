# Handoff

## 目标
Resolve high-priority Issue #224 by bounding Media Hub incoming audio uploads in size, duration, storage consumption, and concurrency, while preserving the HTTPS certificate pinning and successful upload/import contract.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Base: `main@0e62beafe36c807b31297454c87311bb465bf8ed`
- Branch: `security/media-hub-upload-guardrails-20261029`
- PR: pending creation after the initial implementation commit.
- Local Flutter/Dart SDKs are unavailable in this environment; use GitHub Actions for validation.

## 已改文件
- `lib/features/transfer/data/services/http_media_hub_service.dart`
- `test/features/transfer/http_media_hub_upload_test.dart`
- `docs/log/entries/2026-10-29-1620-media-hub-upload-guardrails.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`

## 检查结果
- Added pre-rejection for oversized declared Content-Length, in-stream byte counting for chunked uploads, 413 overflow rejection, idle/total deadlines, partial-file cleanup, 507 storage rejection, and 429 concurrency backoff.
- Added a 256 MiB free-space reserve plus periodic checks during large streams, with deterministic probe injection for tests.
- Added integration coverage for declared and chunked oversized uploads, disk reserve checks, idle/total deadlines, one-per-session concurrency, and slot release.
- Final-head validation is pending; do not merge unless Flutter Quality Gate, KTV history/recovery, and Windows Debug build all pass.

## 下一步
1. Run format, analyzer, full tests, work-log lint, KTV history/recovery validation, and Windows Debug build on the PR head.
2. Fix any failures from exact CI logs without skipping tests.
3. Once all checks pass, update the handoff with the PR URL and verified commit, then rerun checks for the final head.
4. Merge only after all checks pass; continue next with #227/#234 according to severity.

## 已知风险
- Disk-space probing uses PowerShell/.NET DriveInfo on Windows and `df -Pk` on Linux/macOS. If the operating system or filesystem cannot provide a reliable estimate, uploads fail closed with 507.
- Free-space probes run at upload start and every 64 MiB during large streaming uploads; unrelated writes between probes can still affect the available-space estimate.
- The existing `.part` name-reservation race is tracked separately in #234. Physical-device upload behavior still requires a smoke test.

最后更新：2026-10-29 16:20（Asia/Taipei）
