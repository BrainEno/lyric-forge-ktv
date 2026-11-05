# [2026-11-05 18:16] Stabilize Media Hub upload TLS test

- Scope: Address CI's intermittent `SocketException: Broken pipe` during `SecureSocket.connect` in the total-upload-deadline test. Retry only a transient loopback TLS broken pipe up to three times with bounded backoff; keep other socket, TLS, and assertion failures visible.
- Files: `test/features/transfer/http_media_hub_upload_test.dart`, this entry, generated work-log navigation, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Temporary WASM `@wasm-fmt/dart_fmt` formatter check => passed for the changed test.
  - Local Flutter/Dart tests => not run because the pinned SDK is unavailable in this workspace.
  - Pinned Flutter Quality Gate run `42008920419` => passed on implementation/test head `f68cd80400a7dcc366857fa8618e4ec86d9a4eb8`, including work-log preflight, changed-Dart format, analysis, and full tests.
- Notes: The earlier failing run `42006114278` showed the unrelated upload test failing at TLS socket connect; the bounded retry addresses only EPIPE. PR #350 remains open and is not authorized for merge. No production Media Hub code changed.
- Commit: `test: retry transient Media Hub TLS broken pipes`
