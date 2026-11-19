# [2026-11-25 11:00] Route the last bare covers through AppArtwork

- Scope: UI/UX audit C-04. Earlier rounds moved most of the twelve cover widgets onto `AppArtwork`; four still built a bare `Image.file` with their own placeholder: the project player cover (three sizes), the project detail cover, the cover preview in the song info dialog and the download list on the phone. A cover file that exists but cannot be decoded painted Flutter's broken image there, and each placeholder had its own background (player gradient, surface) and icon colour. All four now use `AppArtwork`, so they fall back to the shared placeholder; the project player keeps its accent icon while a song loads through `placeholderColor`. The remote library cover keeps its own widget (it fetches bytes over the pinned channel) but its local branch gains the `errorBuilder` its network branch already had.
- Files:
  - `lib/features/player/presentation/screens/player_screen.dart` (`_ProjectArtwork` → `AppArtwork`, `dart:io` import gone).
  - `lib/features/project/presentation/screens/project_detail_screen.dart` (`_ProjectArtwork` → `AppArtwork`, `dart:io` import gone).
  - `lib/features/player/presentation/widgets/local_media_metadata_dialog.dart` (`_ArtworkPreview` → `AppArtwork`).
  - `lib/features/transfer/presentation/screens/mobile_download_manager_screen.dart` (row leading → `AppArtwork` with the music note placeholder).
  - `lib/features/transfer/presentation/widgets/remote_media_artwork.dart` (local cover `errorBuilder`).
  - Tests: `test/architecture/artwork_convergence_test.dart` (new: only `AppArtwork` and the remote cover build images, every image outside `AppArtwork` has an `errorBuilder`, the four screens use `AppArtwork`, the scanner reads whole calls); `test/core/widgets/app_artwork_test.dart` (undecodable cover file shows the placeholder without an exception).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Visible change: the project player and project detail placeholders lose the player gradient behind the album icon and use the shared surface colour, matching the library, dashboard and now playing covers.
- Commit: `Route the last bare covers through AppArtwork`
