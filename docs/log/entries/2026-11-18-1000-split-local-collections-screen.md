# [2026-11-18 10:00] Split the local collections screen

- Scope: round 55, split `local_collections_screen.dart` and retire its temporary line-budget exception (D-075).
  - `local_collections_screen.dart`: 1248 → 590 lines; it keeps collection loading, mutations and the page layout.
  - `widgets/local_collection_song.dart`: the collection-row view model and its playback-item mapping.
  - `widgets/local_collection_song_tile.dart`: the shared current-playback-aware song row.
  - `widgets/local_collection_widgets.dart`: favorite/playlist action menus, collection hero, playlist detail header/card and empty state.
  - `test/architecture/screen_size_budget_test.dart`: remove the frozen over-budget exception; every screen is now checked against the 1200-line limit.
  - `test/architecture/catalog_card_contract_test.dart`: follow the playlist card and catalog grid after extraction.
- Files:
  - New: the three collection widget/model files above and this entry.
  - Changed: `local_collections_screen.dart`, `screen_size_budget_test.dart`, `catalog_card_contract_test.dart`, `docs/decisions.md`, `docs/handoff.md`, `docs/work_log.md`, `docs/work_log_archive.md`.
- Validation:
  - `git diff --check` => passed.
  - PR #521 final head `ad000e0`: Flutter format check, work-log preflight, repository quality gate and KTV history/recovery workflow => passed.
  - The first CI pass caught the moved screen's shared grid import and a catalog contract still targeting the old card location; both were corrected and the final head passed.
  - Screen is 590 physical lines; all screens are checked by the updated architecture test.
- Notes: UI text, order, callbacks and playback behavior were moved without intended changes. Local Flutter/Dart SDK is unavailable, so validation used GitHub Actions.
- Commit: `Split local collections screen`
