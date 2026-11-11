# [2026-11-07 20:47] Record secondary ASR segment evidence

- Scope: Retain individual secondary-engine segment text, timing and chunk origin to enable later evidence-based review of cross-chunk duplicates.
- Files: High-quality and chunked transcription services, targeted tests, handoff, index, entry and generated work-log navigation.
- Validation:
  - dart format on changed Dart files => passed on pinned SDK.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 42952041778.
  - flutter test --no-pub for high-quality ASR, resumable chunks and lyric inspector => passed in Actions 42952041778.
- Notes: Evidence is not verified alignment or an audio/model identity; chunk indices are session-local, and older checkpoints lack it. Candidate dedup retains only one candidate per merged row. Cross-chunk duplicate detection, real-song and device validation remain undone.
- Commit: `Record secondary ASR segment evidence`
