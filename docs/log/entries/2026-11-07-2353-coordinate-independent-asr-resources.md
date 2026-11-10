# [2026-11-07 23:53] Coordinate independent ASR rerun resources

- Scope: Establish a shared non-queuing resource lease and require independent model reruns to hold it through preflight, recognition, cleanup and candidate persistence.
- Files: ASR resource coordinator and tests, independent rerun workflow and tests, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42781526241: format after dependency resolution, resource coordinator, independent rerun workflow/service and candidate store tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions work-log run checked formatting and generated/checked navigation; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: Only explicitly cooperating operations sharing the same instance in one isolate are excluded. Normal transcription, alignment and installation are not yet wired; no cross-process exclusion or idle Qwen GPU shutdown is provided. Native devices and real-model behavior remain unverified.
- Commit: `Coordinate independent ASR rerun resources`
