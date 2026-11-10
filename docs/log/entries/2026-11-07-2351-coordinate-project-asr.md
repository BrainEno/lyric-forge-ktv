# [2026-11-07 23:51] Coordinate project transcription resources

- Scope: Hold a shared ASR resource lease during normal project recognition and isolate cancellation ownership across queue, smoke test and project screens.
- Files: App assembly, project transcription workflow, queue pause guard, workflow and queue tests, assembly contract, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42797809015: format after dependency resolution, normal and independent workflows, batch queue, smoke test, project detail and assembly contract tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions work-log run checked formatting and generated/checked navigation; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: Lease spans preflight through commit and in-flight cancellation; cancel during the start write restores the run marker, and commit is non-cancellable. The queue honors a pause before starting recognition. Only same-isolate cooperating users share the gate; aligner, installation and production independent rerun remain unwired. Idle Qwen may retain GPU memory; devices and real models unverified.
- Commit: `Coordinate project transcription resources`
