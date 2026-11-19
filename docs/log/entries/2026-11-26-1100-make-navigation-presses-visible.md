# [2026-11-26 11:00] Make navigation presses visible

- Scope: Round 9 feedback on the bottom navigation (音乐库 and the other destinations): presses felt unanswered. The rail and the bottom bar answered only with the faint ink ripple, used Material's default indicator (the accent with a black icon, from the unset container roles), and pressing the destination already open pushed its page again. `AppNavigationRail` and `AppBottomNavigation` are now stateful: every press bumps a per-destination counter that pulses the icon with `AppTapPulse` and gives a selection click. The selected and unselected icons are built the same way so a moving selection does not cut the pulse short. The navigation bar and rail themes from the first commit give them the deep lavender indicator, light lavender selected icon, grey unselected icons and a bold white selected label. Re-pressing the open destination is a no-op through `goToDestination`.
- Files:
  - `lib/core/navigation/app_navigation_shell.dart`.
  - `test/core/navigation/app_navigation_shell_test.dart` (pulse on re-press in the bar and the rail, selection click, indicator, icon and label colours).
  - `test/core/navigation/destination_navigation_test.dart` (new: `planDestinationTap` for first pages, deeper pages, other destinations and unknown routes; `goToDestination` pushing, staying and popping to the root).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Not checked on a device; haptics only fire where the platform supports them.
- Commit: `Make navigation presses visible`
