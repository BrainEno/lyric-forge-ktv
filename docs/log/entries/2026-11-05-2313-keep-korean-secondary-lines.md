# [2026-11-05 23:13] Keep Korean-only secondary lines

- Scope: Verify that a valid Korean lyric heard only by the secondary engine survives dual-engine fusion as a review-only row, in both Qwen-primary and Whisper-primary order.
- Files: `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-05-2313-keep-korean-secondary-lines.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate run `42053030878` failed at `Format check for changed Dart files`; analyze/tests did not run. The runner log is not accessible from this environment, so the exact formatter diff is needed to correct the final discrepancy.
  - Local focused Flutter test => not run because Flutter/Dart SDK is unavailable.
- Notes: This is an independent acceptance slice for issue #317, covering the genuinely secondary-only Korean row path rather than a paired disagreement candidate. PR #355 is open; chunk-merge coverage remains a separate follow-up. No PR merge or issue closure is authorized.
- Commit: `style: format Korean secondary-line test`
