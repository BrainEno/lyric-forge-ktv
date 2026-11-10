# [2026-11-07 23:57] Fix chunk transcription terminal events

- Scope: Prevent individual ASR attempts from reporting a final whole-task outcome and honor cancellation while chunk results are merged.
- Files: Resumable chunk transcription service and focused tests, product follow-up, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42749328039: format after dependency resolution, chunk/high-quality/project-cancellation/typed-cancellation tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions work-log run: format check and work-log write/check; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: A checkpoint already being committed is completed and cleaned before cancellation is honored; JSON and manifest are not a cross-file transaction. A canceled merge may leave a generated file but never returns success. Device and real-song verification remain open; no recognition accuracy gain is claimed.
- Commit: `Fix chunk transcription terminal events`
