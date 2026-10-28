# [2026-10-28 18:18] Bound Qwen transcription request and child process lifetimes

- Scope: Prevent Qwen native-ASR executable checks, FFmpeg preprocessing, service startup/shutdown, or a stalled transcription HTTP response from holding a queue item indefinitely; ensure cancellation remains typed and failed preprocessing leaves no partial WAV.
- Files: `lib/features/transcription/data/services/asr_process_supervisor.dart`, `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`, `test/features/transcription/qwen3_asr_native_transcription_service_test.dart`, `docs/engineering_risks_roadmap.md`, `docs/log/entries/2026-10-28-1818-bound-qwen-transcription-lifetimes.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/handoff.md`.
- Validation:
  - Code-only PR head `f992af3050cb34a0ecbefca9292706b7b7c09218` passed GitHub Actions Flutter Quality Gate: `01:21 +775: All tests passed!`.
  - ASR client checks passed (run `40670616102`).
  - Transcription settings validation passed (run `40670615909`).
  - Transcription execution failure validation passed (run `40670615863`).
  - Added fake-process coverage for Qwen FFmpeg cancellation escalation, cancelled-operation classification, partial-WAV cleanup, and Qwen request-budget scaling/capping.
  - Local Dart/Flutter commands were not run because SDKs are unavailable in this environment; the documentation refresh has its own final-head checks.
- Notes: Qwen `/v1/transcribe` now has a duration-aware request/response deadline, but `ForcedAlignmentHttpClient` `/v1/align` still needs its own request deadline. Resumable FFprobe/FFmpeg and high-quality shared normalization remain follow-up work. Termination is bounded for direct children only; Windows/macOS real-process and descendant cleanup guarantees remain unverified.
- Commit: `fix: bound Qwen transcription request and child process lifetimes (#212)`
