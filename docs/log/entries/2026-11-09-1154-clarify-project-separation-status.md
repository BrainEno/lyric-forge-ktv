# [2026-11-09 11:54] Clarify project separation status

- Scope: Clarify current separation limitations in project details and documentation without changing the desktop separation product goal or playback behavior.
- Files: README, PRD status note, project detail screen, project-detail widget and documentation contract tests, index, handoff, this entry and generated work-log navigation.
- Validation: Local Flutter/Dart SDKs unavailable. Pinned GitHub Actions run 42558639091 passed focused project widget, documentation and KTV tests and the full repository quality gate; Dart format and work-log new/write/check ran there. Earlier full gate run 42558336604 failed the Media Hub upload deadline test with a Broken pipe; final PR checks are reported separately. git diff --check ran locally.
- Notes: The PRD keeps separation as a desktop MVP goal, explicitly distinct from current implementation. Missing project audio no longer implies waiting for accompaniment; a legacy separation stage reports a recorded stage rather than asserting tracks exist. Tests cover compact/desktop logical layouts and fake project data, not real file existence, native playback or manual UI checks. External stem import, a separation backend and full #320 acceptance remain open.
- Commit: `fix: clarify project separation status`
