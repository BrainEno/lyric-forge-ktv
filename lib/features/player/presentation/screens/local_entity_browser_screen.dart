import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../data/services/local_media_catalog_builder.dart';
import '../../domain/models/local_media_catalog.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/local_collection_actions.dart';

enum LocalEntityBrowserKind { artists, albums }

class LocalEntityBrowserScreen extends StatefulWidget {
  final LocalEntityBrowserKind kind;

  const LocalEntityBrowserScreen({
    super.key,
    required this.kind,
  });

  @override
  State<LocalEntityBrowserScreen> createState() =>
      _LocalEntityBrowserScreenState();
}

class _LocalEntityBrowserScreenState extends State<LocalEntityBrowserScreen> {
  static const _catalogBuilder = LocalMediaCatalogBuilder();

  late final LocalMediaLibraryRepository _library;
  late final LocalMediaMetadataRepository _metadata;
  late final PlaybackSessionService _session;
  final _searchController = TextEditingController();

  LocalMediaCatalog _catalog = LocalMediaCatalog.empty;
  String _query = '';
  String? _selectedKey;
  bool _loading = true;
  String? _error;

  bool get _isArtists => widget.kind == LocalEntityBrowserKind.artists;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _library = services.localMediaLibraryRepository;
    _metadata = services.localMediaMetadataRepository;
    _session = services.playbackSessionService;
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant LocalEntityBrowserScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _selectedKey = null;
      _query = '';
      _searchController.clear();
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _key(String value) => value.trim().toLowerCase();

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final entries = await _library.getAll();
      final overrides = await _metadata.getAll();
      final catalog = _catalogBuilder.build(
        entries: entries,
        overrides: overrides,
      );
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        if (_selectedKey != null && !_selectionStillExists(catalog)) {
          _selectedKey = null;
        }
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '本地音乐目录加载失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _selectionStillExists(LocalMediaCatalog catalog) {
    final selected = _selectedKey;
    if (selected == null) return true;
    if (_isArtists) {
      return catalog.artists.any((item) => _key(item.name) == selected);
    }
    return catalog.albums.any((item) => _key(item.title) == selected);
  }

  LocalArtistGroup? get _selectedArtist {
    if (!_isArtists) return null;
    final selected = _selectedKey;
    if (selected == null) return null;
    for (final artist in _catalog.artists) {
      if (_key(artist.name) == selected) return artist;
    }
    return null;
  }

  LocalAlbumGroup? get _selectedAlbum {
    if (_isArtists) return null;
    final selected = _selectedKey;
    if (selected == null) return null;
    for (final album in _catalog.albums) {
      if (_key(album.title) == selected) return album;
    }
    return null;
  }

  List<LocalArtistGroup> get _visibleArtists {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _catalog.artists;
    return _catalog.artists
        .where(
          (artist) =>
              artist.name.toLowerCase().contains(query) ||
              artist.albums.any((album) => album.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  List<LocalAlbumGroup> get _visibleAlbums {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _catalog.albums;
    return _catalog.albums
        .where(
          (album) =>
              album.title.toLowerCase().contains(query) ||
              album.artists.any((artist) => artist.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  PlaybackItem? _toPlaybackItem(LocalCatalogTrack track) {
    if (!track.canPlay) return null;
    return PlaybackItem(
      id: 'local:${track.sourcePath}',
      title: track.title,
      artist: track.artist,
      artworkPath: track.artworkPath,
      hasLyrics: track.hasLyrics,
      audioAsset: AudioAsset(
        originalPath: track.sourcePath,
        format: track.format,
        thumbnailPath: track.artworkPath,
      ),
      preferredSource: AudioSourceType.original,
    );
  }

  Future<void> _playTracks(
    List<LocalCatalogTrack> tracks, {
    int requestedIndex = 0,
  }) async {
    final playable = <PlaybackItem>[];
    var playableBeforeRequested = 0;
    for (var i = 0; i < tracks.length; i++) {
      final item = _toPlaybackItem(tracks[i]);
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

  Future<void> _enqueue(LocalCatalogTrack track) async {
    final item = _toPlaybackItem(track);
    if (item != null) await _session.enqueue(item);
  }

  @override
  Widget build(BuildContext context) {
    final artist = _selectedArtist;
    final album = _selectedAlbum;
    final selected = artist != null || album != null;
    final sectionTitle = _isArtists ? '艺人' : '专辑';

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        leading: selected
            ? IconButton(
                tooltip: '返回$sectionTitle',
                onPressed: () => setState(() => _selectedKey = null),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: Text(selected ? (artist?.name ?? album!.title) : sectionTitle),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          Expanded(
            child: _loading && _catalog.tracks.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : artist != null
                    ? _buildArtistDetail(artist)
                    : album != null
                        ? _buildAlbumDetail(album)
                        : _buildBrowser(),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowser() {
    final artists = _visibleArtists;
    final albums = _visibleAlbums;
    final count = _isArtists ? artists.length : albums.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: _isArtists ? '搜索艺人或专辑' : '搜索专辑或艺人',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Expanded(
          child: count == 0
              ? _EntityEmptyState(
                  kind: widget.kind,
                  hasCatalog: _catalog.tracks.isNotEmpty,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final maxExtent = constraints.maxWidth < 600 ? 220.0 : 250.0;
                    return GridView.builder(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxExtent,
                        mainAxisExtent: 290,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisSpacing: AppSpacing.md,
                      ),
                      itemCount: count,
                      itemBuilder: (context, index) {
                        if (_isArtists) {
                          final artist = artists[index];
                          return _EntityCard(
                            circularArtwork: true,
                            artworkPath: artist.artworkPath,
                            title: artist.name,
                            subtitle: [
                              '${artist.tracks.length} 首歌曲',
                              if (artist.albums.isNotEmpty)
                                '${artist.albums.length} 张专辑',
                            ].join(' · '),
                            onTap: () => setState(
                              () => _selectedKey = _key(artist.name),
                            ),
                          );
                        }
                        final album = albums[index];
                        return _EntityCard(
                          artworkPath: album.artworkPath,
                          title: album.title,
                          subtitle: [
                            album.artistLabel,
                            if (album.year != null) '${album.year}',
                            '${album.tracks.length} 首',
                          ].join(' · '),
                          onTap: () => setState(
                            () => _selectedKey = _key(album.title),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildArtistDetail(LocalArtistGroup artist) {
    return _EntityDetail(
      artworkPath: artist.artworkPath,
      circularArtwork: true,
      title: artist.name,
      subtitle: [
        '${artist.tracks.length} 首歌曲',
        if (artist.albums.isNotEmpty) '${artist.albums.length} 张专辑',
        if (artist.availableTrackCount != artist.tracks.length)
          '${artist.availableTrackCount} 首当前可播放',
      ].join(' · '),
      tracks: artist.tracks,
      onPlayAll: artist.availableTrackCount == 0
          ? null
          : () => _playTracks(artist.tracks),
      onPlayTrack: (index) => _playTracks(
        artist.tracks,
        requestedIndex: index,
      ),
      onEnqueue: _enqueue,
    );
  }

  Widget _buildAlbumDetail(LocalAlbumGroup album) {
    return _EntityDetail(
      artworkPath: album.artworkPath,
      title: album.title,
      subtitle: [
        album.artistLabel,
        if (album.year != null) '${album.year}',
        '${album.tracks.length} 首歌曲',
        if (album.availableTrackCount != album.tracks.length)
          '${album.availableTrackCount} 首当前可播放',
      ].join(' · '),
      tracks: album.tracks,
      onPlayAll: album.availableTrackCount == 0
          ? null
          : () => _playTracks(album.tracks),
      onPlayTrack: (index) => _playTracks(
        album.tracks,
        requestedIndex: index,
      ),
      onEnqueue: _enqueue,
    );
  }
}

class _EntityCard extends StatelessWidget {
  final String? artworkPath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool circularArtwork;

  const _EntityCard({
    required this.artworkPath,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.circularArtwork = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _EntityArtwork(
                    path: artworkPath,
                    circular: circularArtwork,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntityDetail extends StatelessWidget {
  final String? artworkPath;
  final bool circularArtwork;
  final String title;
  final String subtitle;
  final List<LocalCatalogTrack> tracks;
  final VoidCallback? onPlayAll;
  final ValueChanged<int> onPlayTrack;
  final ValueChanged<LocalCatalogTrack> onEnqueue;

  const _EntityDetail({
    required this.artworkPath,
    required this.title,
    required this.subtitle,
    required this.tracks,
    required this.onPlayAll,
    required this.onPlayTrack,
    required this.onEnqueue,
    this.circularArtwork = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 680;
              final artwork = SizedBox(
                width: compact ? 120 : 164,
                height: compact ? 120 : 164,
                child: _EntityArtwork(
                  path: artworkPath,
                  circular: circularArtwork,
                ),
              );
              final copy = Column(
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: onPlayAll,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('播放全部'),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  children: [
                    artwork,
                    const SizedBox(height: AppSpacing.md),
                    copy,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  artwork,
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: copy),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final track = tracks[index];
              return ListTile(
                enabled: track.canPlay,
                onTap: track.canPlay ? () => onPlayTrack(index) : null,
                leading: SizedBox(
                  width: 42,
                  child: Center(
                    child: Text(
                      track.trackNumber?.toString() ?? '${index + 1}',
                      style: TextStyle(
                        color: track.canPlay
                            ? AppColors.textTertiary
                            : AppColors.error,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.canPlay
                      ? [
                          if (track.artist?.trim().isNotEmpty == true)
                            track.artist!,
                          if (track.album?.trim().isNotEmpty == true) track.album!,
                          if (track.year != null) '${track.year}',
                          if (track.hasLyrics) '有歌词',
                        ].join(' · ')
                      : '文件不可用',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: track.canPlay
                    ? Wrap(
                        spacing: AppSpacing.xs,
                        children: [
                          LocalFavoriteButton(sourcePath: track.sourcePath),
                          IconButton(
                            tooltip: '加入播放列表',
                            onPressed: () async {
                              await showAddToLocalPlaylistDialog(
                                context,
                                sourcePath: track.sourcePath,
                                title: track.title,
                              );
                            },
                            icon: const Icon(Icons.playlist_add_rounded),
                          ),
                          IconButton(
                            tooltip: '加入播放队列',
                            onPressed: () => onEnqueue(track),
                            icon: const Icon(Icons.queue_music_rounded),
                          ),
                        ],
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EntityArtwork extends StatelessWidget {
  final String? path;
  final bool circular;

  const _EntityArtwork({
    required this.path,
    required this.circular,
  });

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final image = Container(
      color: AppColors.bgSurface,
      alignment: Alignment.center,
      child: file?.existsSync() == true
          ? Image.file(
              file!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            )
          : const Icon(
              Icons.music_note_rounded,
              size: 58,
              color: AppColors.textTertiary,
            ),
    );
    if (circular) return ClipOval(child: image);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: image,
    );
  }
}

class _EntityEmptyState extends StatelessWidget {
  final LocalEntityBrowserKind kind;
  final bool hasCatalog;

  const _EntityEmptyState({
    required this.kind,
    required this.hasCatalog,
  });

  @override
  Widget build(BuildContext context) {
    final artists = kind == LocalEntityBrowserKind.artists;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                artists ? Icons.person_outline_rounded : Icons.album_outlined,
                size: 68,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                hasCatalog
                    ? (artists ? '没有匹配的艺人' : '没有匹配的专辑')
                    : (artists ? '还没有可浏览的艺人' : '还没有可浏览的专辑'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                hasCatalog
                    ? '换一个搜索词试试。'
                    : '导入带有音频标签的本地歌曲，或在歌曲资料里补充${artists ? '艺人' : '专辑'}信息。',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
