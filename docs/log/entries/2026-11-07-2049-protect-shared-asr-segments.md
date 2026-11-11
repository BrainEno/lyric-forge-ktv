# [2026-11-07 20:49] Protect shared secondary ASR segments

- Scope: Prevent automatic reuse of one secondary ASR segment across multiple primary lyric lines and require manual review of ambiguous segmentation.
- Files: High-quality transcription fusion and tests, lyric inspector and widget tests, handoff, index, entry and generated work-log navigation.
- Validation:
  - dart format on changed Dart files => passed on pinned SDK.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 42943660214.
  - flutter test --no-pub for high-quality ASR, resumable chunks and lyric inspector => passed in Actions 42943660214.
- Notes: Matches are heuristic; old saved candidates have no new shared-segment flag. No real-song or device validation or measured accuracy improvement. Installation ownership is not wired into production.
- Commit: `Protect shared secondary ASR segments`
