# [2026-11-07 23:54] Highlight differences in proofreading proposals

- Scope: Make changed text easier to spot in V2 proofreading review without modifying proposal acceptance or saving.
- Files: V2 review dialog and widget tests, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42767471733: format after dependency resolution, V2 dialog, character diff and document composer tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions run checked formatting and generated/checked work-log files; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: Text-only display; timing-only changes and inserted rows stay readable, approval logic is unchanged. The existing diff uses Unicode code points, not grapheme clusters, and marks entire long inputs when the matrix limit is exceeded. Actual devices and real-song accuracy remain unverified.
- Commit: `Highlight differences in proofreading proposals`
