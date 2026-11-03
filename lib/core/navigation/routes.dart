/// Route names and path helpers.
///
/// Kept in `core/navigation` because screens push these names directly; the
/// table that turns them into widgets is assembly and lives in
/// `lib/app/app_router.dart` (Phase 4.2).
abstract class Routes {
  static const String home = '/';
  static const String dashboard = '/dashboard';
  static const String import = '/import';
  static const String library = '/library';
  static const String libraryArtists = '/library/artists';
  static const String libraryAlbums = '/library/albums';
  static const String collections = '/collections';
  static const String playlists = '/playlists';
  static const String quickPlay = '/quick-play';
  static const String nowPlaying = '/now-playing';
  static const String projectDetail = '/project/:id';
  static const String lyricEditor = '/project/:id/lyrics';
  static const String player = '/project/:id/player';
  static const String review = '/review';
  static const String settings = '/settings';
  static const String mediaSharing = '/media-sharing';
  static const String remoteLibrary = '/remote-library';
  static const String remoteBrowse = '/remote-library/browse';
  static const String mediaHubScanner = '/media-hub-scanner';

  static String projectDetailPath(String id) => '/project/$id';
  static String lyricEditorPath(String id) => '/project/$id/lyrics';
  static String playerPath(String id) => '/project/$id/player';
}
