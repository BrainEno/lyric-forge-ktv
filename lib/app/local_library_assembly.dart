import '../features/player/presentation/local_library_dependencies.dart';
import 'app_services.dart';
import 'playback_assembly.dart';

/// What `/library`, `/collections` and `/quick-play` are made of.
///
/// The local-music feature is the last area that still read the service
/// locator from inside its widgets. Its nine collaborators are bound here, in
/// the assembly layer, so the screens take one object and a widget test can
/// hand them fakes instead of the on-disk library and the real audio engine.
LocalLibraryDependencies assembleLocalLibraryDependencies(
  AppServices services,
) {
  return LocalLibraryDependencies(
    libraryRepository: services.localMediaLibraryRepository,
    collectionRepository: services.localMediaCollectionRepository,
    metadataRepository: services.localMediaMetadataRepository,
    playHistoryRepository: services.playHistoryRepository,
    relinkService: services.localMediaRelinkService,
    libraryImportService: services.audioLibraryImportService,
    playbackSession: services.playbackSessionService,
    audioPlayer: services.audioPlayerService,
    lyricsImport: assembleLyricsImportDependencies(services),
  );
}

/// What the "attach a lyric file to this song" action is made of.
///
/// Shares the app's single [PlaybackLyricsResolver]: resolution writes the
/// corrected `hasLyrics` flag back through the session, so the library, the
/// player bar and Now Playing must not each own their own copy of that logic.
LyricsImportDependencies assembleLyricsImportDependencies(
  AppServices services,
) {
  return LyricsImportDependencies(
    lyricsResolver: buildPlaybackLyricsResolver(services),
    importer: services.lyricFileImportService,
  );
}
