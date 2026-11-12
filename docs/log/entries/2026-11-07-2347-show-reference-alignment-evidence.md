# [2026-11-07 23:47] Show reference alignment evidence

- Scope: Allow V2 reference-first review to show read-only ForcedAligner line timing evidence without applying it.
- Files: V2 use case, review model and assembler, editor dialogs and strings, domain and widget tests, product follow-up, work-log navigation and handoff.
- Validation:
  - dart format changed Dart files => passed in Actions 43162831435.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 43162831435.
  - Targeted planner, orchestration, composer, editor, accessible dialog and architecture tests => passed in Actions 43162831435.
- Notes: Reference timing is read-only and not persisted or auditionable; applying it and handling offsets and provenance remain open. No real audio, runtime, device or screen-reader validation.
- Commit: `Route reference alignment into review evidence`
