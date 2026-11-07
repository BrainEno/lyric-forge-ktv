# [2026-11-07 20:05] Preserve chunk cancellation boundaries

- Scope: Emit one wrapper-owned cancellation event for typed delegate cancellation and reject late chunk results after a cancellation request before checkpointing.
- Files: Resumable chunked transcription service and tests, handoff, this entry and generated work-log navigation.
- Validation: Local Flutter/Dart SDKs unavailable. Pinned GitHub Actions run 42370940932 passed the focused chunk tests and full repository quality gate; Dart format and work-log new/write/check ran there. Final PR checks are reported separately. git diff --check ran locally.
- Notes: Short and chunked delegate cancellations preserve the original typed exception, with or without a child cancellation progress event. A late successful result after cancellation is not added to the manifest; earlier completed checkpoints remain reusable. Cancellation arriving after checkpoint writing has started is outside this boundary. Real ASR and native process cancellation remain unverified.
- Commit: `fix: preserve chunk transcription cancellation boundaries`
