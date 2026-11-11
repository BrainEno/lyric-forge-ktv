# [2026-11-07 20:54] Record fusion timing text provenance

- Scope: Record fusion text/timing snapshots and mark changed or secondary-only rows for future realignment without changing recognition or playback policy.
- Files: Fusion timing evidence contract, high-quality and chunked services, targeted tests, ASR baseline documentation, handoff, index, entry and generated work-log navigation.
- Validation:
  - dart format changed Dart files using pinned SDK => passed in Actions 42976781024.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 42976781024.
  - flutter test --no-pub for timing evidence, fusion, chunks, lyric inspector and architecture contracts => passed in Actions 42976781024.
- Notes: Snapshots are not proof of alignment or audio/model identity; alignedTextHash is unknown, old/degraded evidence may be missing, and false means no fusion-specific flag rather than verified. No UI, automatic realignment, real-song accuracy or device validation.
- Commit: `Record fusion timing text provenance`
