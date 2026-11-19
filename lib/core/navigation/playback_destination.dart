import 'routes.dart';

/// Where "open the player" leads for the current playback session.
///
/// `/quick-play` used to decide this inside the router: depending on what was
/// playing, the same route name showed the local player, the full-screen now
/// playing view or the music library (audit N-01). Callers could not tell which
/// screen they would get, and because the route name stayed `/quick-play`, the
/// app shell treated a remote stream's now playing view as an ordinary page
/// and kept the mini player bar on top of it. Callers now resolve the
/// destination first and push its own route; the router uses the same rules
/// for a bare `/quick-play`, so a deep link lands where a tap would.
enum PlaybackDestination {
  /// A song that belongs to a lyric project: that project's player.
  projectPlayer,

  /// A stream from the desktop Media Hub: the source-agnostic now playing
  /// view, which knows how to show remote metadata and artwork.
  nowPlaying,

  /// A local song, or a play-history entry being resumed: the local player.
  localPlayer,

  /// Nothing is playing: the music library, to pick something.
  library;

  /// Resolves the destination for the session's current song.
  ///
  /// [resumingHistory] wins over everything else: resuming a history entry
  /// always opens the local player with that entry. Otherwise a project song
  /// opens its project player, a remote stream the now playing view, any other
  /// song the local player, and no song the library.
  static PlaybackDestination resolve({
    required bool hasCurrent,
    String? projectId,
    bool isRemoteStream = false,
    bool resumingHistory = false,
  }) {
    if (resumingHistory) return PlaybackDestination.localPlayer;
    if (!hasCurrent) return PlaybackDestination.library;
    if (projectId != null) return PlaybackDestination.projectPlayer;
    if (isRemoteStream) return PlaybackDestination.nowPlaying;
    return PlaybackDestination.localPlayer;
  }

  /// The route to push for this destination.
  ///
  /// [projectId] is required for [projectPlayer]; without it the project
  /// player falls back to the local player route, which hands a project song
  /// over to its project once it knows the id.
  String routeName({String? projectId}) {
    switch (this) {
      case PlaybackDestination.projectPlayer:
        final id = projectId;
        return id == null ? Routes.quickPlay : Routes.playerPath(id);
      case PlaybackDestination.nowPlaying:
        return Routes.nowPlaying;
      case PlaybackDestination.localPlayer:
        return Routes.quickPlay;
      case PlaybackDestination.library:
        return Routes.library;
    }
  }
}
