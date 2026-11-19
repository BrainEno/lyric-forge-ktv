# [2026-11-24 13:00] Put settings groups side by side on wide windows

- Scope: UI/UX audit SE-06. On a 1920 px window the settings page was one 1400 px column: the recognition runtime cards stretched across the screen and the troubleshooting group (diagnostics report, trial run) sat far below the fold. The new `SettingsColumns` places the two groups side by side from 1080 px of content width, recognition in the wider left column (3:2) and 故障排查 on the right; narrower windows and phones keep one column with recognition first, as before. Both groups are wrapped in global keys, so resizing the window across the breakpoint keeps their state (a runtime check or trial run in progress is not restarted).
- Files:
  - `lib/features/settings/presentation/widgets/settings_columns.dart` (new: `SettingsColumns`, breakpoint, flex and gap, state kept across the switch).
  - `lib/features/settings/presentation/screens/settings_screen.dart` (the two groups go through `SettingsColumns`).
  - Test: `test/features/settings/presentation/widgets/settings_columns_test.dart` (new: breakpoint, stacked below it, side by side with the 3:2 split above it, state kept across resizes both ways).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The cards inside already adapt to their own width (`SettingsSectionCard`, the runtime overview `LayoutBuilder`, `Wrap` button rows), so a 450 px right column at a 1280 px window does not overflow.
  - Order for screen readers and keyboard focus is unchanged: recognition, then troubleshooting.
- Commit: `Put settings groups side by side on wide windows`
