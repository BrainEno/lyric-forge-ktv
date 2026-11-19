# [2026-11-19 11:05] Use radius and type tokens everywhere

- Scope: UI/UX audit S-05 (rest). The library grids, the store integrity banner and the two reference-alignment sheets were the last places outside the theme with literal corner radii or font sizes. They now use `AppSpacing.radius*` and the theme's `bodySmall`, and a source-hygiene test keeps new literals out.
- Files:
  - `lib/core/theme/spacing_tokens.dart` (new `radiusSheet` = 20 for bottom-sheet top corners).
  - `reference_alignment_result_comparison.dart`, `reference_alignment_review.dart` (sheet corners → `radiusSheet`; the three ambiguous-match choices use `bodySmall` in the secondary colour).
  - `local_artist_album_browser_screen.dart` (16 → `radiusXLarge`, 12 → `radiusLarge`, album song count → `bodySmall`), `local_library_explorer_screen.dart` (16 → `radiusXLarge`, song tile footnote → `bodySmall`), `local_store_integrity_banner.dart` (12 → `radiusLarge`).
  - Test: `test/architecture/source_hygiene_test.dart` (no `Radius.circular(<number>`, `BorderRadius.circular(<number>` or `fontSize: <number>` outside `lib/core/theme/`).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. The new rule's pattern was run over `lib/` with the test's comment rule and finds nothing.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Visible change: the song tile footnote in the library explorer grows from 11 px to 12 px (the grid artwork gives up about 1.5 px of height). Every other value keeps its size.
  - Computed radii (`size / 2`) and conditional font sizes are not literals and stay allowed.
- Commit: `Use radius and type tokens everywhere`
