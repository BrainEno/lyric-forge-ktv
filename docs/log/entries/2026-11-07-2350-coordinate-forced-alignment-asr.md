# [2026-11-07 23:50] Coordinate forced alignment with ASR tasks

- Scope: Prevent V2 forced alignment from competing with cooperating ASR operations, and explicitly tell users to retry when the resource is busy without changing lyrics.
- Files: Editor assembly, forced alignment proofreading service, editor error copy and widget, coordinated runner and editor regression tests, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42814039053: format after dependency resolution, coordinated alignment, editor widget, forced alignment service, V2 assembler, review strings, project/independent workflows and app assembly tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions work-log run checked formatting and generated/checked navigation; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: The lease covers settings, readiness, native alignment and cleanup; busy aborts review and prompts a retry, while other errors keep the existing no-evidence fallback. Installation and production independent rerun remain unwired; no cross-process lock, idle Qwen shutdown or real device/model validation.
- Commit: `Coordinate forced alignment with ASR tasks`
