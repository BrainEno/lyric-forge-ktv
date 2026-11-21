# [2026-12-16 09:30] One Chinese typeface per label

- Scope: round 29. The user's screenshot of the navigation rail on Windows showed labels mixing two typefaces: in "音乐库" the 音 was bold and dark while 乐库 were thin and grey, likewise 校 against 对 in "校对". The app named no font, so every Chinese character went to the system fallback on its own; on a zh-TW (or Japanese) Windows that fallback finds 音, 校, 工, 程 in Microsoft JhengHei / Yu Gothic but the Simplified-only 乐, 库, 对 only in Microsoft YaHei. Changes (D-050):
  - New `AppTypography`: the platform's UI font from Flutter's typography for Latin (Segoe UI on Windows) and a Simplified Chinese fallback list before the system fallback (Windows: Microsoft YaHei UI, Microsoft YaHei, DengXian, SimHei; Apple: PingFang SC, Hiragino Sans GB, Heiti SC; Android/Linux: Noto Sans CJK SC, Noto Sans SC, Source Han Sans SC, WenQuanYi Micro Hei), followed by the platform typography's own fallback.
  - `AppTheme.themeFor` applies it to the text theme, the primary text theme and every component style that does not merge with the text theme: navigation labels, app bar title, button text, input hint and error, tooltip, snack bar.
- Files:
  - New: `lib/core/theme/app_typography.dart`, `test/core/theme/app_typography_test.dart`.
  - `lib/core/theme/app_theme.dart`.
  - `docs/decisions.md` (D-050), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - Fonts that are not installed are skipped by the engine; a Windows without Microsoft YaHei (very rare) still falls back to the system choice.
- Commit: `Draw each Chinese label in one typeface`
