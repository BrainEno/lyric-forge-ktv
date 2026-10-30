# Handoff

## 目标
Resolve issue #234 by preventing concurrent uploads with the same filename from sharing/deleting each other's temporary file or overwriting completed content.

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- Base: `main@5d011ac4a51c3c04a714297916e5b8c6683b7fff`
- Branch: `security/atomic-upload-reservations-main-20261029`
- PR: https://github.com/BrainEno/lyric-forge-ktv/pull/248.
- The upload size/time/disk/concurrency guardrails are in PR #240; this issue's branch is intentionally kept standalone to permit separate review and CI.

## 已改文件
- `lib/features/transfer/data/services/http_media_hub_service.dart`
- `test/features/transfer/http_media_hub_upload_test.dart`
- `docs/log/entries/2026-10-29-1815-atomic-upload-reservations.md`
- `docs/work_log.md`, `docs/work_log_index.md`, `docs/handoff.md`

## 实现
- `_reserveIncomingDestination` claims a destination-specific `.reserve` marker using `File.create(exclusive: true)`, so concurrent upload contenders select different names without a check-then-create window.
- Temporary upload bodies go to exclusive UUID-named `.lyricforge-<uuid>.part` files, independent of the target filename.
- The marker stays held through upload, rename, and library import, and is released from `finally`. Error paths discard only the current request's temp file.
- Added a concurrent same-name test with two different 256 KiB payloads. It asserts HTTP 201, distinct returned names, both exact SHA-256 hashes, and no remaining `.part` or `.reserve` files.

## 检查结果
- Source and regression test committed on the issue-specific branch.
- Final-head Flutter Quality Gate must pass work-log checks, changed-Dart formatting, analysis, and the full test suite; local Dart/Flutter SDKs are unavailable.
- The test uses concurrent requests but doesn't force a deterministic interleaving at the filesystem syscall boundary; the exclusive-create invariant is also reviewed directly in the implementation.

## 下一步
1. Open a standalone PR against `main` and verify the final-head quality gate.
2. Fix any formatting/analyzer/test failures from CI without weakening the two-payload hash assertions.
3. Keep #234 open until the fix is validated and merged.
4. Track the cleanup policy for abandoned UUID files and `.reserve` markers separately if crash recovery requirements warrant it.

## 已知风险
- A process crash can leave a staging file and reservation marker. The marker fails safe by preventing a later upload from reusing the same name, but orphan cleanup is not part of this fix.
- The reservation coordinates Media Hub uploads. An unrelated process writing directly into the incoming directory does not honor the marker protocol.
- Physical phone/desktop upload smoke testing remains a separate check.

最后更新：2026-10-29 18:18（Asia/Taipei）
