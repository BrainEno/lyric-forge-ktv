# Handoff

## 目标
Resolve issue #234 by preventing concurrent uploads with the same filename from sharing/deleting each other's temporary file or overwriting each other's completed content.

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- Base dependency: PR #240 branch `security/media-hub-upload-guardrails-20261029` (upload size/time/disk/concurrency guardrails)
- Branch: `security/atomic-upload-reservations-20261029`
- PR: to be opened against the PR #240 branch, not `main`, so the follow-up stays narrowly scoped.
- After #240 merges, retarget/rebase this PR onto `main` and rerun all checks before merge.

## 已改文件
- `lib/features/transfer/data/services/http_media_hub_service.dart`
- `test/features/transfer/http_media_hub_upload_test.dart`
- `docs/log/entries/2026-10-29-1815-atomic-upload-reservations.md`
- `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`

## 实现
- `_reserveIncomingDestination` uses `File.create(exclusive: true)` on a destination-specific `.reserve` marker. Contenders that cannot claim a name advance to the next suffix instead of deleting/using the same staging path.
- Temporary upload bodies are written into exclusive `.lyricforge-<uuid>.part` files, independent of the final filename.
- The destination marker remains claimed until the complete temporary file is renamed into place; it is then released. Error paths delete their own temporary file and the `finally` block releases the marker.
- The test gates both uploads at a shared disk-space probe so both same-name requests overlap, sends two different 128 KiB payloads, verifies both HTTP 201 results and distinct names, compares both SHA-256 hashes, and ensures no staging/marker files remain.

## 检查结果
- Source and regression test have been committed to the stacked branch.
- GitHub Actions final-head formatting, analyzer, and full tests must pass; local Flutter/Dart commands are unavailable here.
- PR #240's existing CI passed the upload guardrail implementation head, but this PR still needs its own CI after creation.

## 下一步
1. Open the stacked PR against `security/media-hub-upload-guardrails-20261029`.
2. Fix any Dart formatter/analyzer/test findings from the final head; do not weaken the barrier test or digest assertions.
3. Keep #234 open until #240 is merged, this branch is rebased to `main`, and the concurrent-upload test passes on the rebased final head.
4. Revisit stale `.reserve` markers after crash as separate cleanup policy only if needed; avoid silently deleting markers owned by in-flight uploads.

## 已知风险
- If the process is terminated mid-upload, the unique `.part` file and reservation marker may remain. This fails safe by forcing the next upload to another name, but orphan cleanup is not yet implemented.
- The exclusive marker protects cooperating Media Hub writers. An unrelated external process writing directly into the incoming directory can ignore this protocol.
- This PR is intentionally based on PR #240 because both issues modify the same upload handler. Do not merge/retarget it before the parent branch is incorporated.

最后更新：2026-10-29 18:15（Asia/Taipei）
