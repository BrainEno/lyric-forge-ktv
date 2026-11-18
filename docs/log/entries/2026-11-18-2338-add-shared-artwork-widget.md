# [2026-11-18 23:38] Add a shared artwork widget for player surfaces

- Scope: UI/UX audit C-04 (roadmap phase 2), first half. Each player surface had its own private cover widget with different placeholder icons (album vs music note), icon colours, icon sizes (18, 24 and 92 px), and different rules for remote covers. Only the desktop bar limited remote covers to Media Hub streams, and the mobile bar did no scheme check and ignored the audio thumbnail. They now share `AppArtwork` (`lib/core/widgets/`): local file, then http(s) cover, then one placeholder (surface colour, `textTertiary` icon at 42 % of the edge, album icon for local songs and cloud icon for streams). Decode failures of local files also fall back to the placeholder.
- Files:
  - New: `lib/core/widgets/app_artwork.dart` (`AppArtwork` with fixed `size` or fill-parent mode, plus `existingFile` and `networkUri` helpers), and `lib/features/player/presentation/widgets/playback_artwork.dart` (`PlaybackArtwork`: item cover, then audio thumbnail; a remote cover only for `isRemoteStream`, the same rule as `LibraryMetadataPlaybackSessionService` and the system media handler).
  - Migrated (private widgets removed): `global_player_bar.dart` (`_Artwork`), `mobile_global_player_bar.dart` (`_MobileArtwork` and its inline URI parsing), `playback_queue_panel.dart` (`_QueueArtwork`), `now_playing_screen.dart` (`_PlaybackArtwork` keeps its `RepaintBoundary` and large radius; `_remoteArtworkUri` removed). `dart:io` is no longer imported by these four files.
  - Tests: `test/core/widgets/app_artwork_test.dart`, `test/features/player/presentation/widgets/playback_artwork_test.dart`.
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Lines were measured so that formatter joins and splits are already applied.
  - The security contract on `remote_media_artwork.dart` (authenticated Media Hub fetch, no `Image.network`) is untouched; that widget stays separate. The assembly contracts on the four player files only forbid `AppServices` and still hold.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart` (regenerates `main` with zero diff).
- Notes:
  - Visible changes: the placeholder icon is slightly smaller in the bars (20 px instead of 24) and the queue (16 instead of 18), and larger on Now Playing (scales with the cover instead of a fixed 92 px). It is also a step dimmer (`textTertiary`), and local songs show an album icon instead of a music note. Now Playing no longer shows the player gradient behind a loading cover.
  - Local items that still carry a `remoteArtworkUri` no longer load it in the queue and on Now Playing. The resolver strips that key when an item becomes local, so this only affects inconsistent data.
  - The library screens (dashboard, explorer, artist/album, collections, quick play) are the second half of C-04.
- Commit: `Add a shared artwork widget for player surfaces`
