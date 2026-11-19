# [2026-11-19 10:55] Use design tokens in lyric editor surfaces

- Scope: UI/UX audit S-05 (lyric editor part) and E-03. Seven lyric editor surfaces still used literal corner radii (6, 8, 12) or a literal font size; they now use `AppSpacing.radiusMedium` / `radiusLarge` and the theme's `labelSmall`. The toolbar's "待复核 N" count turns warning amber instead of the accent green, which reads as "done" everywhere else.
- Files:
  - `lyric_export_dialog.dart`, `lyric_tap_sync_dialog.dart`, `lyric_word_tap_dialog.dart`, `lyric_proofread_v2_dialog.dart` (8 → `radiusMedium`; the diagnostics margin uses `AppSpacing.sm`).
  - `lyric_tap_controls.dart` (12 → `radiusLarge`), `lyric_word_timing_strip.dart` (6 → `radiusMedium`).
  - `lyric_list_pane.dart` ("按回车保存 · Esc 取消" uses `labelSmall` as is; the theme already sets 10 px and the tertiary colour).
  - `lyric_editor_toolbar.dart` (`_StatusLine` review count colour).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. No test looks up these colours or radii.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Visible changes: the word-timing chips round 8 px instead of 6 px; the review count is amber (contrast about 9:1 on the editor background) when there is something to review.
  - The library screens and the reference-alignment sheets follow in a separate change with a source-hygiene ratchet.
- Commit: `Use design tokens in lyric editor surfaces`
