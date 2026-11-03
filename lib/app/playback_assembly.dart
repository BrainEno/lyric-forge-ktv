import '../features/player/domain/services/playback_lyrics_availability.dart';
import '../features/player/presentation/playback_screen_dependencies.dart';
import 'app_services.dart';

/// Builds the lyric resolver every playback surface shares.
///
/// The four collaborators (project repository, media metadata repository,
/// playback session, path canonicalizer) always travel together — resolution
/// writes the corrected `hasLyrics` flag back through the session — so the
/// assembly layer binds them once instead of each widget reaching for four
/// services of its own.
PlaybackLyricsResolver buildPlaybackLyricsResolver(AppServices services) {
  return PlaybackLyricsResolver(
    projectRepository: services.projectRepository,
    metadataRepository: services.localMediaMetadataRepository,
    playbackSession: services.playbackSessionService,
    pathCanonicalizer: services.audioPathCanonicalizer,
  );
}

/// What `/project/:id/player` is made of.
PlayerScreenDependencies assemblePlayerScreenDependencies(
  AppServices services,
) {
  return PlayerScreenDependencies(
    projectRepository: services.projectRepository,
    audioPlayer: services.audioPlayerService,
    playbackSession: services.playbackSessionService,
    metadataRepository: services.localMediaMetadataRepository,
    pathCanonicalizer: services.audioPathCanonicalizer,
  );
}

/// What `/now-playing` (and `/quick-play`'s remote fallback) is made of.
NowPlayingDependencies assembleNowPlayingDependencies(AppServices services) {
  return NowPlayingDependencies(
    playbackSession: services.playbackSessionService,
    audioPlayer: services.audioPlayerService,
    lyricsResolver: buildPlaybackLyricsResolver(services),
  );
}
