# [2026-11-07 20:53] Guard proofreading against stale editor state

- Scope: Discard V2 proposals built from an outdated in-memory lyric document and prevent overlapping V2 runs.
- Files: Editor controller and screen, targeted tests, handoff, index, entry and generated work-log navigation.
- Validation:
  - dart format changed Dart files with the pinned SDK => passed in Actions 42956931315.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 42956931315.
  - flutter test --no-pub for editor controller, screen, V2 dialog and forced alignment service => passed in Actions 42956931315.
- Notes: Only V2 is guarded; other async editor operations need separate audit. Native work is not cancelled. Final timeline-conflict confirmation race, real devices and accessibility remain unverified; no real-song accuracy claim.
- Commit: `Guard proofreading against stale editor state`
