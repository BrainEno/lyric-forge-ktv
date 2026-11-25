# [2026-11-18 23:05] Split the local library explorer screen

- Scope: round 57, split the local music library explorer before it crosses the screen-size budget (D-077).
  - `local_library_explorer_screen.dart`: 1124 → 618 lines; retains repositories, loading/rescan and repair flows, song actions, filter/sort state and page composition.
  - `presentation/local_library_explorer_song.dart`: the explorer row model, metadata/lyrics labels, browse projection and playback-item mapping.
  - `widgets/local_library_explorer_views.dart`: grid/list, card/menu, screen-reader actions and empty/no-result states.
  - `test/architecture/catalog_card_contract_test.dart`: follow the extracted catalog card, grid delegate and cover radii.
  - `test/features/player/presentation/local_library_explorer_song_test.dart`: user metadata, missing references and playable queue-item mapping.
- Files:
  - New: the presentation song model, explorer views, their tests and this entry.
  - Changed: `local_library_explorer_screen.dart`, `catalog_card_contract_test.dart`, `docs/decisions.md`, `docs/handoff.md`, `docs/work_log.md`, `docs/work_log_archive.md`.
- Validation:
  - `git diff --check` => passed.
  - Local Flutter/Dart SDK is unavailable; formatting, analysis and tests are pending PR CI.
- Notes: UI behavior and text are intended to remain unchanged. The prior D-075–D-076 PR #521 is merged; this round starts from its merge commit.
- Commit: `Split local library explorer screen`
