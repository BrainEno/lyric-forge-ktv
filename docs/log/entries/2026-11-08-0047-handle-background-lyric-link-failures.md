# [2026-11-08 00:47] Handle background lyric link failures

- Scope: Prevent first-lyric background association failures from escaping as uncaught asynchronous errors after a project has already been saved.
- Files: FileProjectRepository, file project repository regression tests, index, handoff, this entry and generated work-log navigation.
- Validation: Local Flutter/Dart SDKs unavailable. Pinned GitHub Actions run 42392786664 passed focused project, lyric-linking, player and transcription cancellation tests and the full repository quality gate; Dart format and work-log new/write/check ran there. Final PR checks reported separately. git diff --check ran locally.
- Notes: Background failures log the original error and stack, and an optional observer can receive them; an observer failure is also caught and logged. File-backed corrupted metadata, injected read/write failures and existing successful linking are tested. A failed association is not surfaced in the current UI or automatically retried; explicit awaited linking retains its error semantics. Local diagnostic errors may contain file paths. No native playback or manual UI checks performed.
- Commit: `fix: handle background lyric link failures`
