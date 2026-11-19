# [2026-11-19 11:35] Move library empty states to AppEmptyState

- Scope: UI/UX audit C-05 follow-up. Four player screens still drew their own empty states with different icon sizes (52 to 72 px, or an untinted 64 px icon), title styles and spacing. `AppEmptyState` gains a `hero` density for first-run invitations (icon tile 92/112/156 px by layout, headline title, card frame, scrolls on short screens) and optional `status` and `footer` slots; quick play and the empty song library use the hero density, artist/album and favourites/playlists use the page density.
- Files:
  - `lib/core/widgets/app_empty_state.dart` (hero density, `status`, `footer`, `heroIconExtentFor`).
  - `lib/features/player/presentation/screens/quick_play_screen.dart` (`_EmptyPlayer`: error line and spinner go in `status`, the 歌词制作 link in `footer`).
  - `lib/features/player/presentation/screens/local_library_explorer_screen.dart` (`_EmptyLibrary`).
  - `lib/features/player/presentation/screens/local_artist_album_browser_screen.dart` (`_CatalogEmpty`: icon now tertiary like every other empty state).
  - `lib/features/player/presentation/screens/local_collections_screen.dart` (`_CollectionEmptyState`).
  - Test: `test/core/widgets/app_empty_state_test.dart` (hero tile, headline and footer order; short-screen scroll without overflow; status position).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Copy, actions, button minimum sizes and disabled-while-loading behaviour are unchanged; no existing test refers to these widgets.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The song library empty state was a plain column (no card); it now matches quick play, which shows the same invitation in the player.
  - Lyric pane, queue and dashboard empty states remain for a later round.
- Commit: `Move library empty states to AppEmptyState`
