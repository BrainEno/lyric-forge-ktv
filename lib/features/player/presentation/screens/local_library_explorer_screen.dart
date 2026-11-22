import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_catalog_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../../core/widgets/app_song_row.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/local_library_browse_item.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/repositories/local_media_collection_repository.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/repositories/local_store_integrity.dart';
import '../../domain/repositories/play_history_repository.dart';
import '../../domain/services/audio_library_import_service.dart';
import '../../domain/services/library_lyrics_auto_linker.dart';
import '../../domain/services/library_lyrics_pairing.dart';
import '../../domain/services/local_media_relink_service.dart';
import '../../domain/services/media_file_names.dart';
import '../../domain/services/playback_session_service.dart';
import '../local_library_dependencies.dart';
import '../widgets/local_library_semantics.dart';
import '../widgets/local_media_metadata_dialog.dart';
import '../widgets/library_explorer_header.dart';
import '../widgets/library_lyrics_link_text.dart';
import '../widgets/library_lyrics_unpair_action.dart';
import '../widgets/local_store_integrity_banner.dart';
import '../widgets/local_song_lyrics_import_action.dart';
import '../widgets/media_import_action.dart';
import '../widgets/now_playing_listener.dart';

class LocalLibraryExplorerScreen extends StatefulWidget {
  /// Supplied by `LocalMusicLibraryShell`, which gets it from the routing table
  /// (`lib/app/local_library_assembly.dart`).
  final LocalLibraryDependencies dependencies;

  /// The smart view the list opens with, for example 自动配对 when the
  /// 曲库目录 settings card links here; null opens 全部.
  final LocalLibrarySmartView? initialSmartView;

  const LocalLibraryExplorerScreen({
    super.key,
    required this.dependencies,
    this.initialSmartView,
  });

  @override
  State<LocalLibraryExplorerScreen> createState() =>
      _LocalLibraryExplorerScreenState();
}

