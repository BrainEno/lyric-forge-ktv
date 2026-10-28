# [2026-10-28 19:45] Supervise resumable audio chunk processes

- Scope: Bound resumable chunking's audio-duration probe and FFmpeg chunk extraction so a stalled native child cannot hold a long transcription job indefinitely; preserve completed recovery checkpoints.
- Files: `lib/features/transcription/data/services/resumable_chunked_transcription_service.dart`, `test/resumable_chunked_transcription_service_test.dart`, `test/features/transcription/transcription_execution_failure_kind_test.dart`, `docs/engineering_risks_roadmap.md`, `docs/log/entries/2026-10-28-1945-supervise-resumable-chunk-processes.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/handoff.md`.
- Validation:
  - GitHub Actions checks are being run on the PR head; see the PR Actions before merging.
  - Regression tests cover bounded duration-probe timeout, cancellation escalation and typed cancellation, partial WAV cleanup, and preservation of a completed JSON checkpoint and manifest entry after an extraction failure. The existing failure-kind fixture now emits a non-empty WAV-like output so it can exercise delegate failure classification under the new output-integrity check.
  - Local Dart/Flutter commands were not run because SDKs are unavailable in this environment.
- Notes: Duration probing uses a 45-second hard deadline; FFmpeg chunk extraction uses the shared 5–60-minute source-size-aware budget. Both paths keep bounded stderr diagnostics, classify timeout/missing-executable failures as environment failures, and keep input/decoding failures distinct. Cleanup deletes only incomplete or failed chunk WAVs; it does not delete successful checkpoint JSON or rewrite the completed list.
- Commit: `fix: supervise resumable audio chunk processes (#214)`
