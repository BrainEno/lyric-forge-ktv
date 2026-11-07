# [2026-11-07 07:14] Make ASR cancellation type-driven

- Scope: Propagate typed cancellation through dual-engine recognition, chunk retries, project workflow, queue and runtime preparation without interpreting display text; retain checkpoints and editable lyrics.
- Files: ASR transcription and runtime services, batch queue, focused regression tests, handoff, this entry and generated work-log navigation.
- Validation: Local Flutter and Dart SDKs were unavailable and the SDK download host was inaccessible. On pinned GitHub Actions run 42350935756, focused tests, repository quality gate (including scoped analyze and full tests), and work-log write/check passed. Run 42351271943 formatted the changed Dart files after package resolution and passed the format recheck and work-log write/check. Standalone `flutter analyze --no-pub` exited non-zero with 113 informational findings; the repository gate makes infos non-fatal. Consult PR checks for final-head results. `git diff --check` was run locally.
- Notes: Child-engine terminal progress is mapped to non-terminal orchestration progress. Runtime installation cancellation previously also used message checks and untyped exceptions; the queue now pauses rather than recording typed cancellation as a failure. Real ASR hardware and process cancellation remain unverified locally.
- Commit: `fix: make transcription cancellation type-driven`
