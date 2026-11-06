# [2026-11-06 09:26] Cover Chinese ASR fusion regressions

- Scope: Extend issue #317's multilingual regression coverage into the dual-engine fusion path for Chinese and representative supported scripts, in both Qwen-primary and Whisper-primary orders.
- Files: `test/asr_text_comparison_test.dart`; `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-06-0926-chinese-asr-fusion-regressions.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate run `42143570966` passed on code head `179fcdcf1b1029ecd2046aa22089871064cd0992`, including work-log preflight, changed-file formatting, analyze, and the full repository test suite.
  - The first docs-updated head gate `42143980555` passed preflight and format but failed the unrelated existing Media Hub total-upload-deadline test (`test/features/transfer/http_media_hub_upload_test.dart`); no code in that test or its implementation changed in this slice. The follow-up PR-head gate `42144345101` passed on `6a5397c18ac27c406287b7f4928dd6335930d82b`, including preflight, format, analyze, and the full test suite.
  - Local Flutter tests/analyze => not run because Flutter/Dart SDK is unavailable; pinned CI supplied the results.
- Notes: The shared comparison test now includes Chinese preservation and distinct-text similarity. Dual-engine tests cover diacritic-folded English, Japanese, Greek, Cyrillic, and Chinese matching without duplicate or review rows in either engine order, plus distinct Chinese hypotheses surfaced for review in both orders. PR #357 is open; issue #317 remains open while remaining acceptance criteria are audited. No merge or issue-closure authorization is implied.
- Commit: `test: cover Chinese ASR fusion regressions`
