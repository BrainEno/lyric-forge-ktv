import '../../lyrics/domain/services/lyric_file_import_service.dart';
import '../domain/repositories/local_media_collection_repository.dart';
import '../domain/repositories/local_media_library_repository.dart';
import '../domain/repositories/local_media_metadata_repository.dart';
import '../domain/repositories/play_history_repository.dart';
import '../domain/services/audio_library_import_service.dart';
import '../domain/services/audio_player_service.dart';
import '../domain/services/local_media_relink_service.dart';
import '../domain/services/playback_lyrics_availability.dart';
import '../domain/services/playback_session_service.dart';

/// What "import a lyric file for this local song" is made of.
///
/// Two things only: the resolver that decides whether the song already has a
/// lyric project (and repairs the queue flag while it is there), and the file
/// importer. The resolver already bundles the project repository, the media
/// metadata repository, the playback session and the path canonicalizer — the
/// exact quartet the import writes back through — so this object does not
/// repeat them.
class LyricsImportDependencies {
  final PlaybackLyricsResolver lyricsResolver;
  final LyricFileImportService importer;

  const LyricsImportDependencies({
    required this.lyricsResolver,
    required this.importer,
  });
}

/// What the local-music library surfaces are made of.
///
/// One bundle for the whole area — the five library sections (songs, artists,
/// albums, favourites, playlists), the two player bars and quick play. They used
/// to each reach for `AppServices.instance` in `initState`, which is why none of
/// them could be built in a test without the real on-disk library, the real
/// audio engine and the real session.
///
/// Split by use rather than by screen on purpose: a section needs the library,
/// the metadata overrides and the session; quick play needs the importer and the
/// audio player; the bars need the collection repository. Passing one object the
/// assembly layer owns keeps a screen from growing three optional fields with
/// three locator fallbacks, and keeps the number of dependency classes from
/// tracking the number of screens.
class LocalLibraryDependencies {
  final LocalMediaLibraryRepository libraryRepository;
  final LocalMediaCollectionRepository collectionRepository;
  final LocalMediaMetadataRepository metadataRepository;
  final PlayHistoryRepository playHistoryRepository;
  final LocalMediaRelinkService relinkService;
  final AudioLibraryImportService libraryImportService;
  final PlaybackSessionService playbackSession;
  final AudioPlayerService audioPlayer;
  final LyricsImportDependencies lyricsImport;

  const LocalLibraryDependencies({
    required this.libraryRepository,
    required this.collectionRepository,
    required this.metadataRepository,
    required this.playHistoryRepository,
    required this.relinkService,
    required this.libraryImportService,
    required this.playbackSession,
    required this.audioPlayer,
    required this.lyricsImport,
  });
}
