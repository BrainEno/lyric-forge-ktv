# [2026-11-07 20:57] Extract reference alignment application workflow

- Scope: Extract reference alignment preparation, protection, application, backup and provenance from the editor (partial #323).
- Files: Reference alignment use case, editor screen, domain and widget regression tests, handoff and work-log navigation.
- Validation:
  - dart format changed Dart files with pinned SDK => passed in Actions 43048158770.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 43048158770.
  - flutter test --no-pub targeted alignment, proofreading, backup, editor and architecture tests => passed in Actions 43048158770.
- Notes: #323 remains open: editor size, entry-point lengths and complete UX audit remain. Caller retains revision checks and timeline confirmation. No real device, native picker, audio, screen reader or song quality checks.
- Commit: `Extract reference alignment application workflow`
