# [2026-11-27 11:30] Lift error text to AA

- Scope: The error red `#E22134` was used as a text colour in 31 places across 19 feature files, where it measured 4.0:1 on bgBase and 3.2:1 on bgSurface, below the 4.5:1 body text needs. New `AppColors.errorText` `#FF8585` (same hue) is 8.0:1 on bgBase, 6.3:1 on bgSurface, 4.6:1 on bgHighlight and above 4.5:1 inside the red-tinted banners. Every error message, the small icons beside them, destructive text buttons and `TextField` error text (`inputDecorationTheme.errorStyle`) now use it; fills, borders, tints, large status icons, badges and `colorScheme.error` keep `AppColors.error`. Decision D-032.
- Files:
  - `lib/core/theme/color_tokens.dart`, `lib/core/theme/app_theme.dart`.
  - 19 feature files under `lib/features/` (import, lyrics, player, transcription, transfer) whose error text, error icons or destructive buttons used the fill red.
  - `test/core/theme/error_text_contrast_test.dart` (new: AA on all four backgrounds and in the banner tints, AAA on base/elevated, hue family and distance from accent/success, theme error style, TextField error, PlaybackErrorBanner and AsrInstallErrorCard colours, source scan of `lib/features`).
  - `docs/decisions.md` (D-032).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The end-to-end smoke test card's `_Notice` tints its container with the colour it is given and keeps white text, so it still receives `AppColors.error` and is allow-listed in the source scan.
- Commit: `Lift error text to AA`
