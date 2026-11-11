# [2026-11-07 20:48] Preserve shared ASR review across chunks

- Scope: Preserve the restrictive shared-secondary review candidate when overlapping transcription chunks resolve to the same lyric line.
- Files: Chunk metadata merge and tests, handoff, index, entry and generated work-log navigation.
- Validation:
  - dart format on changed Dart files => passed on pinned SDK.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 42949968911.
  - flutter test --no-pub for resumable chunks, high-quality ASR and lyric inspector => passed in Actions 42949968911.
- Notes: Preferring a shared candidate may hide another candidate for the same merged row. Independently fused chunks may miss cross-boundary sharing, old outputs lack the flag, and no real-song accuracy or device validation was performed.
- Commit: `Preserve shared ASR review across chunks`
