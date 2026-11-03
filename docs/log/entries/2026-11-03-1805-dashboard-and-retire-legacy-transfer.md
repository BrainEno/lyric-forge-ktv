# [2026-11-03 18:05] Inject the dashboard and retire legacy sharing UI

- Scope: Phase 4.2, sixth step — remove the dashboard's partial singleton fallback and retire the old desktop sharing screen. `DashboardScreen` now requires one `DashboardDependencies` bundle (five activity/playback collaborators plus the transcription settings store), assembled by `lib/app/home_assembly.dart`. The 559-line `DesktopMediaSharingScreen` had no construction sites; `/mediaSharing` already routes to `DesktopMediaTransferHubV2Screen`, so the unreachable duplicate was deleted rather than made injectable. The feature singleton ratchet drops from 16 / 14 files to 12 / 12.
- Files: `lib/features/home/presentation/dashboard_dependencies.dart` (new), `lib/app/home_assembly.dart` (new), `lib/features/home/presentation/screens/dashboard_screen.dart`, `lib/app/app_router.dart`, deleted `lib/features/transfer/presentation/screens/desktop_media_sharing_screen.dart`, `test/features/home/presentation/screens/dashboard_screen_test.dart`, `test/architecture/app_assembly_contract_test.dart` (ratchet 16/14 → 12/12), `test/architecture/workflow_screen_injection_contract_test.dart` (dashboard assembly + V2 routing + dead-file contract).
- Validation:
  - PR #307: all three checks passed — Flutter Quality Gate 41615427203, readiness-gate 41615427165, widget-root 41615426993.
  - Full quality gate passed formatting, analyze, work-log preflight and full Flutter test suite. Existing dashboard empty-state and error→retry widget tests now construct it from explicit fakes.
  - After merge commit `f5bbbba`, `main` push quality gate run 41615872789 passed.
  - Local `git diff --check` and relative-import existence check passed; this workspace has no Flutter/Dart SDK.
- Notes: No ASR decoding, lyric content, playback, dashboard layout or interaction changed. `TranscriptionConfigDialog` remains a shared singleton consumer (dashboard, settings, ASR setup) and is deferred. The desktop transfer route remains V2; deleting the unreferenced legacy class does not alter production routing. No hardware or real-song validation is claimed.
- Commit: `refactor: inject dashboard and remove legacy sharing screen`
