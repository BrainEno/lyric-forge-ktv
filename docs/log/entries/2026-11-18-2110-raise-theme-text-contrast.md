# [2026-11-18 21:10] Raise theme text contrast and drop the unbundled Inter declaration

- Scope: UI/UX audit A-01 (P1), A-03 (P2) and S-01 (P1). Filled/elevated buttons, selected chips, switches and other accent fills drew white text on #1DB954 (2.6:1, below WCAG AA 4.5:1). Every SnackBar without its own colour was green, including failure messages, with white text at the same 2.6:1. The tertiary text grey #6A6A6A, used for many 12px captions and hints, was 3.5:1 on the page background. The text theme named `Inter`, but no font is bundled, so the result depended on whether the user had Inter installed.
  - Accent fills now use a new `AppColors.onAccent` (black, 8.1:1) through `onPrimary`/`onSecondary` and the elevated-button theme.
  - The SnackBar theme uses the neutral `bgHighlight` with white text (10.7:1); actions use `accentHover` (5.6:1) and are set explicitly because `inversePrimary` would otherwise follow the new black `onPrimary`. Call sites that pass `AppColors.error` or `bgSurface` keep their colours and the white text.
  - `textTertiary` becomes #8F8F8F: 5.8:1 on bgBase, 5.5:1 on bgElevated, 4.6:1 on bgSurface (was 3.5, 3.3 and 2.7:1). `textDisabled` is unchanged.
  - The text theme no longer names a font family, so every platform uses its default UI font until a bundled typeface is chosen with the brand work.
- Files: `lib/core/theme/color_tokens.dart`, `lib/core/theme/app_theme.dart`, this entry, generated work-log files.
- Validation:
  - Contrast ratios computed with the WCAG 2.x relative-luminance formula (values above).
  - No test asserts theme colours or the font family (`rg "AppColors\.|'Inter'|onPrimary" test` => no matches).
  - The sandbox has no Dart/Flutter toolchain. `dart format` ran on GitHub Actions through a temporary branch-only probe workflow (removed before review); its output, including pre-existing tall-style churn in both theme files (hint style, gradient lists), is applied. `flutter analyze` and the full test suite run in the PR's Flutter Quality Gate.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`, 0 errors.
- Notes:
  - Visual change, not verified on a running app: green primary buttons, selected ChoiceChips/navigation indicators and switch thumbs now show black content; SnackBars turn dark grey instead of green. Manual check on desktop and mobile: a FilledButton, the Library section chips, a Switch in settings, a success and an error SnackBar.
  - Hard-coded `AppColors.pureWhite` on non-accent surfaces (spinners in disabled buttons, error buttons, the white play button) is unchanged and passes.
  - Choosing and bundling a typeface (with a CJK fallback chain) is left to the brand/design-system phase.
- Commit: `Raise theme text contrast and drop unbundled Inter font`
