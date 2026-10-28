# [2026-10-28 19:45] Supervise resumable audio chunk processes

- Scope: Bound resumable chunking's audio-duration probe and FFmpeg chunk extraction so a stalled native child cannot hold a long transcription job indefinitely; preserve completed recovery checkpoints.
- Files: `lib/features/transcription/data/services/resumable_chunked_transcription_service.dart`, `test/resumable_chunked_transcription_service_test.dart`, `test/features/transcription/transcription_execution_failure_kind_test.dart`, `docs/engineering_risks_roadmap.md`, `docs/log/entries/2026-10-28-1945-supervise-resumable-chunk-processes.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/handoff.md`.
- Validation:
  - Results below were run on code/test head `4abb4411f443072c38753b765c4fd14a5f451227`.
  - Flutter Quality Gate passed (run [40684224252](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40684224252)); all 780 tests passed and work-log lint reported 0 errors and 0 warnings.
  - ASR client checks passed (run [40684224285](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40684224285)).
  - Transcription settings validation passed (run [40684224262](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40684224262)).
  - Transcription execution failure validation passed (run [40684224265](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40684224265)).
  - Local Dart/Flutter commands were not run because SDKs are unavailable in this environment; re-check all workflows on the final documentation-refresh head before merging.
- Notes: Duration probing uses a 45-second hard deadline; FFmpeg chunk extraction uses the shared 5–60-minute source-size-aware budget. Both paths keep bounded stderr diagnostics, classify timeout/missing-executable failures as environment failures, and keep input/decoding failures distinct. Cleanup deletes only incomplete or failed chunk WAVs; it does not delete successful checkpoint JSON or rewrite the completed list.
- Commit: `fix: supervise resumable audio chunk processes (#214)`
