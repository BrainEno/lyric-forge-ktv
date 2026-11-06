# [2026-11-06 10:03] Keep empty-normalized ASR rows unmatched

- Scope: Add an end-to-end regression proving non-empty lyric strings that both normalize to empty are not treated as matching rows in either dual-engine order.
- Files: `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-06-1003-empty-normalized-fusion-regression.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate run `42147456078` passed work-log preflight and changed-file formatting; the full suite failed only at the unrelated existing `test/features/transfer/http_media_hub_upload_test.dart` total-upload-deadline test. It reported 1170 passing tests and that single failure.
  - Docs-updated head run `42147925809` repeated the same single unrelated test failure after preflight and formatting passed. GitHub refused rerun (`run cannot be rerun; its workflow file may be broken`); a new PR-head run is needed to validate the final head.
  - Local Flutter tests/analyze => not run because Flutter/Dart SDK is unavailable; pinned CI supplied the available results.
- Notes: Qwen-primary and Whisper-primary cases compare `'!? 🎵'` with `'♪'`; both normalize to empty, so the primary row remains and the unmatched secondary is surfaced as a review-only row rather than being silently merged. PR #358 is open; issue #317 remains open. No merge or issue-closure authorization is implied.
- Commit: `test: keep empty-normalized ASR rows unmatched`
