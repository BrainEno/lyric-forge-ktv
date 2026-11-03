import '../../project/domain/repositories/project_repository.dart';
import '../domain/repositories/local_media_metadata_repository.dart';
import '../domain/services/audio_path_canonicalizer.dart';
import '../domain/services/audio_player_service.dart';
import '../domain/services/playback_lyrics_availability.dart';
import '../domain/services/playback_session_service.dart';

/// What the lyric-project player screen needs, decided outside of it.
///
/// Phase 4.2 migration: the screen used to read these three from
/// `AppServices.instance` in `initState`. The assembly layer
/// (`lib/app/playback_assembly.dart`) now builds this object, so the screen can
/// be handed a fake repository and a fake session without the process-wide
/// singleton — the same seam the lyric editor and the review inbox already use.
///
/// Deliberately *not* here: microphone, KTV recording and take history. Those
/// belonged to `_FullScreenKtvView`, a private widget that was replaced by
/// `ImmersiveKtvScreen` and left behind unreferenced; deleting it removed four
/// locator lookups and about a thousand lines of dead UI.
class PlayerScreenDependencies {
  final ProjectRepository projectRepository;
  final AudioPlayerService audioPlayer;
  final PlaybackSessionService playbackSession;

  /// Only used when opening the fullscreen KTV view from this screen.
  final LocalMediaMetadataRepository metadataRepository;
  final AudioPathCanonicalizer pathCanonicalizer;

  const PlayerScreenDependencies({
    required this.projectRepository,
    required this.audioPlayer,
    required this.playbackSession,
    required this.metadataRepository,
    required this.pathCanonicalizer,
  });
}

/// What the app-scoped Now Playing screen needs.
///
/// Three things travel together: the session drives the transport, the audio
/// player answers "where are we", and the lyrics resolver answers "is there a
/// lyric project behind this song" (which also repairs the queue's cached
/// `hasLyrics` flag). The resolver bundles four services into one field; see
/// [PlaybackLyricsResolver].
class NowPlayingDependencies {
  final PlaybackSessionService playbackSession;
  final AudioPlayerService audioPlayer;
  final PlaybackLyricsResolver lyricsResolver;

  const NowPlayingDependencies({
    required this.playbackSession,
    required this.audioPlayer,
    required this.lyricsResolver,
  });
}
