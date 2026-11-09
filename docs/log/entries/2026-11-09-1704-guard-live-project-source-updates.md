# [2026-11-09 17:04] Guard live project audio source updates

- Scope: First phase of safely updating inactive project audio source paths without interrupting current playback.
- Files: Audio source update domain guard and capability, just_audio adapter, Media Hub audio wrapper, focused tests, this entry, generated work-log navigation, index and handoff.
- Validation: Pinned Flutter GitHub Actions run 42590251419 passed focused audio/Media Hub/session/KTV tests and full quality gate, plus Dart format and work-log new/write/check. Local git diff --check passed. Local Flutter/Dart unavailable; final PR checks reported separately.
- Notes: This capability is not connected to any UI or playback-session queue yet; the documented accompaniment workaround still applies. The guard refuses stale source paths, unknown or changed active source, nonproject audio, outstanding loads, and failed just_audio loads. Media Hub wrapper forwards only to a supporting delegate and rejects overlapping loads. Tests exercise the pure path guard and a fake wrapper, not real just_audio/native playback; project identity and queue consistency must be checked by a future session-layer caller. Cross-process file changes, active-source replacement, native device behavior, and #320 remain open.
- Commit: `feat: guard live project source updates`
