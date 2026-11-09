# [2026-11-07 23:59] Assess saved ASR candidate freshness

- Scope: Report whether a saved rerun candidate still matches current lyrics and selected audio without applying or changing either version.
- Files: Candidate assessor, candidate-store baseline comparison, focused tests, product follow-up, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42655844804: format after dependency resolution, candidate assessment/store/rerun tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions work-log run: formatting and work-log write/check; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: Assessment is point-in-time, not authorization to overwrite lyrics. Model contents and settings remain unverified; audio checks are not locks and repository CAS is not cross-process. No UI or production caller, no safe apply or deletion, and no real engine or song evaluation.
- Commit: `Assess saved ASR candidate freshness`
