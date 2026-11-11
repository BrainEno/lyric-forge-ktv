# [2026-11-07 20:55] Extract V2 proofreading orchestration

- Scope: Extract V2 proofreading orchestration from the editor without changing existing strategy behavior (partial #323).
- Files: V2 domain use case, editor screen, use-case tests, UX undo guidance, handoff and work-log navigation.
- Validation:
  - dart format changed Dart files with pinned SDK => passed in Actions 43023659317.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 43023659317.
  - flutter test --no-pub on V2 use case, pipelines, review widgets, editor and architecture contracts => passed in Actions 43023659317.
- Notes: #323 remains open; other workflows and the screen size and UX audit remain. #319 reference-first forced alignment and automatic secondary transcript are not implemented. Real devices, audio, ASR and real-song quality were not tested.
- Commit: `Extract V2 proofreading orchestration`
