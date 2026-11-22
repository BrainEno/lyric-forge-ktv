import '../../lyrics/domain/online/song_lyrics_lookup.dart';
import '../../lyrics/domain/online/song_tags.dart';
import '../../lyrics/domain/services/lyric_file_import_service.dart';
import '../domain/repositories/local_media_collection_repository.dart';
import '../domain/repositories/local_media_library_repository.dart';
import '../domain/repositories/local_media_metadata_repository.dart';
import '../domain/repositories/play_history_repository.dart';
import '../domain/services/audio_library_import_service.dart';
import '../domain/services/audio_player_service.dart';
import '../domain/services/library_lyrics_auto_linker.dart';
import '../domain/services/local_media_relink_service.dart';
import '../domain/services/playback_lyrics_availability.dart';
import '../domain/services/playback_session_service.dart';

/// What "add lyrics to this local song" is made of.
///
/// Two required things: the resolver that decides whether the song already
/// has a lyric project (and repairs the queue flag while it is there), and the
/// file importer; the online lookup and the player for its timing preview are
/// optional (D-054). The resolver already bundles the project repository, the media
/// metadata repository, the playback session and the path canonicalizer — the
/// exact quartet the import writes back through — so this object does not
/// repeat them.
class LyricsImportDependencies {
  final PlaybackLyricsResolver lyricsResolver;
  final LyricFileImportService importer;

  /// Searches the lyric sites for 联网获取歌词 (D-054); null hides the option.
  final SongLyricsLookup? songLyricsLookup;

  /// Lets the timing preview follow and seek the song; null shows the
  /// fetched lyrics without the listen-and-check controls.
  final AudioPlayerService? audioPlayer;

  /// Reads the song file's tags for a second search when its name finds
  /// nothing (D-055); null searches by the name only.
  final SongTagReader? songTagReader;

  const LyricsImportDependencies({
    required this.lyricsResolver,
    required this.importer,
    this.songLyricsLookup,
    this.audioPlayer,
    this.songTagReader,
  });
}

/// What the local-music library surfaces are made of.
///
/// One bundle for the whole area — the five library sections (songs, artists,
/// albums, favourites, playlists), the two player bars and quick play. They used
/// to each reach for the app-wide singleton in `initState`, which is why none of
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

  /// Pairs lyric files in the library folder with songs when the library
  /// opens or rescans (decision D-033). Null in tests that do not need it.
  final LibraryLyricsAutoLinker? lyricsAutoLinker;

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
    this.lyricsAutoLinker,
  });
}
