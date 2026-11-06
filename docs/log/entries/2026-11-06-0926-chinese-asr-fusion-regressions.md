# [2026-11-06 09:26] Cover Chinese ASR fusion regressions

- Scope: Extend issue #317's multilingual regression coverage into the dual-engine fusion path for Chinese and representative supported scripts, in both Qwen-primary and Whisper-primary orders.
- Files: `test/asr_text_comparison_test.dart`; `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-06-0926-chinese-asr-fusion-regressions.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate run `42143570966` passed on code head `179fcdcf1b1029ecd2046aa22089871064cd0992`, including work-log preflight, changed-file formatting, analyze, and the full repository test suite.
  - Local Flutter tests/analyze => not run because Flutter/Dart SDK is unavailable; pinned CI supplied the result.
- Notes: The shared comparison test now includes Chinese preservation and distinct-text similarity. Dual-engine tests cover diacritic-folded English, Japanese, Greek, Cyrillic, and Chinese matching without duplicate or review rows in either engine order, plus distinct Chinese hypotheses surfaced for review in both orders. PR #357 is open; issue #317 remains open while remaining acceptance criteria are audited. No merge or issue-closure authorization is implied.
- Commit: `test: cover Chinese ASR fusion regressions`
