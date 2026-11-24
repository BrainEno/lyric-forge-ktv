import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_catalog_card.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../../core/widgets/undo_snack_bar.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/models/local_playlist.dart';
import '../../domain/repositories/local_media_collection_repository.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/playback_session_service.dart';
import '../local_library_dependencies.dart';
import '../widgets/local_collection_actions.dart';
import '../widgets/local_collection_song.dart';
import '../widgets/local_collection_song_tile.dart';
import '../widgets/local_collection_widgets.dart';
import '../widgets/local_store_integrity_banner.dart';

enum LocalCollectionView { favorites, playlists }

class LocalCollectionsScreen extends StatefulWidget {
  final LocalCollectionView view;

  /// Supplied by `LocalMusicLibraryShell`.
  final LocalLibraryDependencies dependencies;

  /// The playlist to open with, e.g. one picked in the global search
  /// (D-065). Ignored when it no longer exists.
  final String? initialPlaylistId;

  const LocalCollectionsScreen({
    super.key,
    required this.view,
    required this.dependencies,
    this.initialPlaylistId,
  });

  @override
  State<LocalCollectionsScreen> createState() => _LocalCollectionsScreenState();
}

class _LocalCollectionsScreenState extends State<LocalCollectionsScreen> {
  late final LocalMediaCollectionRepository _collections;
  late final LocalMediaLibraryRepository _library;
  late final LocalMediaMetadataRepository _metadata;
  late final PlaybackSessionService _session;