class _LocalLibraryExplorerScreenState
    extends State<LocalLibraryExplorerScreen> {
  late final LocalMediaLibraryRepository _library;
  late final LocalMediaMetadataRepository _metadata;
  late final LocalMediaCollectionRepository _collections;
  late final PlayHistoryRepository _history;
  late final AudioLibraryImportService _importer;
  late final LocalMediaRelinkService _relink;
  late final PlaybackSessionService _session;
  late final TextEditingController _searchController;
  StreamSubscription<int>? _collectionSubscription;

  List<_ExplorerSong> _songs = const [];
  bool _loading = true;
  bool _working = false;

  /// The user's pick of grid or list; null follows the layout: a list on a
  /// phone, where a row shows title, artist and the playing song at a
  /// glance, and the cover grid on wider windows (D-041).
  bool? _gridChoice;
  String _query = '';
  String? _error;
  List<LocalStoreLoadIssue> _storeIssues = const [];
  late LocalLibrarySmartView _smartView =
      widget.initialSmartView ?? LocalLibrarySmartView.all;
  LocalLibrarySortMode _sortMode = LocalLibrarySortMode.title;

  @override
  void initState() {
    super.initState();
    final dependencies = widget.dependencies;
    _library = dependencies.libraryRepository;
    _metadata = dependencies.metadataRepository;
    _collections = dependencies.collectionRepository;
    _history = dependencies.playHistoryRepository;
    _importer = dependencies.libraryImportService;
    _relink = dependencies.relinkService;
    _session = dependencies.playbackSession;
    _searchController = TextEditingController();
    _collectionSubscription = _collections.changes.listen((_) {
      unawaited(_reload(showLoading: false));
    });
    unawaited(_reload(linkLyricFiles: true));
  }

  @override
  void dispose() {
    _searchController.dispose();
    unawaited(_collectionSubscription?.cancel());
    super.dispose();
  }

  String _pathKey(String path) {
    final canonical = File(path).absolute.path;
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }

  Future<void> _reload({
    bool rescan = false,
    bool forceTags = false,
    bool showLoading = true,
    bool linkLyricFiles = false,
  }) async {
    if (mounted && showLoading) setState(() => _loading = true);
    try {
      if (rescan) {
        await _library.refreshFromRoots(_importer.supportedExtensions);
      }
      if (forceTags) {
        await _library.refreshMetadata(force: true);
      }

      final entries = await _library.getAll();
      final overrides = await _metadata.getAll();
      final histories = await _history.getRecentPlayHistory(
        limit: maxHistoryCount,
      );
      final playlists = await _collections.getPlaylists();
      final storeIssues = await _readStoreIssues();

      final overrideByPath = <String, LocalMediaMetadata>{
        for (final item in overrides) _pathKey(item.sourcePath): item,
      };
      final playedAtByPath = <String, DateTime>{};
      for (final item in histories) {
        final key = _pathKey(item.filePath);
        final previous = playedAtByPath[key];
        if (previous == null || item.playedAt.isAfter(previous)) {
          playedAtByPath[key] = item.playedAt;
        }
      }
      final playlistNamesByPath = <String, List<String>>{};
      for (final playlist in playlists) {
        for (final path in playlist.sourcePaths) {
          final key = _pathKey(path);
          final names = playlistNamesByPath.putIfAbsent(key, () => <String>[]);
          if (!names.contains(playlist.name)) names.add(playlist.name);
        }
      }

      final songs = entries
          .map(
            (entry) => _ExplorerSong(
              entry: entry,
              override: overrideByPath[_pathKey(entry.sourcePath)],
              lastPlayedAt: playedAtByPath[_pathKey(entry.sourcePath)],
              playlistNames:
                  playlistNamesByPath[_pathKey(entry.sourcePath)] ?? const [],
            ),
          )
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _songs = songs;
        _storeIssues = storeIssues;
        _error = null;
      });
      if (rescan || linkLyricFiles) unawaited(_linkLyricFiles());
    } catch (error) {
      if (mounted) {
        setState(() => _error = '音乐库加载失败：${describeLocalLibraryError(error)}');
      }
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  /// Gives songs without lyrics the lyric files saved for them in the
  /// library folder or beside them (decision D-033), then says which.
  Future<void> _linkLyricFiles() async {
    final linker = widget.dependencies.lyricsAutoLinker;
    if (linker == null) return;
    final LibraryLyricsLinkResult result;
    try {
      result = await linker.linkAll();
    } on Exception {
      // Pairing is a convenience: the library itself loaded fine.
      return;
    }
    final notice = LibraryLyricsLinkText.libraryNotice(result);
    if (notice == null || !mounted) return;
    await _reload(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(notice), duration: const Duration(seconds: 6)),
    );
  }

  List<_ExplorerSong> get _visibleSongs => queryLocalLibrary<_ExplorerSong>(
    items: _songs,
    browseItem: (song) => song.browseItem,
    query: _query,
    smartView: _smartView,
    sortMode: _sortMode,
  );

  int _smartCount(LocalLibrarySmartView view) {
    final now = DateTime.now();
    return _songs
        .where((song) => song.browseItem.matchesSmartView(view, now: now))
        .length;
  }

  void _selectSmartView(LocalLibrarySmartView view) {
    setState(() {
      _smartView = view;
      if (view == LocalLibrarySmartView.recentlyAdded) {
        _sortMode = LocalLibrarySortMode.recentlyAdded;
      } else if (view == LocalLibrarySmartView.recentlyPlayed) {
        _sortMode = LocalLibrarySortMode.recentlyPlayed;
      }
    });
  }

  Future<void> _withWork(Future<void> Function() work) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) setState(() => _error = describeLocalLibraryError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Stores that loaded only partly (#439); they refuse writes until repaired.
  Future<List<LocalStoreLoadIssue>> _readStoreIssues() async {
    final issues = <LocalStoreLoadIssue>[];
    for (final store in <Object>[_library, _collections]) {
      if (store is! LocalStoreIntegrity) continue;
      final issue = await store.loadIssue();
      if (issue != null) issues.add(issue);
    }
    return issues;
  }

  Future<void> _repairStore(LocalStoreLoadIssue issue) => _withWork(() async {
    final Object store = switch (issue.kind) {
      LocalStoreKind.mediaLibrary => _library,
      LocalStoreKind.collections => _collections,
    };
    if (store is! LocalStoreIntegrity) return;
    final confirmed = await confirmLocalStoreRepair(context, issue);
    if (!confirmed) return;
    final result = await store.repairKeepingReadableRecords();
    await _reload(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已修复${localStoreDisplayName(issue.kind)}：保留 ${result.keptRecords} 条，'
          '放弃 ${result.droppedRecords} 条无法读取的记录。'
          '原文件副本：${result.preservedCopyPath}',
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  });

  Future<void> _addFiles() => _withWork(() async {
    final paths = await _importer.pickAudioFiles();
    if (paths.isNotEmpty) await _reload(showLoading: false);
  });

  /// 导入音频或视频 on a phone (D-056); desktop adds files in place.
  Future<void> _importMedia() async {
    final mediaImport = widget.dependencies.mediaImport;
    if (mediaImport == null) return _addFiles();
    await _withWork(() async {
      final result = await runMediaImport(context, mediaImport);
      if (result != null && result.importedPaths.isNotEmpty) {
        await _reload(showLoading: false);
      }
    });
  }

  /// iOS hands out folders only for the moment they are picked, so a phone
  /// library folder is offered on Android only.
  bool get _offersFolder =>
      widget.dependencies.mediaImport == null || Platform.isAndroid;

  Future<void> _addFolder() => _withWork(() async {
    final paths = await _importer.pickAudioDirectory();
    if (paths.isNotEmpty) await _reload(showLoading: false);
  });

  Future<void> _play(_ExplorerSong song) async {
    if (!song.playable) return;
    final queue = _visibleSongs.where((item) => item.playable).toList();
    final index = queue.indexWhere(
      (item) =>
          _pathKey(item.entry.sourcePath) == _pathKey(song.entry.sourcePath),
    );
    if (index < 0) return;
    await _session.setQueue(
      queue.map((item) => item.playbackItem).toList(growable: false),
      startIndex: index,
    );
    await _reload(showLoading: false);
  }

  Future<void> _playAll({bool shuffle = false}) async {
    final queue = _visibleSongs.where((item) => item.playable).toList();
    if (queue.isEmpty) return;
    if (shuffle) queue.shuffle();
    await _session.setQueue(
      queue.map((item) => item.playbackItem).toList(growable: false),
    );
    await _reload(showLoading: false);
  }

  Future<void> _enqueue(_ExplorerSong song) async {
    if (song.playable) await _session.enqueue(song.playbackItem);
  }

  Future<void> _edit(_ExplorerSong song) async {
    if (!song.playable) return;
    await showLocalMediaMetadataDialog(
      context,
      song.playbackItem,
      repository: widget.dependencies.metadataRepository,
      session: widget.dependencies.playbackSession,
      projectRepository:
          widget.dependencies.lyricsImport.lyricsResolver.projectRepository,
    );
    await _reload(showLoading: false);
  }

  Future<void> _lyrics(_ExplorerSong song) async {
    if (!song.playable) return;
    await importLyricsForLocalPlaybackItem(
      context,
      song.playbackItem,
      widget.dependencies.lyricsImport,
    );
    await _reload(showLoading: false);
  }

  /// Takes back lyrics the library paired from a file name (D-034).
  Future<void> _unpair(_ExplorerSong song) async {
    final linker = widget.dependencies.lyricsAutoLinker;
    final pairing = song.pairing;
    if (linker == null || pairing == null) return;
    await unpairLibraryLyrics(
      context,
      linker: linker,
      audioPath: song.entry.sourcePath,
      songTitle: song.title,
      pairing: pairing,
      onChanged: () => _reload(showLoading: false),
    );
  }

  Future<void> _relinkMissing(_ExplorerSong song) => _withWork(() async {
    if (song.playable) return;
    final result = await _relink.pickReplacementAndRelink(
      song.entry.sourcePath,
    );
    if (result == null) return;
    await _reload(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已重新定位“${song.title}”，收藏、播放列表、资料和播放进度已保留')),
    );
  });

  Future<void> _remove(_ExplorerSong song) => _withWork(() async {
    await _library.remove(song.entry.sourcePath);
    await _reload(showLoading: false);
  });

  void _handleCompactAppAction(String action) {
    switch (action) {
      case 'refresh':
        unawaited(_withWork(() => _reload(rescan: true, showLoading: false)));
        return;
      case 'tags':
        unawaited(
          _withWork(() => _reload(forceTags: true, showLoading: false)),
        );
        return;
      case 'files':
        unawaited(_importMedia());
        return;
      case 'folder':
        unawaited(_addFolder());
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final songs = _visibleSongs;
    final playableCount = songs.where((song) => song.playable).length;
    final missingCount = _smartCount(LocalLibrarySmartView.missingFiles);
    final unpair = widget.dependencies.lyricsAutoLinker == null
        ? null
        : _unpair;

    final grid = _gridChoice ?? !layout.isCompact;
    final compactMenu = layout.isCompact
        ? PopupMenuButton<String>(
            tooltip: '音乐库操作',
            onSelected: _working ? null : _handleCompactAppAction,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'refresh', child: Text('刷新音乐文件夹')),
              const PopupMenuItem(value: 'tags', child: Text('重新读取音频标签')),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'files',
                child: Text(
                  widget.dependencies.mediaImport == null
                      ? '添加音乐文件'
                      : '导入音频或视频',
                ),
              ),
              if (_offersFolder)
                const PopupMenuItem(value: 'folder', child: Text('添加音乐文件夹')),
            ],
            icon: Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
          )
        : null;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      // The phone has the section strip above; its menu sits in the
      // header's toolbar instead of an app bar of its own (D-059).
      appBar: layout.isCompact
          ? null
          : AppBar(
              backgroundColor: AppColors.bgBase,
              title: const Text('音乐库'),
              actions: [
                IconButton(
                  tooltip: '刷新音乐文件夹',
                  onPressed: _working
                      ? null
                      : () => _withWork(
                          () => _reload(rescan: true, showLoading: false),
                        ),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: '重新读取音频标签',
                  onPressed: _working
                      ? null
                      : () => _withWork(
                          () => _reload(forceTags: true, showLoading: false),
                        ),
                  icon: const Icon(Icons.manage_search_rounded),
                ),
                IconButton(
                  tooltip: widget.dependencies.mediaImport == null
                      ? '添加音乐文件'
                      : '导入音频或视频',
                  onPressed: _working ? null : _importMedia,
                  icon: const Icon(Icons.library_add_rounded),
                ),
                if (_offersFolder)
                  IconButton(
                    tooltip: '添加音乐文件夹',
                    onPressed: _working ? null : _addFolder,
                    icon: const Icon(Icons.create_new_folder_rounded),
                  ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
      body: SafeArea(
        child: Column(
          children: [
            LibraryExplorerHeader(
              controller: _searchController,
              query: _query,
              total: _songs.length,
              visible: songs.length,
              playable: playableCount,
              smartView: _smartView,
              sortMode: _sortMode,
              grid: grid,
              countFor: _smartCount,
              onQuery: (value) => setState(() => _query = value),
              onClearQuery: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              onSmartView: _selectSmartView,
              onSortMode: (value) => setState(() => _sortMode = value),
              onGrid: (value) => setState(() => _gridChoice = value),
              onPlayAll: playableCount == 0 ? null : _playAll,
              onShuffle: playableCount < 2
                  ? null
                  : () => _playAll(shuffle: true),
              menu: compactMenu,
              onCleanMissing: missingCount == 0
                  ? null
                  : () => _withWork(() async {
                      await _library.removeMissing();
                      await _reload(showLoading: false);
                    }),
            ),
            if (_working) const LinearProgressIndicator(minHeight: 2),
            if (_storeIssues.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: layout.pageGutter),
                child: LocalStoreIntegrityBanner(
                  issues: _storeIssues,
                  busy: _working,
                  onRepair: (issue) => unawaited(_repairStore(issue)),
                ),
              ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: layout.pageGutter),
                child: Text(
                  _error!,
                  style: TextStyle(color: AppColors.errorText),
                ),
              ),
            Expanded(
              child: _loading
                  ? const AppLoadingState()
                  : _songs.isEmpty
                  ? _EmptyLibrary(
                      onFiles: _importMedia,
                      onFolder: _offersFolder ? _addFolder : null,
                      importsMedia: widget.dependencies.mediaImport != null,
                    )
                  : songs.isEmpty
                  ? const _NoResults()
                  : grid
                  ? _ExplorerGrid(
                      songs: songs,
                      onPlay: _play,
                      onEnqueue: _enqueue,
                      onEdit: _edit,
                      onLyrics: _lyrics,
                      onUnpair: unpair,
                      onRelink: _relinkMissing,
                      onRemove: _remove,
                    )
                  : NowPlayingListener(
                      playbackSession: _session,
                      audioPlayer: widget.dependencies.audioPlayer,
                      builder: (context, nowPlaying) => _ExplorerList(
                        songs: songs,
                        nowPlaying: nowPlaying,
                        onPlay: _play,
                        onEnqueue: _enqueue,
                        onEdit: _edit,
                        onLyrics: _lyrics,
                        onUnpair: unpair,
                        onRelink: _relinkMissing,
                        onRemove: _remove,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplorerSong {
  final LocalMediaLibraryEntry entry;
  final LocalMediaMetadata? override;
  final DateTime? lastPlayedAt;
  final List<String> playlistNames;

  const _ExplorerSong({
    required this.entry,
    required this.override,
    required this.lastPlayedAt,
    required this.playlistNames,
  });

  String get fileName => entry.sourcePath.split(Platform.pathSeparator).last;
  String get fallbackTitle =>
      readableMediaName(
        fileName.replaceAll(
          RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false),
          '',
        ),
      ) ??
      untitledSongTitle;
  String get title =>
      override?.resolvedTitle(
        entry.embeddedTitle?.trim().isNotEmpty == true
            ? entry.embeddedTitle!
            : fallbackTitle,
      ) ??
      (entry.embeddedTitle?.trim().isNotEmpty == true
          ? entry.embeddedTitle!
          : fallbackTitle);
  String? get artist =>
      override?.resolvedArtist(entry.embeddedArtist) ?? entry.embeddedArtist;
  String? get album =>
      override?.resolvedAlbum(entry.embeddedAlbum) ?? entry.embeddedAlbum;
  String? get artworkPath =>
      override?.resolvedArtwork(entry.embeddedArtworkPath) ??
      entry.embeddedArtworkPath;
  bool get hasLyrics => override?.metadata['linkedProjectId'] is String;

  /// The record of lyrics paired from a file name (D-034), if these are.
  LibraryLyricsPairing? get pairing =>
      hasLyrics ? LibraryLyricsPairing.of(override) : null;
  bool get hasAutoPairedLyrics => pairing != null;
  String get lyricsLabel =>
      hasAutoPairedLyrics ? LibraryLyricsLinkText.autoPairedLabel : '有歌词';
  bool get hasUserOverride => override?.hasOverrides == true;
  bool get playable => !entry.isMissing && File(entry.sourcePath).existsSync();

  LocalLibraryBrowseItem get browseItem => LocalLibraryBrowseItem(
    sourcePath: entry.sourcePath,
    title: title,
    artist: artist,
    album: album,
    genres: entry.embeddedGenres,
    playlistNames: playlistNames,
    addedAt: entry.addedAt,
    lastPlayedAt: lastPlayedAt,
    hasLyrics: hasLyrics,
    hasAutoPairedLyrics: hasAutoPairedLyrics,
    hasUserOverride: hasUserOverride,
    isMissing: entry.isMissing,
  );

  String get secondary => [
    if (artist?.trim().isNotEmpty == true) artist!,
    if (album?.trim().isNotEmpty == true) album!,
    entry.format.toUpperCase(),
    if (hasAutoPairedLyrics) LibraryLyricsLinkText.autoPairedLabel,
  ].join(' · ');

  PlaybackItem get playbackItem => PlaybackItem(
    id: 'local:${entry.sourcePath}',
    title: title,
    artist: artist,
    artworkPath: artworkPath,
    hasLyrics: hasLyrics,
    audioAsset: AudioAsset(
      originalPath: entry.sourcePath,
      format: entry.format,
      thumbnailPath: artworkPath,
    ),
    preferredSource: AudioSourceType.original,
  );
}

class _ExplorerGrid extends StatelessWidget {
  final List<_ExplorerSong> songs;
  final ValueChanged<_ExplorerSong> onPlay;
  final ValueChanged<_ExplorerSong> onEnqueue;
  final ValueChanged<_ExplorerSong> onEdit;
  final ValueChanged<_ExplorerSong> onLyrics;
  final ValueChanged<_ExplorerSong>? onUnpair;
  final ValueChanged<_ExplorerSong> onRelink;
  final ValueChanged<_ExplorerSong> onRemove;

  const _ExplorerGrid({
    required this.songs,
    required this.onPlay,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onUnpair,
    required this.onRelink,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        return GridView.builder(
          padding: EdgeInsets.all(layout.pageGutter),
          gridDelegate: AppCatalogCard.gridDelegateFor(layout),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            final unpair = onUnpair;
            return _ExplorerCard(
              song: song,
              compact: layout.isCompact,
              onPlay: () => onPlay(song),
              onEnqueue: () => onEnqueue(song),
              onEdit: () => onEdit(song),
              onLyrics: () => onLyrics(song),
              onUnpair: unpair == null ? null : () => unpair(song),
              onRelink: () => onRelink(song),
              onRemove: () => onRemove(song),
            );
          },
        );
      },
    );
  }
}

class _ExplorerList extends StatelessWidget {
  final List<_ExplorerSong> songs;
  final NowPlaying nowPlaying;
  final ValueChanged<_ExplorerSong> onPlay;
  final ValueChanged<_ExplorerSong> onEnqueue;
  final ValueChanged<_ExplorerSong> onEdit;
  final ValueChanged<_ExplorerSong> onLyrics;
  final ValueChanged<_ExplorerSong>? onUnpair;
  final ValueChanged<_ExplorerSong> onRelink;
  final ValueChanged<_ExplorerSong> onRemove;

  const _ExplorerList({
    required this.songs,
    required this.nowPlaying,
    required this.onPlay,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onUnpair,
    required this.onRelink,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: layout.isCompact ? AppSpacing.sm : layout.pageGutter,
        vertical: AppSpacing.sm,
      ),
      itemCount: songs.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final song = songs[index];
        final unpair = onUnpair;
        final menu = _SongMenuCallbacks(
          onEnqueue: () => onEnqueue(song),
          onEdit: () => onEdit(song),
          onLyrics: () => onLyrics(song),
          onUnpair: unpair == null ? null : () => unpair(song),
          onRelink: () => onRelink(song),
          onRemove: () => onRemove(song),
        );
        return AppSongRow(
          key: ValueKey('library-song:${song.entry.sourcePath}'),
          title: song.title,
          subtitle: song.secondary,
          unavailable: !song.playable,
          unavailableLabel: '文件不可用 · 引用仍保留',
          artwork: song.playable
              ? AppArtwork(
                  path: song.artworkPath,
                  borderRadius: AppArtwork.rowRadius,
                )
              : AppArtwork.missing(
                  path: song.artworkPath,
                  borderRadius: AppArtwork.rowRadius,
                ),
          badges: [
            if (song.hasLyrics)
              const AppSongRowBadge(icon: Icons.lyrics_rounded),
            if (song.hasUserOverride)
              const AppSongRowBadge(icon: Icons.edit_note_rounded),
          ],
          playback: song.playable
              ? nowPlaying.playbackForPath(song.entry.sourcePath)
              : AppSongRowPlayback.none,
          onTap: () => onPlay(song),
          semanticLabel: _songLabel(song),
          semanticHint: LocalLibrarySemantics.playHint,
          semanticActions: _songActions(song, menu),
          trailing: _SongMenu(
            song: song,
            onEnqueue: menu.onEnqueue,
            onEdit: menu.onEdit,
            onLyrics: menu.onLyrics,
            onUnpair: menu.onUnpair,
            onRelink: menu.onRelink,
            onRemove: menu.onRemove,
          ),
        );
      },
    );
  }
}

/// The ⋯ menu's callbacks for one song, shared by the menu and the
/// screen-reader actions of its card or row.
class _SongMenuCallbacks {
  const _SongMenuCallbacks({
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onUnpair,
    required this.onRelink,
    required this.onRemove,
  });

  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback? onUnpair;
  final VoidCallback onRelink;
  final VoidCallback onRemove;
}

/// The format, edit and lyrics notes of [song], read in its label and shown
/// as a card's last line.
List<String> _songDetails(_ExplorerSong song) => [
  [
    if (song.entry.embeddedTrackNumber != null)
      '#${song.entry.embeddedTrackNumber}',
    song.entry.format.toUpperCase(),
  ].join(' · '),
  if (song.hasUserOverride) '已编辑',
  if (song.hasLyrics) song.lyricsLabel,
];

/// What a screen reader hears for [song], on a card and on a row alike.
String _songLabel(_ExplorerSong song) => LocalLibrarySemantics.songCard(
  title: song.title,
  artist: song.artist,
  playable: song.playable,
  details: _songDetails(song),
);

/// The ⋯ menu's entries as screen-reader actions, in menu order and with
/// the menu's wording (audit A-04).
Map<String, VoidCallback?> _songActions(
  _ExplorerSong song,
  _SongMenuCallbacks menu,
) => {
  if (song.playable) '加入播放队列': menu.onEnqueue,
  if (song.playable) '编辑资料与封面': menu.onEdit,
  if (song.playable) (song.hasLyrics ? '打开歌词' : '导入歌词'): menu.onLyrics,
  if (song.hasAutoPairedLyrics)
    LibraryLyricsLinkText.unpairAction: menu.onUnpair,
  if (!song.playable) '重新定位文件': menu.onRelink,
  '从音乐库移除': menu.onRemove,
};

class _ExplorerCard extends StatelessWidget {
  final _ExplorerSong song;
  final bool compact;
  final VoidCallback onPlay;
  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback? onUnpair;
  final VoidCallback onRelink;
  final VoidCallback onRemove;

  const _ExplorerCard({
    required this.song,
    required this.compact,
    required this.onPlay,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onUnpair,
    required this.onRelink,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AppCatalogCard(
      semanticLabel: _songLabel(song),
      semanticHint: LocalLibrarySemantics.playHint,
      enabled: song.playable,
      unavailable: !song.playable,
      onTap: onPlay,
      semanticActions: semanticActions,
      compact: compact,
      artwork: song.playable
          ? AppArtwork(
              path: song.artworkPath,
              borderRadius: AppArtwork.tileRadius,
            )
          : AppArtwork.missing(path: song.artworkPath),
      title: song.title,
      titleTrailing: _SongMenu(
        song: song,
        onEnqueue: onEnqueue,
        onEdit: onEdit,
        onLyrics: onLyrics,
        onUnpair: onUnpair,
        onRelink: onRelink,
        onRemove: onRemove,
      ),
      subtitle: song.playable ? (song.artist ?? '本地音乐') : '文件不可用',
      subtitleIsAlert: !song.playable,
      caption: _songDetails(
        song,
      ).where((value) => value.isNotEmpty).join(' · '),
    );
  }

  /// The ⋯ menu's entries as the card's screen-reader actions.
  Map<String, VoidCallback?> get semanticActions => _songActions(
    song,
    _SongMenuCallbacks(
      onEnqueue: onEnqueue,
      onEdit: onEdit,
      onLyrics: onLyrics,
      onUnpair: onUnpair,
      onRelink: onRelink,
      onRemove: onRemove,
    ),
  );
}

class _SongMenu extends StatelessWidget {
  final _ExplorerSong song;
  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback? onUnpair;
  final VoidCallback onRelink;
  final VoidCallback onRemove;

  const _SongMenu({
    required this.song,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onUnpair,
    required this.onRelink,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'queue':
            onEnqueue();
            return;
          case 'edit':
            onEdit();
            return;
          case 'lyrics':
            onLyrics();
            return;
          case 'unpair':
            onUnpair?.call();
            return;
          case 'relink':
            onRelink();
            return;
          case 'remove':
            onRemove();
            return;
        }
      },
      itemBuilder: (_) => [
        if (song.playable)
          const PopupMenuItem(value: 'queue', child: Text('加入播放队列')),
        if (song.playable)
          const PopupMenuItem(value: 'edit', child: Text('编辑资料与封面')),
        if (song.playable)
          PopupMenuItem(
            value: 'lyrics',
            child: Text(song.hasLyrics ? '打开歌词' : '导入歌词'),
          ),
        if (song.hasAutoPairedLyrics && onUnpair != null)
          const PopupMenuItem(
            value: 'unpair',
            child: Text(LibraryLyricsLinkText.unpairAction),
          ),
        if (!song.playable)
          const PopupMenuItem(value: 'relink', child: Text('重新定位文件')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'remove', child: Text('从音乐库移除')),
      ],
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.search_off_rounded,
      title: '没有符合当前搜索或智能列表条件的歌曲',
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onFiles;
  final VoidCallback? onFolder;

  /// The phone's 导入音频或视频 (D-056) leads instead of the folder.
  final bool importsMedia;

  const _EmptyLibrary({
    required this.onFiles,
    required this.onFolder,
    this.importsMedia = false,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final minimumSize = Size(
      layout.minimumInteractiveExtent,
      layout.minimumInteractiveExtent,
    );
    final folder = onFolder;
    if (importsMedia) {
      return AppEmptyState(
        density: AppEmptyStateDensity.hero,
        icon: Icons.library_music_rounded,
        title: '建立你的本地音乐库',
        message: '从“文件”或相册导入歌曲；视频会自动提取声音，保存成较小的音频文件。',
        actions: [
          FilledButton.icon(
            key: const ValueKey('library-import-media'),
            style: FilledButton.styleFrom(minimumSize: minimumSize),
            onPressed: onFiles,
            icon: const Icon(Icons.add_rounded),
            label: const Text('导入音频或视频'),
          ),
          if (folder != null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: minimumSize),
              onPressed: folder,
              icon: const Icon(Icons.folder_rounded),
              label: const Text('添加音乐文件夹'),
            ),
        ],
      );
    }
    return AppEmptyState(
      density: AppEmptyStateDensity.hero,
      icon: Icons.library_music_rounded,
      title: '建立你的本地音乐库',
      message: '导入后自动读取标题、艺人、专辑和内嵌封面。',
      actions: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: minimumSize),
          onPressed: folder,
          icon: const Icon(Icons.folder_rounded),
          label: const Text('添加音乐文件夹'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: minimumSize),
          onPressed: onFiles,
          icon: const Icon(Icons.audio_file_rounded),
          label: const Text('添加音乐文件'),
        ),
      ],
    );
  }
}
