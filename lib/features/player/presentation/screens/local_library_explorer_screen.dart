import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/local_library_browse_item.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/repositories/local_media_collection_repository.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/repositories/play_history_repository.dart';
import '../../domain/services/audio_library_import_service.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/local_media_metadata_dialog.dart';
import '../widgets/local_song_lyrics_import_action.dart';

class LocalLibraryExplorerScreen extends StatefulWidget {
  const LocalLibraryExplorerScreen({super.key});

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
  late final PlaybackSessionService _session;
  late final TextEditingController _searchController;
  StreamSubscription<int>? _collectionSubscription;

  List<_ExplorerSong> _songs = const [];
  bool _loading = true;
  bool _working = false;
  bool _grid = true;
  String _query = '';
  String? _error;
  LocalLibrarySmartView _smartView = LocalLibrarySmartView.all;
  LocalLibrarySortMode _sortMode = LocalLibrarySortMode.title;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _library = services.localMediaLibraryRepository;
    _metadata = services.localMediaMetadataRepository;
    _collections = services.localMediaCollectionRepository;
    _history = services.playHistoryRepository;
    _importer = services.audioLibraryImportService;
    _session = services.playbackSessionService;
    _searchController = TextEditingController();
    _collectionSubscription = _collections.changes.listen((_) {
      unawaited(_reload(showLoading: false));
    });
    unawaited(_reload());
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
      final histories =
          await _history.getRecentPlayHistory(limit: maxHistoryCount);
      final playlists = await _collections.getPlaylists();

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
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '音乐库加载失败：$error');
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
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
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _addFiles() => _withWork(() async {
        final paths = await _importer.pickAudioFiles();
        if (paths.isNotEmpty) await _reload(showLoading: false);
      });

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

  Future<void> _playAll() async {
    final queue = _visibleSongs.where((item) => item.playable).toList();
    if (queue.isEmpty) return;
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
    await showLocalMediaMetadataDialog(context, song.playbackItem);
    await _reload(showLoading: false);
  }

  Future<void> _lyrics(_ExplorerSong song) async {
    if (!song.playable) return;
    await importLyricsForLocalPlaybackItem(context, song.playbackItem);
    await _reload(showLoading: false);
  }

  Future<void> _remove(_ExplorerSong song) async {
    await _library.remove(song.entry.sourcePath);
    await _reload(showLoading: false);
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
        unawaited(_addFiles());
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

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        title: const Text('音乐库'),
        actions: [
          if (layout.isCompact)
            PopupMenuButton<String>(
              tooltip: '音乐库操作',
              onSelected: _working ? null : _handleCompactAppAction,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'refresh', child: Text('刷新音乐文件夹')),
                PopupMenuItem(value: 'tags', child: Text('重新读取音频标签')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'files', child: Text('添加音乐文件')),
                PopupMenuItem(value: 'folder', child: Text('添加音乐文件夹')),
              ],
              icon: const Icon(Icons.more_vert_rounded),
            )
          else ...[
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
              tooltip: '添加音乐文件',
              onPressed: _working ? null : _addFiles,
              icon: const Icon(Icons.library_add_rounded),
            ),
            IconButton(
              tooltip: '添加音乐文件夹',
              onPressed: _working ? null : _addFolder,
              icon: const Icon(Icons.create_new_folder_rounded),
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ExplorerHeader(
              controller: _searchController,
              query: _query,
              total: _songs.length,
              visible: songs.length,
              playable: playableCount,
              smartView: _smartView,
              sortMode: _sortMode,
              grid: _grid,
              countFor: _smartCount,
              onQuery: (value) => setState(() => _query = value),
              onClearQuery: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              onSmartView: _selectSmartView,
              onSortMode: (value) => setState(() => _sortMode = value),
              onGrid: (value) => setState(() => _grid = value),
              onPlayAll: playableCount == 0 ? null : _playAll,
              onCleanMissing: missingCount == 0
                  ? null
                  : () => _withWork(() async {
                        await _library.removeMissing();
                        await _reload(showLoading: false);
                      }),
            ),
            if (_working) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: layout.pageGutter),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _songs.isEmpty
                      ? _EmptyLibrary(onFiles: _addFiles, onFolder: _addFolder)
                      : songs.isEmpty
                          ? const _NoResults()
                          : _grid
                              ? _ExplorerGrid(
                                  songs: songs,
                                  onPlay: _play,
                                  onEnqueue: _enqueue,
                                  onEdit: _edit,
                                  onLyrics: _lyrics,
                                  onRemove: _remove,
                                )
                              : _ExplorerList(
                                  songs: songs,
                                  onPlay: _play,
                                  onEnqueue: _enqueue,
                                  onEdit: _edit,
                                  onLyrics: _lyrics,
                                  onRemove: _remove,
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
  String get fallbackTitle => fileName.replaceAll(
        RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false),
        '',
      );
  String get title => override?.resolvedTitle(
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
        hasUserOverride: hasUserOverride,
        isMissing: entry.isMissing,
      );

  String get secondary => [
        if (artist?.trim().isNotEmpty == true) artist!,
        if (album?.trim().isNotEmpty == true) album!,
        entry.format.toUpperCase(),
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

class _ExplorerHeader extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final int total;
  final int visible;
  final int playable;
  final LocalLibrarySmartView smartView;
  final LocalLibrarySortMode sortMode;
  final bool grid;
  final int Function(LocalLibrarySmartView view) countFor;
  final ValueChanged<String> onQuery;
  final VoidCallback onClearQuery;
  final ValueChanged<LocalLibrarySmartView> onSmartView;
  final ValueChanged<LocalLibrarySortMode> onSortMode;
  final ValueChanged<bool> onGrid;
  final VoidCallback? onPlayAll;
  final VoidCallback? onCleanMissing;

  const _ExplorerHeader({
    required this.controller,
    required this.query,
    required this.total,
    required this.visible,
    required this.playable,
    required this.smartView,
    required this.sortMode,
    required this.grid,
    required this.countFor,
    required this.onQuery,
    required this.onClearQuery,
    required this.onSmartView,
    required this.onSortMode,
    required this.onGrid,
    required this.onPlayAll,
    required this.onCleanMissing,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final search = TextField(
          controller: controller,
          onChanged: onQuery,
          decoration: InputDecoration(
            hintText: layout.isCompact
                ? '搜索音乐库'
                : '搜索歌曲、艺人、专辑、流派、文件名或歌单',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    onPressed: onClearQuery,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        );
        final controls = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<LocalLibrarySortMode>(
              value: sortMode,
              onChanged: (value) {
                if (value != null) onSortMode(value);
              },
              items: LocalLibrarySortMode.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_sortLabel(value)),
                    ),
                  )
                  .toList(growable: false),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.grid_view_rounded),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.view_list_rounded),
                ),
              ],
              selected: {grid},
              showSelectedIcon: false,
              onSelectionChanged: (value) => onGrid(value.first),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                minimumSize: Size(
                  layout.minimumInteractiveExtent,
                  layout.minimumInteractiveExtent,
                ),
              ),
              onPressed: onPlayAll,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(layout.isCompact ? '播放结果' : '播放当前结果'),
            ),
          ],
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            layout.pageGutter,
            AppSpacing.md,
            layout.pageGutter,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (layout.isLarge || layout.isExtraLarge)
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: AppSpacing.md),
                    controls,
                  ],
                )
              else ...[
                search,
                const SizedBox(height: AppSpacing.sm),
                controls,
              ],
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: LocalLibrarySmartView.values.map((view) {
                    final selected = view == smartView;
                    final count = countFor(view);
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: FilterChip(
                        selected: selected,
                        onSelected: (_) => onSmartView(view),
                        avatar: Icon(_smartIcon(view), size: 18),
                        label: Text('${_smartLabel(view)}  $count'),
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(visible == total ? '$total 首歌曲' : '$visible / $total 首'),
                  Text(
                    '$playable 首当前可播放',
                    style: const TextStyle(color: AppColors.textTertiary),
                  ),
                  if (smartView == LocalLibrarySmartView.recentlyAdded)
                    const Text(
                      '最近添加 = 过去 30 天',
                      style: TextStyle(color: AppColors.textTertiary),
                    ),
                  if (onCleanMissing != null)
                    TextButton(
                      onPressed: onCleanMissing,
                      child: const Text('清理缺失项'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _smartLabel(LocalLibrarySmartView view) => switch (view) {
        LocalLibrarySmartView.all => '全部',
        LocalLibrarySmartView.recentlyAdded => '最近添加',
        LocalLibrarySmartView.recentlyPlayed => '最近播放',
        LocalLibrarySmartView.withLyrics => '有歌词',
        LocalLibrarySmartView.withoutLyrics => '无歌词',
        LocalLibrarySmartView.editedMetadata => '已编辑资料',
        LocalLibrarySmartView.missingFiles => '文件不可用',
      };

  static IconData _smartIcon(LocalLibrarySmartView view) => switch (view) {
        LocalLibrarySmartView.all => Icons.library_music_rounded,
        LocalLibrarySmartView.recentlyAdded => Icons.fiber_new_rounded,
        LocalLibrarySmartView.recentlyPlayed => Icons.history_rounded,
        LocalLibrarySmartView.withLyrics => Icons.lyrics_rounded,
        LocalLibrarySmartView.withoutLyrics => Icons.lyrics_outlined,
        LocalLibrarySmartView.editedMetadata => Icons.edit_note_rounded,
        LocalLibrarySmartView.missingFiles => Icons.link_off_rounded,
      };

  static String _sortLabel(LocalLibrarySortMode mode) => switch (mode) {
        LocalLibrarySortMode.title => '标题 A-Z',
        LocalLibrarySortMode.artist => '按艺人',
        LocalLibrarySortMode.album => '按专辑',
        LocalLibrarySortMode.recentlyAdded => '最近添加',
        LocalLibrarySortMode.recentlyPlayed => '最近播放',
      };
}

class _ExplorerGrid extends StatelessWidget {
  final List<_ExplorerSong> songs;
  final ValueChanged<_ExplorerSong> onPlay;
  final ValueChanged<_ExplorerSong> onEnqueue;
  final ValueChanged<_ExplorerSong> onEdit;
  final ValueChanged<_ExplorerSong> onLyrics;
  final ValueChanged<_ExplorerSong> onRemove;

  const _ExplorerGrid({
    required this.songs,
    required this.onPlay,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final columns = layout.gridColumns(
          minTileWidth: layout.isCompact ? 160 : 190,
          min: layout.isCompact ? 2 : 2,
          max: 7,
        );
        return GridView.builder(
          padding: EdgeInsets.all(layout.pageGutter),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: layout.isCompact ? 0.74 : 0.72,
          ),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            return _ExplorerCard(
              song: song,
              compact: layout.isCompact,
              onPlay: () => onPlay(song),
              onEnqueue: () => onEnqueue(song),
              onEdit: () => onEdit(song),
              onLyrics: () => onLyrics(song),
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
  final ValueChanged<_ExplorerSong> onPlay;
  final ValueChanged<_ExplorerSong> onEnqueue;
  final ValueChanged<_ExplorerSong> onEdit;
  final ValueChanged<_ExplorerSong> onLyrics;
  final ValueChanged<_ExplorerSong> onRemove;

  const _ExplorerList({
    required this.songs,
    required this.onPlay,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return ListView.separated(
      padding: EdgeInsets.all(layout.pageGutter),
      itemCount: songs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(
          enabled: song.playable,
          minVerticalPadding: layout.isCompact ? AppSpacing.sm : null,
          leading: SizedBox(
            width: layout.minimumInteractiveExtent,
            height: layout.minimumInteractiveExtent,
            child: _Artwork(song),
          ),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            song.playable ? song.secondary : '文件不可用 · 引用仍保留',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: song.playable ? () => onPlay(song) : null,
          trailing: _SongMenu(
            song: song,
            onEnqueue: () => onEnqueue(song),
            onEdit: () => onEdit(song),
            onLyrics: () => onLyrics(song),
            onRemove: () => onRemove(song),
          ),
        );
      },
    );
  }
}

class _ExplorerCard extends StatelessWidget {
  final _ExplorerSong song;
  final bool compact;
  final VoidCallback onPlay;
  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback onRemove;

  const _ExplorerCard({
    required this.song,
    required this.compact,
    required this.onPlay,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: song.playable ? onPlay : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(compact ? AppSpacing.xs : AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: song.playable
                ? AppColors.borderMuted
                : AppColors.error.withAlpha(80),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Artwork(song)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _SongMenu(
                  song: song,
                  onEnqueue: onEnqueue,
                  onEdit: onEdit,
                  onLyrics: onLyrics,
                  onRemove: onRemove,
                ),
              ],
            ),
            Text(
              song.playable ? (song.artist ?? '本地音乐') : '文件不可用',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              [
                entryLabel(song),
                if (song.hasUserOverride) '已编辑',
                if (song.hasLyrics) '有歌词',
              ].where((value) => value.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String entryLabel(_ExplorerSong song) => [
        if (song.entry.embeddedTrackNumber != null)
          '#${song.entry.embeddedTrackNumber}',
        song.entry.format.toUpperCase(),
      ].join(' · ');
}

class _SongMenu extends StatelessWidget {
  final _ExplorerSong song;
  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback onRemove;

  const _SongMenu({
    required this.song,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
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
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'remove', child: Text('从音乐库移除')),
      ],
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

class _Artwork extends StatelessWidget {
  final _ExplorerSong song;

  const _Artwork(this.song);

  @override
  Widget build(BuildContext context) {
    final file = song.artworkPath == null ? null : File(song.artworkPath!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: file?.existsSync() == true
          ? Image.file(file!, fit: BoxFit.cover)
          : Container(
              color: AppColors.bgSurface,
              alignment: Alignment.center,
              child: Icon(
                song.playable ? Icons.album_rounded : Icons.link_off_rounded,
                color: song.playable ? AppColors.textTertiary : AppColors.error,
                size: 50,
              ),
            ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(layout.pageGutter),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: AppColors.textTertiary,
            ),
            SizedBox(height: AppSpacing.md),
            Text('没有符合当前搜索或智能列表条件的歌曲'),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onFiles;
  final VoidCallback onFolder;

  const _EmptyLibrary({required this.onFiles, required this.onFolder});

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(layout.pageGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_rounded,
              size: layout.isCompact ? 56 : 72,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '建立你的本地音乐库',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              '导入后自动读取标题、艺人、专辑和内嵌封面。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: Size(
                      layout.minimumInteractiveExtent,
                      layout.minimumInteractiveExtent,
                    ),
                  ),
                  onPressed: onFolder,
                  icon: const Icon(Icons.folder_rounded),
                  label: const Text('添加音乐文件夹'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(
                      layout.minimumInteractiveExtent,
                      layout.minimumInteractiveExtent,
                    ),
                  ),
                  onPressed: onFiles,
                  icon: const Icon(Icons.audio_file_rounded),
                  label: const Text('添加音乐文件'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
