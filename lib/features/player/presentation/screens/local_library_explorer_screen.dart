import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../../core/widgets/undo_snack_bar.dart';
import '../../domain/models/local_library_browse_item.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/repositories/local_media_collection_repository.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/repositories/local_store_integrity.dart';
import '../../domain/repositories/play_history_repository.dart';
import '../../domain/services/audio_library_import_service.dart';
import '../../domain/services/library_lyrics_auto_linker.dart';
import '../../domain/services/local_media_relink_service.dart';
import '../../domain/services/media_file_names.dart';
import '../../domain/services/playback_session_service.dart';
import '../local_library_dependencies.dart';
import '../local_library_explorer_song.dart';
import '../widgets/library_explorer_header.dart';
import '../widgets/library_lyrics_link_text.dart';
import '../widgets/library_lyrics_unpair_action.dart';
import '../widgets/local_library_explorer_views.dart';
import '../widgets/local_media_metadata_dialog.dart';
import '../widgets/local_song_lyrics_import_action.dart';
import '../widgets/local_store_integrity_banner.dart';
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

  List<LocalLibraryExplorerSong> _songs = const [];
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
            (entry) => LocalLibraryExplorerSong(
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

  List<LocalLibraryExplorerSong> get _visibleSongs =>
      queryLocalLibrary<LocalLibraryExplorerSong>(
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

  Future<void> _play(LocalLibraryExplorerSong song) async {
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

  Future<void> _enqueue(LocalLibraryExplorerSong song) async {
    if (song.playable) await _session.enqueue(song.playbackItem);
  }

  Future<void> _edit(LocalLibraryExplorerSong song) async {
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

  Future<void> _lyrics(LocalLibraryExplorerSong song) async {
    if (!song.playable) return;
    await importLyricsForLocalPlaybackItem(
      context,
      song.playbackItem,
      widget.dependencies.lyricsImport,
    );
    await _reload(showLoading: false);
  }

  /// Takes back lyrics the library paired from a file name (D-034).
  Future<void> _unpair(LocalLibraryExplorerSong song) async {
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

  Future<void> _relinkMissing(LocalLibraryExplorerSong song) =>
      _withWork(() async {
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

  /// Takes the song off the list (the file stays) and offers 撤销 (D-064).
  Future<void> _remove(LocalLibraryExplorerSong song) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = song.entry.sourcePath;
    var removed = false;
    await _withWork(() async {
      await _library.remove(path);
      removed = true;
      await _reload(showLoading: false);
    });
    if (!removed) return;
    showUndoSnackBar(
      messenger,
      message: '已从音乐库移除“${song.title}”（文件还在原处）',
      onUndo: () async {
        await _library.addPaths([path]);
        if (mounted) await _reload(showLoading: false);
        return null;
      },
    );
  }

  /// Drops songs whose file is gone and offers 撤销 (D-064).
  Future<void> _cleanMissing() async {
    final messenger = ScaffoldMessenger.of(context);
    var paths = const <String>[];
    await _withWork(() async {
      final entries = await _library.getAll();
      paths = [
        for (final entry in entries)
          if (entry.isMissing) entry.sourcePath,
      ];
      await _library.removeMissing();
      await _reload(showLoading: false);
    });
    if (paths.isEmpty) return;
    showUndoSnackBar(
      messenger,
      message: '已移除 ${paths.length} 首找不到文件的歌曲',
      onUndo: () async {
        await _library.addPaths(paths);
        if (mounted) await _reload(showLoading: false);
        return null;
      },
    );
  }

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
              onCleanMissing: missingCount == 0 ? null : _cleanMissing,
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
                  ? LocalLibraryExplorerEmptyState(
                      onFiles: _importMedia,
                      onFolder: _offersFolder ? _addFolder : null,
                      importsMedia: widget.dependencies.mediaImport != null,
                    )
                  : songs.isEmpty
                  ? const LocalLibraryExplorerNoResults()
                  : grid
                  ? LocalLibraryExplorerGrid(
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
                      builder: (context, nowPlaying) =>
                          LocalLibraryExplorerList(
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
