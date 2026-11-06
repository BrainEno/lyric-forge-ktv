# [2026-11-06 13:37] Stabilize Media Hub total-upload-deadline regression

- Scope: Remove timing flakiness from the Media Hub total-upload-deadline regression without weakening its scenario; explicitly prove upload chunks continue arriving before the total deadline.
- Files: `test/features/transfer/http_media_hub_upload_test.dart`; `docs/log/entries/2026-11-06-1337-stabilize-media-hub-total-upload-deadline.md`; generated work-log navigation; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate `42169233340` on code head `d06c94efebb20193923dec4a0c38f1667f749649` => work-log preflight, changed-file formatting, and repository quality gate all passed.
  - Earlier heads `42147456078`, `42147925809`, and `42148380426` each failed only at this test (1170 passing tests, one failing test); the failure logs could not be retrieved from GitHub Actions.
  - Local Flutter/Dart tests/analyze => not run because Flutter/Dart SDK is unavailable; validation is through pinned CI.
- Notes: The regression now gives loopback TLS and a loaded runner more headroom (total deadline 250 ms → 1 s; idle timeout 2 s → 3 s) and asserts at least one continuing chunk was sent before the expected 408 response. PR #358 remains open. The passing code-head gate does not validate the documentation/handoff commit that follows; merge only after the final PR-head pinned gate is green. The user explicitly authorized merging PR #358 subject to that green gate. Issue #317 remains open.
- Commit: `test: stabilize Media Hub total upload deadline regression`
