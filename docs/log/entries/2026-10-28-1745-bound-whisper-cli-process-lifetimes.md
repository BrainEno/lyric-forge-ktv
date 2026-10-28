# [2026-10-28 17:45] Bound Whisper CLI process lifetimes

- Scope: Prevent whisper.cpp jobs from waiting forever when executable probes, FFmpeg preprocessing, or inference stops exiting; make cancellation and timeout terminate the child within a bounded window and remove partial outputs.
- Files: `lib/features/transcription/data/services/asr_process_supervisor.dart`, `lib/features/transcription/data/services/whisper_cpp_transcription_service.dart`, `test/features/transcription/asr_process_supervisor_test.dart`, `docs/engineering_risks_roadmap.md`, `docs/log/entries/2026-10-28-1745-bound-whisper-cli-process-lifetimes.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/handoff.md`.
- Validation:
  - GitHub Actions Flutter Quality Gate passed; repository quality gate reported `01:13 +773: All tests passed!`, with work-log lint at 0 errors and 0 warnings.
  - ASR client checks passed.
  - Transcription settings validation passed.
  - Transcription execution failure validation passed, including the high-quality fallback regression.
  - Added fake-process tests for bounded output tails, timeout termination and escalation, cancellation escalation, non-zero exit codes, inherited-pipe drain limits, and operation timeout budget scaling.
  - Local Dart/Flutter commands were not run because the SDKs are unavailable in this execution environment.
- Notes: This phase migrates the whisper.cpp adapter only. Qwen server/request, resumable FFprobe/FFmpeg, and high-quality shared normalization are still outstanding. Timeout budgets are heuristics; real-child behavior and complete descendant cleanup still require Windows/macOS verification.
- Commit: `fix: bound Whisper CLI process lifetimes (#211)`
