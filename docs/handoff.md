# Handoff

## 目标
Resolve high-priority Issue #224 by bounding Media Hub incoming audio uploads in size, duration, storage consumption, and concurrency, while preserving the HTTPS certificate pinning and successful upload/import contract.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Base: `main@0e62beafe36c807b31297454c87311bb465bf8ed`
- Branch: `security/media-hub-upload-guardrails-20261029`
- PR: https://github.com/BrainEno/lyric-forge-ktv/pull/240
- Current implementation head: `6f23b50f37c9cf2f513aef0da60925487985a21a`
- Local Flutter/Dart SDKs are unavailable in this environment; use GitHub Actions for validation.

## 已改文件
- `lib/features/transfer/data/services/http_media_hub_service.dart`
- `test/features/transfer/http_media_hub_upload_test.dart`
- `docs/log/entries/2026-10-29-1620-media-hub-upload-guardrails.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`

## 检查结果
- Flutter Quality Gate passed on implementation head `6f23b50f37c9cf2f513aef0da60925487985a21a`: work-log preflight, changed-Dart formatting, analysis, and full tests all passed.
- Added pre-rejection for oversized declared Content-Length, in-stream byte counting for chunked uploads, HTTP 413 overflow rejection, idle/total deadlines, partial-file cleanup, HTTP 507 storage rejection, and HTTP 429 concurrency backoff.
- Added a 256 MiB free-space reserve plus periodic checks during large streams, with deterministic probe injection for tests.
- Timeout handling now manually arbitrates the request iterator against idle and total timers, allowing the 408 response to be written before the request-body subscription is cancelled.
- A documentation-only handoff refresh follows the validated code head; check final-head CI before merge.

## 下一步
1. Verify CI on the final PR head after the documentation refresh.
2. Ensure KTV history/recovery and Windows Debug checks are green if triggered by the applicable CI configuration; the Flutter Quality Gate includes full tests.
3. Keep #224 open until the PR is merged; physically test upload/timeout behavior on at least one device.
4. Continue with #227 (constant-time token comparison/CORS origin policy) and #234 (atomic .part name reservation) as the next Media Hub security fixes.

## 已知风险
- Disk-space probing uses PowerShell/.NET DriveInfo on Windows and `df -Pk` on Linux/macOS. If the OS or filesystem cannot provide a reliable estimate, uploads fail closed with 507.
- Free-space probes run at upload start and every 64 MiB during large streaming uploads; unrelated writes between probes can still affect the available-space estimate.
- The existing `.part` name-reservation race is tracked separately in #234. Physical-device upload behavior still requires a smoke test.

最后更新：2026-10-29 17:03（Asia/Taipei）
