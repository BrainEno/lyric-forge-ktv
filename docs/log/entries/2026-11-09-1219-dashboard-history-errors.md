# [2026-11-09 12:19] Show dashboard history read failures

- Scope: Distinguish a failed recent playback-history read from an empty history, allow retry and observe early errors before FutureBuilder subscribes.
- Files: Dashboard screen and widget tests; this entry, generated work-log navigation, index and handoff.
- Validation: Pinned Flutter GitHub Actions run 42560926452 passed dashboard widget tests and the full quality gate; it ran Dart format and work-log new/write/check. Earlier focused run 42560804967 exposed an unhandled retry-time history error before FutureBuilder subscribed, addressed before this run. Local git diff --check passed. Final PR checks are reported separately; local Flutter/Dart are unavailable.
- Notes: The retry uses the existing dashboard-wide refresh, so both history and recent projects reload. Tests cover repeated immediate failures of either or both repositories and recovery to a populated shelf with fake repositories, not real devices or visual inspection. File repositories that swallow or cache errors cannot be repaired by this UI; #223 remains open. The unrelated Media Hub total-upload deadline test has previously failed intermittently with Broken pipe.
- Commit: `fix: show dashboard history read failures`
