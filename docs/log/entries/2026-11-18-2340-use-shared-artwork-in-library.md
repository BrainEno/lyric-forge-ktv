# [2026-11-18 23:40] Use the shared artwork widget on library screens

- Scope: UI/UX audit C-04, second half. The dashboard, library explorer, artist/album browser, collections and quick play each built their own cover placeholder: a gradient or a flat surface, album or music-note icons at fixed or proportional sizes (24, 50, 54 or 96 px), and radii of 8, 12 or `radiusLarge`. Their private wrappers keep their names and call sites but now delegate to `AppArtwork`, so every cover in the app shares the placeholder surface, icon colour and 42 % icon scale, and falls back cleanly on decode errors.
- Files:
  - `lib/core/widgets/app_artwork.dart`: optional `placeholderColor` for placeholders that carry meaning (default `textTertiary`).
  - `dashboard_screen.dart` (`_Artwork`, `radiusMedium`; the `dart:io` and `foundation` imports are no longer needed), `local_library_explorer_screen.dart` (`_Artwork`: songs with a missing file keep the red link-off placeholder through `placeholderColor`), `local_artist_album_browser_screen.dart` (`_CatalogArtwork`: round person placeholder for artists), `local_collections_screen.dart` (`_CollectionArtwork`: playlists keep the music-note icon, song rows use the album icon), `quick_play_screen.dart` (`_Artwork` keeps the square ratio and the loading spinner; the box shadow was clipped by its own `ClipRRect` and never visible, so it is dropped).
  - Test: `test/core/widgets/app_artwork_test.dart` (status colour).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Lines were measured so that formatter joins and splits are already applied, and the removed imports were checked against remaining uses (`kIsWeb` was the only `foundation` symbol in the dashboard).
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Visible changes: the dashboard placeholder is the flat surface instead of the card gradient. The explorer's placeholder icon scales with the tile instead of a fixed 50 px, which overflowed the 48 px list thumbnail. The explorer grid image now fills the tile width the way its placeholder already did.
  - With this change no private cover widget is left outside the transfer domain. `RemoteMediaArtwork` stays separate because it fetches covers through the authenticated Media Hub client.
- Commit: `Use the shared artwork widget on library screens`
