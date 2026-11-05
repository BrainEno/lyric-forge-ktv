# [2026-11-05 23:13] Keep Korean-only secondary lines

- Scope: Verify that a valid Korean lyric heard only by the secondary engine survives dual-engine fusion as a review-only row, in both Qwen-primary and Whisper-primary order.
- Files: `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-05-2313-keep-korean-secondary-lines.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate run `42053995785` passed on code head `9356a6092c9863ed56091e7282b6691b2e1ca9d8`, including work-log preflight, changed-file formatting, analyze, and the full repository test suite.
  - Local focused Flutter test => not run because Flutter/Dart SDK is unavailable; pinned CI supplied the test result.
- Notes: This is an independent acceptance slice for issue #317, covering the genuinely secondary-only Korean row path rather than a paired disagreement candidate. PR #355 is open; chunk-merge coverage remains a separate follow-up. No PR merge or issue closure is authorized.
- Commit: `docs: record Korean-only ASR gate`
