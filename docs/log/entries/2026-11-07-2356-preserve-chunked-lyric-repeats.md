# [2026-11-07 23:56] Preserve repeated lyrics when merging chunks

- Scope: Avoid deleting real repeated lyrics when stitching long-audio transcription chunks, while deduplicating confident overlap matches.
- Files: Chunk transcription service and regression tests, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42753283509: format after dependency resolution, chunk and high-quality transcription tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions work-log run checked formatting and generated/checked work-log files; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: Match only adjacent chunks with equal normalized text and positive time intersection inside shared audio, one-to-one. Conflicting timestamps or text can leave duplicates; inaccurate overlapping timestamps can still mispair repeated lines. Native devices and real songs were not tested; no measured accuracy gain is claimed.
- Commit: `Preserve repeated lyrics when merging chunks`
