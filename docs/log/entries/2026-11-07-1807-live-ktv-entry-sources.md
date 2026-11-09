# [2026-11-07 18:07] Keep KTV entry source choices current

- Scope: Keep an open project KTV entry sheet aligned with current playback sources and reject stale choices.
- Files: Project player screen, KTV entry sheet, widget regression tests, this entry, generated work-log navigation, index and handoff.
- Validation: Pinned Flutter GitHub Actions run 42608484346 passed Dart format, targeted player/session/import tests, the full quality gate, and work-log new/write/check. Local git diff --check passed. Local Flutter/Dart unavailable; final PR checks reported separately.
- Notes: The open sheet follows matching session source and playback state changes, disables choices on item mismatch, and rechecks the selected path before and after source switching. Widget tests use fake audio and sessions; native devices and manual UI are unverified. Checks do not serialize async audio switching against concurrent song changes and do not detect an item changing away and back between observations. #320 remains open.
- Commit: `fix: keep KTV entry choices current`
