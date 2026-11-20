# [2026-12-04 09:30] Share one catalog card and cover

- Scope: L-04 and T-03 from the page reports. Four music catalogs each drew their own grid card: the local library's artist/album cards, song cards and playlist cards, and the phone's artist/album cards for the desktop library. They used two corner radii, three paddings, two title weights, three grid ratios, a fixed-height grid for playlists, and two ways of showing an unavailable item. All of them painted an opaque box over the `InkWell`, so a tap left no ripple. The covers inside went through three private wrappers (`_Artwork`, `_CatalogArtwork`, `_CollectionArtwork`) that only picked a radius and an icon. The phone's `RemoteMediaArtwork` had its own placeholder, with a fixed icon size and a different colour. A shared `AppCatalogCard` (`lib/core/widgets/app_catalog_card.dart`, D-038) now draws every one of those cards:
  - the surface is the `Material`, so the ripple shows;
  - the cover is the largest centred square;
  - the border turns red only for an item that cannot be opened;
  - it brings the column, ratio and spacing rules (`gridDelegateFor`);
  - it reads as one button through `AppTapTarget`.

  `AppArtwork` gains `tileRadius` and `rowRadius`, `AppArtwork.person` (round, centred in a wide cell) and `AppArtwork.missing` (broken link in the error colour), plus a public `AppArtworkPlaceholder`. The three wrappers are gone.

  `RemoteMediaArtwork` draws a local copy through `AppArtwork` and its placeholder through `AppArtworkPlaceholder`. Artists on the phone are round, as they are locally. The fetch itself is unchanged: bytes over the pinned channel, with the token in a header.

  The phone's track row worked out its download state from five booleans, and its icon, progress bar and notice each re-read them in their own order. It now asks a single `RemoteTrackDownload`. As a result, a song already on the phone no longer shows an old 下载失败 next to its ✓.
- Files:
  - New: `lib/core/widgets/app_catalog_card.dart`, `lib/features/transfer/presentation/widgets/remote_track_download.dart`.
  - `lib/core/widgets/app_artwork.dart`; `lib/features/transfer/presentation/widgets/remote_media_artwork.dart`.
  - `lib/features/player/presentation/screens/local_library_explorer_screen.dart`, `local_artist_album_browser_screen.dart`, `local_collections_screen.dart`.
  - `lib/features/transfer/presentation/screens/mobile_remote_grouped_library_screen.dart`, `mobile_remote_music_library_screen.dart`.
  - New tests: `test/core/widgets/app_catalog_card_test.dart`, `test/features/transfer/presentation/widgets/remote_media_artwork_test.dart`, `remote_track_download_test.dart`, `test/architecture/catalog_card_contract_test.dart`; additions to `test/core/widgets/app_artwork_test.dart`.
  - `docs/decisions.md` (D-038), `artifacts/ui-audit/reports/issues.md` (status section for round 17, with the page-report items).
- Validation:
  - Widget tests for the card:
    - style helpers and grid rules (2 to 7 columns, ratio, spacing);
    - square centred cover, including on a short card;
    - padding, the ripple on the `Material`, the red border and red subtitle;
    - title-row and cover-corner controls;
    - taps, disabled state, one semantics node, custom actions.
  - Widget tests for the cover roles:
    - person circle, including in a wide cell;
    - missing song, with and without a cover on disk;
    - the radii, and the placeholder matching `AppArtwork`.
  - Widget tests for the remote cover:
    - placeholder, no fetch without artwork;
    - radii, filling its cell;
    - spinner, memory image, failed and empty fetch;
    - local copy without a fetch, round artists.
  - Unit tests for every `RemoteTrackDownload` state, progress, icon, notice and label.
  - A source contract keeps the four grids on the shared card and delegate, keeps private artwork wrappers out of the five library screens, and keeps the remote cover's fetch off URLs.
  - Format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - Not looked at in a running app.
  - Visible changes:
    - playlists now use the same grid as albums (two columns at least, square covers) instead of fixed 190–220 px tiles;
    - the explorer's song cards get the album cards' padding;
    - the phone's artist and album cards get the local spacing (`md` instead of `sm`);
    - a playlist without a cover shows a playlist icon instead of a note;
    - card subtitles use `textSecondary`;
    - a failed download's notice uses `errorText`, which is readable on the dark surface.
  - The media hub security contract still finds `Image.memory(` and the `fetchArtwork` call in `remote_media_artwork.dart`, and no `Image.network(`.
- Commit: `Share one catalog card and cover across the music libraries`
