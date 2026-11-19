# [2026-11-26 10:30] Give lavender buttons readable foregrounds

- Scope: Round 9 feedback: parts of the purple buttons had poor contrast. Two theme gaps caused it. (1) The icon button theme set a grey foreground, and Material applies that theme to every icon button variant, so the icons of `IconButton.filled` (dashboard play) and `IconButton.filledTonal` (history, microphone, transfer, editor tools) were #B3B3B3 on #B69CFF, 1.1:1. (2) The colour scheme had no container roles, so Material copied the accent and its black label into them: selected chips drew black labels and icons on the translucent selected tint (1.6:1), and tonal buttons, segmented buttons and the navigation indicator looked like extra primary buttons. Added `accentContainer` #3A2E66 / `onAccentContainer` #E8DEFF (9.3:1) as primary/secondary containers, moved the icon button grey to `onSurfaceVariant`, gave controls a grey `borderStrong` outline instead of white, removed the lavender surface tint, and themed elevated (hover/press/disabled fills), filled/outlined (press wash), segmented, switch, checkbox, radio, FAB, tab bar, navigation bar and navigation rail explicitly. Selected chips now use the opaque container.
- Files:
  - `lib/core/theme/color_tokens.dart`, `lib/core/theme/app_theme.dart`.
  - `test/core/theme/control_contrast_test.dart` (new: colour roles, every elevated state, segments, selection controls, and rendered icon/label colours of filled, tonal, plain and selected buttons).
  - `test/core/theme/chip_theme_test.dart` (selected chips: opaque container, light lavender label and icon).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Contrast numbers computed with the WCAG formula in Python before writing the tests.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Unselected chip labels and plain icon buttons are now the secondary grey rather than white, so the selected state stands out more.
  - Not checked in a running app.
- Commit: `Give lavender buttons readable foregrounds`
