# [2026-11-09 13:46] Retry failed project store loads

- Scope: Allow the same file project repository to retry an initial load after its project store is repaired, enabling existing dashboard retry.
- Files: File project repository, real-file project repository tests, this entry, generated work-log navigation, index and handoff.
- Validation: Pinned Flutter GitHub Actions run 42568975231 passed focused project, dashboard, lyric resolver and atomic-persistence tests and the full quality gate, with Dart format and work-log new/write/check. Local git diff --check passed; Flutter/Dart are unavailable locally. Final PR checks reported separately.
- Notes: Concurrent callers share in-flight loads and receive original failures; successful loads stay cached. Real-file tests cover top-level corruption, malformed or duplicate records, preservation of canonical/backup files, same-instance repair, and persistence after retry. Dashboard retry itself has separate widget coverage with fake repositories, not a real-file end-to-end widget test. Other repositories may still cache failures; successful loads do not see external edits and cross-process writes have no CAS. Physical device and manual UI verification were not performed. Issue #223 remains open.
- Commit: `fix: retry failed project store loads`
