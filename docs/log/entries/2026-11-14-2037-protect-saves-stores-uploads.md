# [2026-11-14 20:37] Protect lyric saves, local stores, and rejected uploads

- Scope: Fix audit findings R-01 to R-05 (#438-#442). "保存并返回" now waits for the write, stays on the editor after a failure, a conflict, or an edit made during the save, and pops once. Library and collection stores that are only partly readable keep the readable rows visible but refuse writes until the user confirms a repair; the repair first keeps a verified `.incomplete-<time>.json` copy. A failed first load is no longer cached, so the same repository instance retries. Relink checks both stores before its first write. The media hub releases upload resources before it answers, sends the rejection, then briefly drains the body before closing so the client is not reset before it reads the response. The remaining English proofreading text is now Chinese, and a source contract test guards against English-only sentences.
- Files: Lyric editor screen/content/document controller; `RetryableLoad`; local store integrity contract, preservation helper, and banner; library/collection/metadata repositories; relink service; explorer, collections, and favorite actions; media hub service; lyric review strings and proofreading coordinator; new and extended tests for save-and-return, store integrity, retryable load, the banner, relink preflight, upload rejection/slot release, and the language contract; handoff and work-log docs.
- Validation:
  - The sandbox has no Flutter/Dart SDK (storage.googleapis.com is unreachable). A temporary pinned-SDK branch workflow ran the checks and was removed before the PR.
  - Run 43595900121: `dart format` changed 7 files, which were committed. 8 new save-and-return tests and 2 existing conflict-dialog tests failed. Causes: an endless save spinner kept `pumpAndSettle` waiting behind the conflict dialog, and the test helper requested back before rebuilding. Both are fixed.
  - Run 43596922207 (head f8cd03b):
    - `dart tool/work_log.dart check` exit 0 (only the existing commit-subject warning).
    - `flutter analyze` showed no errors or warnings.
    - Focused tests: 215 passed.
    - `http_media_hub_upload_test.dart` passed 3 times in a row.
    - Full `flutter test`: 2016 passed, 1 skipped (Windows-only).
- Notes: #442 picks Simplified Chinese as the single supported UI language for proofreading, with Chinese as the fallback. Real locale switching would need `flutter_localizations` and a lockfile change, so it is not done here. Model and product identifiers (ForcedAligner, ASR, LRC) stay as written. The repair drops unreadable rows only after explicit confirmation and keeps a byte-verified copy.
- Commit: `Protect lyric saves, local stores, and rejected uploads`
