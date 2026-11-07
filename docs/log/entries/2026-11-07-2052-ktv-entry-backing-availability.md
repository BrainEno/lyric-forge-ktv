# [2026-11-07 20:52] Clarify KTV accompaniment availability

- Scope: Clarify that this version cannot generate or import accompaniment tracks when entering KTV without one; preserve original-mix and existing accompaniment selection.
- Files: Player screen, KTV entry sheet, focused widget tests, handoff, this entry and generated work-log navigation.
- Validation: Local Flutter/Dart SDKs unavailable. Pinned GitHub Actions run 42374238245 passed focused widget and backing-mode tests and the full repository quality gate; Dart format and work-log new/write/check ran there. Final PR checks reported separately. git diff --check ran locally.
- Notes: Tests exercise the real modal sheet with missing and preexisting instrumental paths, including selection and desktop/mobile-sized viewports; they do not play audio or validate file existence. Docs correction, stem import, and actual separation remain future work under #320. No native-device/manual visual checks performed.
- Commit: `fix: clarify ktv accompaniment availability`
