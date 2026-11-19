# [2026-11-25 12:10] Draw the brand mark from the app icon

- Scope: UI/UX audit B-01 (with the visual half of D-01), first step. Nothing in the interface echoed the red, black and paper-white app icon: the navigation rail showed Material's generic `graphic_eq` icon and the dashboard header only the product name. `AppColors.brand` (Forge Red `#F11413`) and `AppColors.brandPaper` (`#F6F2E8`) are sampled from `assets/images/icon.png`, and the new `AppBrandMark` draws the icon's fading equalizer with its one red bar. It replaces the rail's `graphic_eq` (with the product name as tooltip) and sits beside the name in the dashboard header, where it is excluded from semantics because the visible name is read instead. The mark is painted rather than loaded from the icon file, because the file carries a light outer margin that would show as a white tile on the dark rail.
- Files:
  - `lib/core/theme/color_tokens.dart` (`brand`, `brandPaper`).
  - `lib/core/widgets/app_brand_mark.dart` (new).
  - `lib/core/navigation/app_navigation_shell.dart` (rail leading).
  - `lib/features/home/presentation/screens/dashboard_screen.dart` (header identity row; the name comes from `appDisplayName`).
  - `test/core/widgets/app_brand_mark_test.dart` (new: bars fade like the icon; Forge Red reaches 3:1 on every dark surface and is not the error color; size from height; one red bar among paper-white ones; default and empty labels).
  - `test/core/navigation/app_navigation_shell_test.dart` (the rail shows the mark and no `graphic_eq`; the bottom bar has none).
- Validation:
  - Contrast (WCAG relative luminance, computed): Forge Red on `bgBase` 4.33:1, on `bgElevated` 4.10:1, on `bgSurface` 3.40:1; paper white on them 16.8, 15.9 and 13.2:1.
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and the temporary format probe.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Decision: Forge Red stays out of buttons, text and states for now. The audit proposed it for the primary call to action and the KTV current line too, but the error color `#E22134` is a near neighbour, so red actions would read as destructive; moving the accent away from green (A-01) needs that conflict settled first and a maintainer decision.
- Commit: `Draw the brand mark from the app icon`
