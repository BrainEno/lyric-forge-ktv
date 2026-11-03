import '../../project/domain/repositories/project_repository.dart';
import '../domain/repositories/local_media_collection_repository.dart';
import '../domain/repositories/local_media_metadata_repository.dart';
import '../domain/services/audio_path_canonicalizer.dart';
import '../domain/services/audio_player_service.dart';
import '../domain/services/audio_preview_service.dart';
import '../domain/services/ktv_microphone_service.dart';
import '../domain/services/ktv_recording_service.dart';
import '../domain/services/ktv_take_history_store.dart';
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
/// The fullscreen KTV surface travels as one bundle ([immersiveKtv]) instead of
/// as two loose repositories: everything it needs from playback is decided in
/// the same place as the rest of this object.
class PlayerScreenDependencies {
  final ProjectRepository projectRepository;
  final AudioPlayerService audioPlayer;
  final PlaybackSessionService playbackSession;

  /// Only used when opening the fullscreen KTV view from this screen.
  final ImmersiveKtvDependencies immersiveKtv;

  const PlayerScreenDependencies({
    required this.projectRepository,
    required this.audioPlayer,
    required this.playbackSession,
    required this.immersiveKtv,
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

  /// Only used by the queue panel's "save queue as playlist".
  final LocalMediaCollectionRepository localCollectionRepository;

  /// Only used when opening the fullscreen KTV view from Now Playing.
  final ImmersiveKtvDependencies immersiveKtv;

  const NowPlayingDependencies({
    required this.playbackSession,
    required this.audioPlayer,
    required this.lyricsResolver,
    required this.localCollectionRepository,
    required this.immersiveKtv,
  });
}

/// Everything the one fullscreen KTV surface is made of.
///
/// The five playback collaborators plus the four KTV services. They used to be
/// split: `ImmersiveKtvScreen` took the playback five while the unreachable
/// `_FullScreenKtvView` kept microphone, recording and take history to itself,
/// which is how the recording UI lost every entry point when that view was
/// deleted. One bundle means one place to see — and one place to test — that a
/// screen gets the whole studio or none of it.
class ImmersiveKtvDependencies {
  final ProjectRepository projectRepository;
  final LocalMediaMetadataRepository metadataRepository;
  final AudioPlayerService audioPlayer;
  final PlaybackSessionService playbackSession;
  final AudioPathCanonicalizer pathCanonicalizer;
  final KtvMicrophoneService microphoneService;
  final KtvRecordingService recordingService;
  final KtvTakeHistoryStore takeHistoryStore;

  /// Independent preview channel for auditing a take; never the queue player.
  final AudioPreviewService previewService;

  const ImmersiveKtvDependencies({
    required this.projectRepository,
    required this.metadataRepository,
    required this.audioPlayer,
    required this.playbackSession,
    required this.pathCanonicalizer,
    required this.microphoneService,
    required this.recordingService,
    required this.takeHistoryStore,
    required this.previewService,
  });
}
