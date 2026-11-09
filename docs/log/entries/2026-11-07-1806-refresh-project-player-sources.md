# [2026-11-07 18:06] Refresh project player source choices from session

- Scope: Keep an open project player source selector and KTV entry aligned with its current session item after a guarded source update.
- Files: Project player screen, widget regression tests, this entry, generated work-log navigation, index and handoff.
- Validation: Pinned Flutter GitHub Actions run 42606167300 passed Dart format, targeted player/session/import tests, the full quality gate, and work-log new/write/check. Local git diff --check passed. Local Flutter/Dart unavailable; final PR checks reported separately.
- Notes: Matching current project items use their session audio asset rather than a stale project snapshot, including after a rejected sync. Other items fall back to the project snapshot. Widget tests use fake audio and session; no real device playback or manual UI checks were performed. An already open KTV sheet does not live-update; switch-song/reopen fallback and #320 remain.
- Commit: `fix: refresh project player source choices from session`
