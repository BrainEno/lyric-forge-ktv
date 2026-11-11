# [2026-11-07 20:50] Coordinate ASR installation ownership

- Scope: Prepare a per-caller installation facade for shared ASR resource coordination and cancellation ownership.
- Files: Installation coordination facade and tests, handoff, work-log index, entry, generated summary and archive.
- Validation:
  - dart format on changed Dart files => passed on pinned SDK.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 42848531494.
  - flutter test --no-pub for installation coordination, preflight cancellation, resource coordinator, project cancellation, independent rerun workflow and smoke service => passed in Actions 42848531494.
- Notes: Not wired to production. Correct ownership requires every shared-delegate installation to use a separate facade with the same coordinator; it cannot force cancellation of an uncooperative delegate. Repair, storage operations, cross-process resources and real-device behavior remain unverified.
- Commit: `Coordinate ASR installation ownership`
