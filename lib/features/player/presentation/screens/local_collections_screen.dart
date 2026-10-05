import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/models/local_playlist.dart';
import '../../domain/repositories/local_media_collection_repository.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/local_collection_actions.dart';

enum LocalCollectionView { favorites, playlists }

class LocalCollectionsScreen extends StatefulWidget {
  final LocalCollectionView view;

  const LocalCollectionsScreen({
    super.key,
    required this.view,
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
    final services = ServiceLocatorGlobal.I;
    _collections = services.localMediaCollectionRepository;
    _library = services.localMediaLibraryRepository;
    _metadata = services.localMediaMetadataRepository;
    _session = services.playbackSessionService;
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
        setState(() => _error = '收藏与播放列表加载失败：$error');
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
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  _CollectionSong _song(String sourcePath) {
    final key = _pathKey(sourcePath);
    return _CollectionSong(
      sourcePath: sourcePath,
      entry: _entryByPath[key],
      override: _metadataByPath[key],
    );
  }

  List<_CollectionSong> get _favoriteSongs {
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
    List<_CollectionSong> songs, {
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
    final startIndex =
        playableBeforeRequested.clamp(0, playable.length - 1).toInt();
    await _session.setQueue(playable, startIndex: startIndex);
  }

  Future<void> _enqueue(_CollectionSong song) async {
    final item = song.playbackItem;
    if (item == null) return;
    await _session.enqueue(item);
  }

  Future<void> _removeFavorite(_CollectionSong song) async {
    await _withWork(() async {
      await _collections.setFavorite(song.sourcePath, false);
      await _reload();
    });
  }

  Future<void> _addFavoriteToPlaylist(_CollectionSong song) async {
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

  Future<void> _deletePlaylist(LocalPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除播放列表？'),
        content: Text('只会删除“${playlist.name}”这个列表，不会删除任何音频文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _withWork(() async {
      await _collections.deletePlaylist(playlist.id);
      if (mounted) setState(() => _selectedPlaylistId = null);
      await _reload();
    });
  }

  Future<void> _addCurrentToPlaylist(LocalPlaylist playlist) async {
    final current = _session.currentState.currentItem;
    if (current == null || current.projectId != null) return;
    await _withWork(() async {
      await _collections.addToPlaylist(
        playlist.id,
        [current.audioAsset.originalPath],
      );
      await _reload();
    });
  }

  Future<void> _removeFromPlaylist(
    LocalPlaylist playlist,
    _CollectionSong song,
  ) async {
    await _withWork(() async {
      await _collections.removeFromPlaylist(playlist.id, song.sourcePath);
      await _reload();
    });
  }

  Future<void> _moveInPlaylist(
    LocalPlaylist playlist,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    await _withWork(() async {
      await _collections.moveInPlaylist(playlist.id, oldIndex, newIndex);
      await _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final title =
        widget.view == LocalCollectionView.favorites ? '已收藏' : '播放列表';

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
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
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
      return const _CollectionEmptyState(
        icon: Icons.favorite_border_rounded,
        title: '还没有收藏歌曲',
        message: '播放本地音乐时点击心形按钮，歌曲会出现在这里。',
      );
    }

    final playableCount =
        songs.where((song) => song.playbackItem != null).length;
    return Column(
      children: [
        _CollectionHero(
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
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final song = songs[index];
              return _CollectionSongTile(
                song: song,
                onTap: song.playbackItem == null
                    ? null
                    : () => _playSongs(songs, requestedIndex: index),
                trailing: _FavoriteActions(
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
      return _CollectionEmptyState(
        icon: Icons.queue_music_rounded,
        title: '建立你的第一个播放列表',
        message: '播放列表只保存本地歌曲引用，不会复制、移动或修改原音频文件。',
        actionLabel: '新建播放列表',
        onAction: _createPlaylist,
      );
    }

    final columns = spec.gridColumns(
      minTileWidth: 240,
      min: 1,
      max: spec.isExtraLarge ? 5 : 4,
    );
    final cardHeight = spec.isCompact
        ? 190.0
        : spec.isMedium
            ? 205.0
            : 220.0;

    return GridView.builder(
      padding: EdgeInsets.all(spec.pageGutter),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: cardHeight,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final playlist = _playlists[index];
        final songs = playlist.sourcePaths.map(_song).toList(growable: false);
        final missing =
            songs.where((song) => song.playbackItem == null).length;
        final artwork = songs
            .map((song) => song.artworkPath)
            .whereType<String>()
            .firstOrNull;

        return _PlaylistCard(
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

  Widget _buildPlaylistDetail(
    LocalPlaylist playlist,
    AppLayoutSpec spec,
  ) {
    final songs = playlist.sourcePaths.map(_song).toList(growable: false);
    final playableCount =
        songs.where((song) => song.playbackItem != null).length;
    final current = _session.currentState.currentItem;
    final canAddCurrent = current != null && current.projectId == null;

    return Column(
      children: [
        _PlaylistDetailHeader(
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
              ? const _CollectionEmptyState(
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
                  onReorder: (oldIndex, newIndex) =>
                      _moveInPlaylist(playlist, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return Container(
                      key: ValueKey('${playlist.id}:${song.sourcePath}'),
                      child: _CollectionSongTile(
                        song: song,
                        leadingIndex: index + 1,
                        onTap: song.playbackItem == null
                            ? null
                            : () => _playSongs(
                                  songs,
                                  requestedIndex: index,
                                ),
                        trailing: _PlaylistSongActions(
                          index: index,
                          compact: spec.isCompactOrMedium,
                          canPlay: song.playbackItem != null,
                          onEnqueue: () => _enqueue(song),
                          onRemove: () =>
                              _removeFromPlaylist(playlist, song),
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

class _FavoriteActions extends StatelessWidget {
  final bool compact;
  final bool canPlay;
  final VoidCallback onEnqueue;
  final VoidCallback onRemoveFavorite;
  final VoidCallback onAddToPlaylist;

  const _FavoriteActions({
    required this.compact,
    required this.canPlay,
    required this.onEnqueue,
    required this.onRemoveFavorite,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return PopupMenuButton<String>(
        tooltip: '歌曲操作',
        onSelected: (value) {
          if (value == 'queue' && canPlay) onEnqueue();
          if (value == 'unfavorite') onRemoveFavorite();
          if (value == 'playlist') onAddToPlaylist();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'queue',
            enabled: canPlay,
            child: const Text('加入播放队列'),
          ),
          const PopupMenuItem(
            value: 'playlist',
            child: Text('加入播放列表'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'unfavorite',
            child: Text('取消收藏'),
          ),
        ],
      );
    }

    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        IconButton(
          tooltip: '加入播放队列',
          onPressed: canPlay ? onEnqueue : null,
          icon: const Icon(Icons.queue_music_rounded),
        ),
        IconButton(
          tooltip: '取消收藏',
          onPressed: onRemoveFavorite,
          icon: const Icon(Icons.favorite_rounded),
        ),
        IconButton(
          tooltip: '加入播放列表',
          onPressed: onAddToPlaylist,
          icon: const Icon(Icons.playlist_add_rounded),
        ),
      ],
    );
  }
}

class _PlaylistSongActions extends StatelessWidget {
  final int index;
  final bool compact;
  final bool canPlay;
  final VoidCallback onEnqueue;
  final VoidCallback onRemove;

  const _PlaylistSongActions({
    required this.index,
    required this.compact,
    required this.canPlay,
    required this.onEnqueue,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final dragHandle = Tooltip(
      message: '拖动排序',
      child: ReorderableDragStartListener(
        index: index,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.drag_handle_rounded),
        ),
      ),
    );

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: '歌曲操作',
            onSelected: (value) {
              if (value == 'queue' && canPlay) onEnqueue();
              if (value == 'remove') onRemove();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'queue',
                enabled: canPlay,
                child: const Text('加入播放队列'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'remove',
                child: Text('从播放列表移除'),
              ),
            ],
          ),
          dragHandle,
        ],
      );
    }

    return Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: '加入播放队列',
          onPressed: canPlay ? onEnqueue : null,
          icon: const Icon(Icons.queue_music_rounded),
        ),
        IconButton(
          tooltip: '从播放列表移除',
          onPressed: onRemove,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        dragHandle,
      ],
    );
  }
}

class _CollectionSong {
  final String sourcePath;
  final LocalMediaLibraryEntry? entry;
  final LocalMediaMetadata? override;

  const _CollectionSong({
    required this.sourcePath,
    required this.entry,
    required this.override,
  });

  String get fileName => sourcePath.split(Platform.pathSeparator).last;

  String get fallbackTitle => fileName.replaceAll(
        RegExp(
          r'\.(mp3|flac|wav|m4a|aac|ogg)$',
          caseSensitive: false,
        ),
        '',
      );

  String get embeddedTitle => entry?.embeddedTitle?.trim().isNotEmpty == true
      ? entry!.embeddedTitle!
      : fallbackTitle;

  String get title => override?.resolvedTitle(embeddedTitle) ?? embeddedTitle;

  String? get artist =>
      override?.resolvedArtist(entry?.embeddedArtist) ?? entry?.embeddedArtist;

  String? get album =>
      override?.resolvedAlbum(entry?.embeddedAlbum) ?? entry?.embeddedAlbum;

  String? get artworkPath =>
      override?.resolvedArtwork(entry?.embeddedArtworkPath) ??
      entry?.embeddedArtworkPath;

  bool get sourceExists => File(sourcePath).existsSync();

  bool get canPlay => entry?.isMissing != true && sourceExists;

  String get format {
    if (entry?.format.trim().isNotEmpty == true) return entry!.format;
    final dot = sourcePath.lastIndexOf('.');
    return dot < 0 ? '' : sourcePath.substring(dot + 1).toLowerCase();
  }

  String get secondary {
    if (!canPlay) return '文件不可用 · 引用仍保留';
    return [
      if (artist?.trim().isNotEmpty == true) artist!,
      if (album?.trim().isNotEmpty == true) album!,
      if (format.isNotEmpty) format.toUpperCase(),
    ].join(' · ');
  }

  PlaybackItem? get playbackItem {
    if (!canPlay) return null;
    return PlaybackItem(
      id: 'local:$sourcePath',
      title: title,
      artist: artist,
      artworkPath: artworkPath,
      hasLyrics: override?.metadata['linkedProjectId'] is String,
      audioAsset: AudioAsset(
        originalPath: sourcePath,
        format: format,
        thumbnailPath: artworkPath,
      ),
      preferredSource: AudioSourceType.original,
    );
  }
}

class _CollectionHero extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback? onPrimary;

  const _CollectionHero({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final compact = spec.isCompactOrMedium || spec.isShort;
    final extent = spec.isCompact ? 56.0 : 72.0;
    final button = FilledButton.icon(
      onPressed: onPrimary,
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(primaryLabel),
      style: FilledButton.styleFrom(
        minimumSize: Size(0, spec.minimumInteractiveExtent),
      ),
    );

    return Padding(
      padding: EdgeInsets.all(spec.pageGutter),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(
          spec.isCompact ? AppSpacing.md : AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          border: Border.all(color: AppColors.borderMuted),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _HeroIcon(icon: icon, extent: extent),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _HeroText(
                          title: title,
                          subtitle: subtitle,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(width: double.infinity, child: button),
                ],
              )
            : Row(
                children: [
                  _HeroIcon(icon: icon, extent: extent),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _HeroText(
                      title: title,
                      subtitle: subtitle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  button,
                ],
              ),
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  final IconData icon;
  final double extent;

  const _HeroIcon({
    required this.icon,
    required this.extent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: extent,
      height: extent,
      decoration: BoxDecoration(
        color: AppColors.bgHighlight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Icon(icon, size: extent * 0.52),
    );
  }
}

class _HeroText extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool compact;

  const _HeroText({
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (compact
                  ? Theme.of(context).textTheme.titleLarge
                  : Theme.of(context).textTheme.headlineSmall)
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _PlaylistDetailHeader extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool canPlay;
  final bool canAddCurrent;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onAddCurrent;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _PlaylistDetailHeader({
    required this.name,
    required this.subtitle,
    required this.canPlay,
    required this.canAddCurrent,
    required this.onBack,
    required this.onPlay,
    required this.onAddCurrent,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final compact = spec.isCompactOrMedium || spec.isShort;

    final menu = PopupMenuButton<String>(
      tooltip: '播放列表操作',
      onSelected: (value) {
        if (value == 'rename') onRename();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('重命名')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('删除播放列表')),
      ],
    );

    final playButton = FilledButton.icon(
      onPressed: canPlay ? onPlay : null,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('播放'),
      style: FilledButton.styleFrom(
        minimumSize: Size(0, spec.minimumInteractiveExtent),
      ),
    );
    final addButton = OutlinedButton.icon(
      onPressed: canAddCurrent ? onAddCurrent : null,
      icon: const Icon(Icons.add_rounded),
      label: const Text('加入当前歌曲'),
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, spec.minimumInteractiveExtent),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: spec.minimumInteractiveExtent,
                      height: spec.minimumInteractiveExtent,
                      child: IconButton(
                        tooltip: '返回播放列表',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _PlaylistTitleBlock(
                        name: name,
                        subtitle: subtitle,
                        compact: true,
                      ),
                    ),
                    menu,
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: playButton),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: addButton),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                IconButton(
                  tooltip: '返回播放列表',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _PlaylistTitleBlock(
                    name: name,
                    subtitle: subtitle,
                  ),
                ),
                playButton,
                const SizedBox(width: AppSpacing.sm),
                addButton,
                menu,
              ],
            ),
    );
  }
}

class _PlaylistTitleBlock extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool compact;

  const _PlaylistTitleBlock({
    required this.name,
    required this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (compact
                  ? Theme.of(context).textTheme.titleLarge
                  : Theme.of(context).textTheme.headlineSmall)
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _CollectionSongTile extends StatelessWidget {
  final _CollectionSong song;
  final VoidCallback? onTap;
  final Widget trailing;
  final int? leadingIndex;

  const _CollectionSongTile({
    required this.song,
    required this.onTap,
    required this.trailing,
    this.leadingIndex,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final artworkExtent = spec.isCompact ? 44.0 : 48.0;
    final leadingWidth =
        artworkExtent + (leadingIndex == null ? 0 : 28.0);

    return ListTile(
      onTap: onTap,
      enabled: song.canPlay,
      minVerticalPadding: AppSpacing.xs,
      contentPadding: EdgeInsets.symmetric(
        horizontal: spec.isCompact ? AppSpacing.xs : AppSpacing.sm,
      ),
      leading: SizedBox(
        width: leadingWidth,
        child: Row(
          children: [
            if (leadingIndex != null)
              SizedBox(
                width: 24,
                child: Text(
                  '$leadingIndex',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textTertiary),
                ),
              ),
            SizedBox(
              width: artworkExtent,
              height: artworkExtent,
              child: _CollectionArtwork(path: song.artworkPath),
            ),
          ],
        ),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song.secondary,
        maxLines: spec.isCompact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final LocalPlaylist playlist;
  final String? artworkPath;
  final int missing;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _PlaylistCard({
    required this.playlist,
    required this.artworkPath,
    required this.missing,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: Container(
        padding: EdgeInsets.all(
          spec.isCompact ? AppSpacing.sm : AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          border: Border.all(color: AppColors.borderMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CollectionArtwork(path: artworkPath, large: true),
                  Align(
                    alignment: Alignment.topRight,
                    child: Material(
                      color: AppColors.pureBlack.withAlpha(90),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusCircular),
                      child: PopupMenuButton<String>(
                        tooltip: '播放列表操作',
                        onSelected: (value) {
                          if (value == 'rename') onRename();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('重命名'),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('删除播放列表'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              [
                '${playlist.sourcePaths.length} 首歌曲',
                if (missing > 0) '$missing 首不可用',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    missing > 0 ? AppColors.error : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionArtwork extends StatelessWidget {
  final String? path;
  final bool large;

  const _CollectionArtwork({
    this.path,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    return ClipRRect(
      borderRadius:
          BorderRadius.circular(large ? AppSpacing.radiusLarge : 8),
      child: Container(
        color: AppColors.bgSurface,
        alignment: Alignment.center,
        child: file?.existsSync() == true
            ? Image.file(
                file!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              )
            : Icon(
                Icons.music_note_rounded,
                size: large ? 54 : 24,
                color: AppColors.textTertiary,
              ),
      ),
    );
  }
}

class _CollectionEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CollectionEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: EdgeInsets.all(spec.pageGutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: spec.isCompact ? 52 : 68,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: (spec.isCompact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(actionLabel!),
                  style: FilledButton.styleFrom(
                    minimumSize:
                        Size(0, spec.minimumInteractiveExtent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
