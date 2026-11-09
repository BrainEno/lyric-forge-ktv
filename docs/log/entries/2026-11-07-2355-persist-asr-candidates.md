# [2026-11-07 23:55] Persist independent ASR candidates

- Scope: Persist both the human-edited baseline and a separate rerun candidate without replacing the active lyrics.
- Files: Candidate store and focused tests, product follow-up, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42651644755: format after dependency resolution, candidate persistence/isolated rerun/file project repository tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions work-log run: formatting and work-log write/check; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: No UI or production caller; versions are bounded to five pairs and 512 KiB per pair, with no automatic eviction or deletion interface yet. Saving updates project revision; source checks are not locks, model contents are unverified and CAS is not cross-process. Repository persistence failure may leave its in-memory state changed. No real engine or song evaluation.
- Commit: `Persist independent ASR candidates`
