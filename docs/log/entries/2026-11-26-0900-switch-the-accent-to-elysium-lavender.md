# [2026-11-26 09:00] Switch the accent to Elysium Lavender

- Scope: UI/UX audit A-01, which the user approved in this round: change the accent, keep it apart from the error colour, and make it look good (any hue). The accent was Spotify green `#1DB954`, the same value as `success`, so "selected", "primary action" and "done" looked alike, and nothing tied the interface to the red, black and paper-white app icon. The accent is now lavender `#B69CFF` (hover `#C7B3FF`, pressed `#9F84F0`, 16 % tint `accentMuted`). It is at least 40° of hue away from error, warning, success, info and the brand red. Black labels on it reach 9.2:1, and it reaches 6.4:1 or more as text on every surface. Two places used the accent to mean "done" and now use `AppColors.success`: the 就绪 project status dot (dashboard shelves, project detail) and the inserted text in the reference-lyric comparison views.
- Files:
  - `lib/core/theme/color_tokens.dart` (accent family and comments).
  - `lib/features/home/presentation/widgets/dashboard_shelves.dart`, `lib/features/project/presentation/screens/project_detail_screen.dart` (ready → success).
  - `lib/features/lyrics/presentation/widgets/reference_alignment_result_comparison.dart`, `lib/features/lyrics/presentation/widgets/reference_alignment_review.dart` (insertions → success).
  - `test/core/theme/accent_palette_test.dart` (new: hue distance from every status colour and the brand red, AAA labels on accent fills, AA accent text on every surface, white on the muted tint, hover/pressed ordering, theme wiring).
  - `docs/decisions.md` (D-031).
- Validation:
  - Contrast (WCAG relative luminance, computed): black on accent 9.19, on hover 10.6, on pressed 7.03; accent on `bgBase` 8.20, `bgElevated` 7.77, `bgSurface` 6.45; white on the muted tint over `bgElevated` 13.35.
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Decision: lavender rather than a light red or black. A light red is too close to `#E22134`, so red buttons would read as destructive. Black has no contrast on the dark theme. Lavender suits the name Elysium and does not clash with the icon's red, which stays on the brand mark only.
  - Running work (queue, downloads, install progress) keeps the accent: it means "in progress", not "done".
  - Not checked in a running app.
- Commit: `Switch the accent to Elysium Lavender`
