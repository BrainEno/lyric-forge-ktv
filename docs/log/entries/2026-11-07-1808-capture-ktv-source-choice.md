# [2026-11-07 18:08] Capture KTV source path at selection

- Scope: Capture the exact audio source path when a KTV choice is tapped so later sheet rebuilds cannot change the guarded selection.
- Files: KTV entry sheet, project player screen, sheet and player widget tests, this entry, generated work-log navigation and handoff.
- Validation: Pinned Flutter GitHub Actions run 42615096091 passed Dart format, targeted player/session/import tests, the full quality gate, and work-log new/write/check. Local git diff --check passed. Local Flutter/Dart unavailable; final PR checks reported separately.
- Notes: The sheet returns the mode and displayed path together; the player checks that immutable path before and after switching. Fake widget tests exercise both modes and a replacement after tapping. No production audio locking was added: concurrent native switching and song changes, including away-and-back races, remain unprotected. Manual UI and native playback were not tested; #320 remains open.
- Commit: `fix: capture KTV source path at selection`
