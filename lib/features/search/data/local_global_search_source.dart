import '../../../core/navigation/routes.dart';
import '../../player/domain/models/local_media_library_entry.dart';
import '../../player/domain/models/local_media_metadata.dart';
import '../../player/domain/models/local_playlist.dart';
import '../../player/domain/repositories/local_media_collection_repository.dart';
import '../../player/domain/repositories/local_media_library_repository.dart';
import '../../player/domain/repositories/local_media_metadata_repository.dart';
import '../../player/domain/services/media_file_names.dart';
import '../../player/domain/services/playback_session_service.dart';
import '../../project/domain/models/audio_asset.dart';
import '../../project/domain/models/lyric_document.dart';
import '../../project/domain/models/project_manifest.dart';
import '../../project/domain/repositories/project_repository.dart';
import '../domain/global_search_actions.dart';
import '../domain/global_search_item.dart';
import '../domain/global_search_source.dart';

/// Reads the global search items from the app's stores (D-065).
///
/// Each store is read on its own: a library that fails to load still leaves
/// the pages and projects searchable, and the other way round.
class LocalGlobalSearchSource implements GlobalSearchSource {
  LocalGlobalSearchSource({
    required this.projectRepository,
    required this.libraryRepository,
    required this.metadataRepository,
    required this.collectionRepository,
    required this.phone,
  });

  final ProjectRepository projectRepository;
  final LocalMediaLibraryRepository libraryRepository;
  final LocalMediaMetadataRepository metadataRepository;
  final LocalMediaCollectionRepository collectionRepository;

  /// The phone's pages instead of the desktop's.
  final bool phone;

  @override
  Future<List<GlobalSearchItem>> load() async {
    // Started together, awaited one by one.
    final projectsRead = _orEmpty(projectRepository.getAllProjects);
    final entriesRead = _orEmpty(libraryRepository.getAll);
    final overridesRead = _orEmpty(metadataRepository.getAll);
    final playlistsRead = _orEmpty(collectionRepository.getPlaylists);
    final projects = await projectsRead;
    final entries = await entriesRead;
    final overrides = {
      for (final item in await overridesRead) pathKey(item.sourcePath): item,
    };
    final playlists = await playlistsRead;

    final songs = <String, PlaybackItem>{};
    final songItems = <GlobalSearchItem>[];
    for (final entry in entries) {
      if (entry.isMissing) continue;
      final override = overrides[pathKey(entry.sourcePath)];
      final song = songFor(entry, override);
      songs[pathKey(entry.sourcePath)] = song;
      final album = override?.resolvedAlbum(entry.embeddedAlbum);
      songItems.add(
        GlobalSearchItem(
          kind: GlobalSearchKind.song,
          id: song.id,
          title: song.title,
          subtitle: _join([song.artist, album ?? entry.embeddedAlbum]),
          keywords: [_fileName(entry.sourcePath)],
          target: PlaySongTarget(song),
        ),
      );
    }

    final sortedProjects = [...projects]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return [
      ...globalSearchActions(phone: phone),
      for (final project in sortedProjects) projectItem(project),
      ...songItems,
      for (final playlist in playlists) playlistItem(playlist, songs),
    ];
  }

  /// The search item of [playlist]; [songs] are the library's playable
  /// songs by [pathKey], so a missing file is left out of 播放歌单.
  static GlobalSearchItem playlistItem(
    LocalPlaylist playlist,
    Map<String, PlaybackItem> songs,
  ) => GlobalSearchItem(
    kind: GlobalSearchKind.playlist,
    id: playlist.id,
    title: playlist.name,
    subtitle: _join([
      '${playlist.sourcePaths.length} 首',
      playlist.description,
    ]),
    target: OpenPlaylistTarget(
      playlistId: playlist.id,
      route: playlistRoute(playlist.id),
      songs: [
        for (final path in playlist.sourcePaths) ?songs[pathKey(path)],
      ],
    ),
  );

  /// The route that opens the playlist [id] in the library.
  static String playlistRoute(String id) =>
      '${Routes.playlists}?playlist=${Uri.encodeQueryComponent(id)}';

  /// The search item of [project]: its name, artist and album, and its lyric
  /// lines for 歌词里提到.
  static GlobalSearchItem projectItem(ProjectManifest project) {
    final lines = [
      for (final line in project.lyricDocument?.lines ?? const <LyricLine>[])
        if (line.text.trim().isNotEmpty) line.text,
    ];
    return GlobalSearchItem(
      kind: GlobalSearchKind.project,
      id: project.id,
      title: project.name.trim().isEmpty ? '未命名工程' : project.name.trim(),
      subtitle: _join([
        project.artist,
        project.album,
        if (lines.isEmpty) '还没有歌词' else '${lines.length} 行歌词',
      ]),
      keywords: [
        if (project.audioAsset != null)
          _fileName(project.audioAsset!.originalPath),
      ],
      lyricLines: lines,
      target: OpenRouteTarget(Routes.projectDetailPath(project.id)),
    );
  }

  /// The queue entry for a library song, keyed as the library keys it so
  /// the session recognises it from either place; the user's own title,
  /// artist and cover win over the tags.
  static PlaybackItem songFor(
    LocalMediaLibraryEntry entry,
    LocalMediaMetadata? override,
  ) {
    final tagged = entry.embeddedTitle?.trim();
    final fallback = tagged == null || tagged.isEmpty
        ? songTitleFromPath(entry.sourcePath)
        : tagged;
    final artwork = override?.artworkPath?.trim().isNotEmpty == true
        ? override!.artworkPath
        : entry.embeddedArtworkPath;
    return PlaybackItem(
      id: 'local:${entry.sourcePath}',
      title: override?.resolvedTitle(fallback) ?? fallback,
      artist: override?.resolvedArtist(entry.embeddedArtist) ??
          entry.embeddedArtist,
      artworkPath: artwork,
      audioAsset: AudioAsset(
        originalPath: entry.sourcePath,
        format: entry.format,
        thumbnailPath: artwork,
      ),
      preferredSource: AudioSourceType.original,
    );
  }

  /// Compares paths the way the file system does: Windows paths ignore case
  /// and either slash.
  static String pathKey(String path) {
    final windows = path.contains('\\') || RegExp(r'^[A-Za-z]:').hasMatch(path);
    return windows ? path.replaceAll('\\', '/').toLowerCase() : path;
  }

  static String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;

  static String? _join(List<String?> parts) {
    final kept = [
      for (final part in parts)
        if (part != null && part.trim().isNotEmpty) part.trim(),
    ];
    return kept.isEmpty ? null : kept.join(' · ');
  }

  static Future<List<T>> _orEmpty<T>(Future<List<T>> Function() read) async {
    try {
      return await read();
    } on Object {
      // One store failing leaves the others searchable.
      return <T>[];
    }
  }
}
