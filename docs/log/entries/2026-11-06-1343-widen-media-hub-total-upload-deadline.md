# [2026-11-06 13:43] Widen Media Hub total-upload-deadline test margin

- Scope: Make the flaky Media Hub total-upload-deadline regression robust under a loaded CI runner after its first timing adjustment passed once but failed on a later full-suite run.
- Files: `test/features/transfer/http_media_hub_upload_test.dart`; `docs/log/entries/2026-11-06-1343-widen-media-hub-total-upload-deadline.md`; generated work-log navigation; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned gate `42169233340` on code head `d06c94efebb20193923dec4a0c38f1667f749649` passed the full repository quality gate once.
  - Pinned gate `42169695799` on docs head `a185b01c46c1f7c310a6d0c91ebf6a07d210d54e` failed only at this same test (1170 passing tests, one failure); GitHub's run annotations did not include the assertion, and downloading the failed log again returned EOF.
  - Local Flutter/Dart tests/analyze => not run because Flutter/Dart SDK is unavailable.
- Notes: Increase the total timeout to 5 seconds and idle timeout to 30 seconds, continue sending chunks for up to 200 × 30 ms while waiting for the response, and allow 15 seconds to read the response. This preserves the intended total-deadline-versus-idle-timeout assertion while providing substantially more scheduling headroom. PR #358 remains open; do not merge until a pinned gate on the final PR head passes. Issue #317 remains open.
- Commit: `test: widen Media Hub total deadline test margin`