  StreamSubscription<int>? _collectionSubscription;
  Map<String, LocalMediaLibraryEntry> _entryByPath = const {};
  Map<String, LocalMediaMetadata> _metadataByPath = const {};
  Set<String> _favoritePaths = const {};
  List<LocalPlaylist> _playlists = const [];
  String? _selectedPlaylistId;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final dependencies = widget.dependencies;
    _collections = dependencies.collectionRepository;
    _library = dependencies.libraryRepository;
    _metadata = dependencies.metadataRepository;
    _session = dependencies.playbackSession;
    if (widget.view == LocalCollectionView.playlists) {
      _selectedPlaylistId = widget.initialPlaylistId;
    }
    _collectionSubscription = _collections.changes.listen((_) {
      unawaited(_reload());
    });
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant LocalCollectionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view &&
        widget.view == LocalCollectionView.favorites) {
      _selectedPlaylistId = null;
    }
    unawaited(_reload());
  }

  @override
  void dispose() {
    unawaited(_collectionSubscription?.cancel());
    super.dispose();
  }

  String _pathKey(String path) {
    final canonical = File(path).absolute.path;
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final entries = await _library.getAll();
      final overrides = await _metadata.getAll();
      final favorites = await _collections.getFavoritePaths();
      final playlists = await _collections.getPlaylists();

      final entryByPath = <String, LocalMediaLibraryEntry>{
        for (final entry in entries) _pathKey(entry.sourcePath): entry,
      };
      final metadataByPath = <String, LocalMediaMetadata>{
        for (final item in overrides) _pathKey(item.sourcePath): item,
      };

      if (!mounted) return;
      setState(() {
        _entryByPath = entryByPath;
        _metadataByPath = metadataByPath;
        _favoritePaths = Set<String>.unmodifiable(favorites);
        _playlists = playlists;
        if (_selectedPlaylistId != null &&
            !_playlists.any((item) => item.id == _selectedPlaylistId)) {
          _selectedPlaylistId = null;
        }
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = '收藏与播放列表加载失败：${describeLocalLibraryError(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  LocalCollectionSong _song(String sourcePath) {
    final key = _pathKey(sourcePath);
    return LocalCollectionSong(
      sourcePath: sourcePath,
      entry: _entryByPath[key],
      override: _metadataByPath[key],
    );
  }

  List<LocalCollectionSong> get _favoriteSongs {
    final songs = _favoritePaths.map(_song).toList(growable: false);
    songs.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return songs;
  }

  LocalPlaylist? get _selectedPlaylist {
    final id = _selectedPlaylistId;
    if (id == null) return null;
    for (final item in _playlists) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> _playSongs(
    List<LocalCollectionSong> songs, {
    int requestedIndex = 0,
  }) async {
    if (songs.isEmpty) return;
    final playable = <PlaybackItem>[];
    var playableBeforeRequested = 0;

    for (var i = 0; i < songs.length; i++) {
      final item = songs[i].playbackItem;
      if (item == null) continue;
      if (i < requestedIndex) playableBeforeRequested += 1;
      playable.add(item);
    }

    if (playable.isEmpty) return;
    final startIndex = playableBeforeRequested
        .clamp(0, playable.length - 1)
        .toInt();
    await _session.setQueue(playable, startIndex: startIndex);
  }

  Future<void> _enqueue(LocalCollectionSong song) async {
    final item = song.playbackItem;
    if (item == null) return;
    await _session.enqueue(item);
  }

  Future<void> _removeFavorite(LocalCollectionSong song) async {
    final messenger = ScaffoldMessenger.of(context);
    var removed = false;
    await _withWork(() async {
      await _collections.setFavorite(song.sourcePath, false);
      removed = true;
      await _reload();
    });
    if (!removed) return;
    showUndoSnackBar(
      messenger,
      message: '已取消收藏“${song.title}”',
      onUndo: () async {
        await _collections.setFavorite(song.sourcePath, true);
        if (mounted) await _reload();
        return null;
      },
    );
  }

  Future<void> _addFavoriteToPlaylist(LocalCollectionSong song) async {
    await showAddToLocalPlaylistDialog(
      context,
      sourcePath: song.sourcePath,
      title: song.title,
      repository: _collections,
    );
    await _reload();
  }

  Future<void> _createPlaylist() async {
    final playlist = await showCreateLocalPlaylistDialog(
      context,
      repository: _collections,
    );
    if (playlist == null || !mounted) return;
    await _reload();
    if (mounted) setState(() => _selectedPlaylistId = playlist.id);
  }

  Future<void> _renamePlaylist(LocalPlaylist playlist) async {
    final updated = await showRenameLocalPlaylistDialog(
      context,
      playlist,
      repository: _collections,
    );
    if (updated == null) return;
    await _reload();
  }

  /// Deletes at once and offers 撤销 (D-064): the list is rebuilt with
  /// its name, description and songs in order. No audio file is touched.
  Future<void> _deletePlaylist(LocalPlaylist playlist) async {
    final messenger = ScaffoldMessenger.of(context);
    var deleted = false;
    await _withWork(() async {
      await _collections.deletePlaylist(playlist.id);
      deleted = true;
      if (mounted) setState(() => _selectedPlaylistId = null);
      await _reload();
    });
    if (!deleted) return;
    showUndoSnackBar(
      messenger,
      message: '已删除播放列表“${playlist.name}”（音频文件不受影响）',
      onUndo: () async {
        final restored = await _collections.createPlaylist(
          playlist.name,
          description: playlist.description,
        );
        if (playlist.sourcePaths.isNotEmpty) {
          await _collections.addToPlaylist(restored.id, playlist.sourcePaths);
        }
        if (mounted) {
          setState(() => _selectedPlaylistId = restored.id);
          await _reload();
        }
        return '播放列表已恢复';
      },
    );
  }

  Future<void> _addCurrentToPlaylist(LocalPlaylist playlist) async {
    final current = _session.currentState.currentItem;
    if (current == null || current.projectId != null) return;
    await _withWork(() async {
      await _collections.addToPlaylist(playlist.id, [
        current.audioAsset.originalPath,
      ]);
      await _reload();
    });
  }

  Future<void> _removeFromPlaylist(
    LocalPlaylist playlist,
    LocalCollectionSong song,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final position = playlist.sourcePaths.indexOf(song.sourcePath);
    var removed = false;
    await _withWork(() async {
      await _collections.removeFromPlaylist(playlist.id, song.sourcePath);
      removed = true;
      await _reload();
    });
    if (!removed) return;
    showUndoSnackBar(
      messenger,
      message: '已从“${playlist.name}”移除“${song.title}”',
      onUndo: () async {
        final updated = await _collections.addToPlaylist(playlist.id, [
          song.sourcePath,
        ]);
        final last = updated.sourcePaths.length - 1;
        if (position >= 0 && position < last) {
          await _collections.moveInPlaylist(playlist.id, last, position);
        }
        if (mounted) await _reload();
        return null;
      },
    );
  }

  Future<void> _moveInPlaylist(
    LocalPlaylist playlist,
    int oldIndex,
    int newIndex,
  ) async {
    // [ReorderableListView.onReorderItem] already gives the index after the
    // moved song is taken out of the list.
    if (newIndex == oldIndex) return;
    await _withWork(() async {
      await _collections.moveInPlaylist(playlist.id, oldIndex, newIndex);
      await _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final title = widget.view == LocalCollectionView.favorites ? '已收藏' : '播放列表';

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        title: Text(title),
        actions: [
          if (spec.isCompact && widget.view == LocalCollectionView.playlists)
            PopupMenuButton<String>(
              tooltip: '播放列表操作',
              onSelected: (value) {
                if (value == 'create') unawaited(_createPlaylist());
                if (value == 'refresh') unawaited(_reload());
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'create',
                  child: ListTile(
                    leading: Icon(Icons.playlist_add_rounded),
                    title: Text('新建播放列表'),
                  ),
                ),
                PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: Icon(Icons.refresh_rounded),
                    title: Text('刷新'),
                  ),
                ),
              ],
            )
          else ...[
            if (widget.view == LocalCollectionView.playlists)
              IconButton(
                tooltip: '新建播放列表',
                onPressed: _working ? null : _createPlaylist,
                icon: const Icon(Icons.playlist_add_rounded),
              ),
            IconButton(
              tooltip: '刷新',
              onPressed: _working ? null : _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          SizedBox(width: spec.isCompact ? 0 : AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          if (_working) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spec.pageGutter,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                _error!,
                style: TextStyle(color: AppColors.errorText),
              ),
            ),
          Expanded(
            child: _loading
                ? const AppLoadingState()
                : widget.view == LocalCollectionView.favorites
                ? _buildFavorites(spec)
                : _buildPlaylists(spec),
          ),
        ],
      ),
    );
  }

  Widget _buildFavorites(AppLayoutSpec spec) {
    final songs = _favoriteSongs;
    if (songs.isEmpty) {
      return const CollectionEmptyState(
        icon: Icons.favorite_border_rounded,
        title: '还没有收藏歌曲',
        message: '播放本地音乐时点击心形按钮，歌曲会出现在这里。',
      );
    }

    final playableCount = songs
        .where((song) => song.playbackItem != null)
        .length;
    return Column(
      children: [
        CollectionHero(
          icon: Icons.favorite_rounded,
          title: '喜欢的歌曲',
          subtitle: '${songs.length} 首 · $playableCount 首当前可播放',
          primaryLabel: '播放全部',
          onPrimary: playableCount == 0 ? null : () => _playSongs(songs),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              spec.pageGutter,
              0,
              spec.pageGutter,
              spec.sectionGap,
            ),
            itemCount: songs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 2),
            itemBuilder: (context, index) {
              final song = songs[index];
              return LocalCollectionSongTile(
                song: song,
                dependencies: widget.dependencies,
                onTap: song.playbackItem == null
                    ? null
                    : () => _playSongs(songs, requestedIndex: index),
                trailing: FavoriteCollectionSongActions(
                  compact: spec.isCompactOrMedium,
                  canPlay: song.playbackItem != null,
                  onEnqueue: () => _enqueue(song),
                  onRemoveFavorite: () => _removeFavorite(song),
                  onAddToPlaylist: () => _addFavoriteToPlaylist(song),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylists(AppLayoutSpec spec) {
    final selected = _selectedPlaylist;
    if (selected != null) return _buildPlaylistDetail(selected, spec);

    if (_playlists.isEmpty) {
      return CollectionEmptyState(
        icon: Icons.queue_music_rounded,
        title: '建立你的第一个播放列表',
        message: '播放列表只保存本地歌曲引用，不会复制、移动或修改原音频文件。',
        actionLabel: '新建播放列表',
        onAction: _createPlaylist,
      );
    }

    return GridView.builder(
      padding: EdgeInsets.all(spec.pageGutter),
      gridDelegate: AppCatalogCard.gridDelegateFor(spec),
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final playlist = _playlists[index];
        final songs = playlist.sourcePaths.map(_song).toList(growable: false);
        final missing = songs.where((song) => song.playbackItem == null).length;
        final artwork = songs
            .map((song) => song.artworkPath)
            .whereType<String>()
            .firstOrNull;

        return LocalPlaylistCard(
          playlist: playlist,
          artworkPath: artwork,
          missing: missing,
          onOpen: () => setState(() => _selectedPlaylistId = playlist.id),
          onRename: () => _renamePlaylist(playlist),
          onDelete: () => _deletePlaylist(playlist),
        );
      },
    );
  }

  Widget _buildPlaylistDetail(LocalPlaylist playlist, AppLayoutSpec spec) {
    final songs = playlist.sourcePaths.map(_song).toList(growable: false);
    final playableCount = songs
        .where((song) => song.playbackItem != null)
        .length;
    final current = _session.currentState.currentItem;
    final canAddCurrent = current != null && current.projectId == null;

    return Column(
      children: [
        PlaylistDetailHeader(
          name: playlist.name,
          subtitle: '${songs.length} 首歌曲 · $playableCount 首当前可播放',
          canPlay: playableCount > 0,
          canAddCurrent: canAddCurrent,
          onBack: () => setState(() => _selectedPlaylistId = null),
          onPlay: () => _playSongs(songs),
          onAddCurrent: () => _addCurrentToPlaylist(playlist),
          onRename: () => _renamePlaylist(playlist),
          onDelete: () => _deletePlaylist(playlist),
        ),
        const Divider(height: 1),
        Expanded(
          child: songs.isEmpty
              ? const CollectionEmptyState(
                  icon: Icons.music_note_rounded,
                  title: '这个播放列表还是空的',
                  message: '播放一首本地歌曲后，可以使用“加入当前歌曲”。',
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.fromLTRB(
                    spec.pageGutter,
                    AppSpacing.sm,
                    spec.pageGutter,
                    spec.sectionGap,
                  ),
                  itemCount: songs.length,
                  onReorderItem: (oldIndex, newIndex) =>
                      _moveInPlaylist(playlist, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return Container(
                      key: ValueKey('${playlist.id}:${song.sourcePath}'),
                      child: LocalCollectionSongTile(
                        song: song,
                        dependencies: widget.dependencies,
                        leadingIndex: index + 1,
                        onTap: song.playbackItem == null
                            ? null
                            : () => _playSongs(songs, requestedIndex: index),
                        trailing: PlaylistCollectionSongActions(
                          index: index,
                          compact: spec.isCompactOrMedium,
                          canPlay: song.playbackItem != null,
                          onEnqueue: () => _enqueue(song),
                          onRemove: () => _removeFromPlaylist(playlist, song),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
