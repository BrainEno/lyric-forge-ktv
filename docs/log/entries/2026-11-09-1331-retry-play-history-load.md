# [2026-11-09 13:31] Retry failed play history loads

- Scope: Allow a failed initial file-backed play-history load to be retried by the same repository after storage is repaired.
- Files: File play-history repository and real-file tests; this entry, generated work-log navigation, index and handoff.
- Validation: Pinned Flutter GitHub Actions run 42567560503 passed focused history/dashboard tests and the full quality gate, with Dart format and work-log new/write/check. Local git diff --check passed; Flutter/Dart are unavailable locally. Final PR checks reported separately.
- Notes: Concurrent callers share the in-flight load and receive its original failure; successful loads remain cached. Real-file tests preserve an invalid canonical store on failure, repair it, then verify same-instance retry and subsequent persistence. Other repositories still cache failed loads; malformed individual history entries and post-validation read errors retain their existing best-effort behavior. External edits after a successful load remain invisible; no cross-process synchronization is added. Physical device and manual UI verification were not performed. Issue #223 remains open.
- Commit: `fix: retry failed play history loads`
