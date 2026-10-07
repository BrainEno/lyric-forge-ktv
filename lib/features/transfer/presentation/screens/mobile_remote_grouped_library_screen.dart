import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/local_media_library_entry.dart';
import '../../../player/domain/repositories/local_media_library_repository.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';
import 'remote_catalog_utils.dart';

enum RemoteCatalogView { artists, albums }

class MobileRemoteGroupedLibraryScreen extends StatefulWidget {
  final RemoteCatalogView view;

  const MobileRemoteGroupedLibraryScreen({
    super.key,
    required this.view,
  });

  @override
  State<MobileRemoteGroupedLibraryScreen> createState() =>
      _MobileRemoteGroupedLibraryScreenState();
}

class _MobileRemoteGroupedLibraryScreenState
    extends State<MobileRemoteGroupedLibraryScreen> {
  late final MediaHubClientService _client;
  late final LocalMediaLibraryRepository _localLibrary;
  late final PlaybackSessionService _session;
  final TextEditingController _searchController = TextEditingController();

  List<RemoteAudioTrack> _tracks = const <RemoteAudioTrack>[];
  Map<String, LocalMediaLibraryEntry> _localEntries = const {};
  bool _loading = false;
  String? _error;

  RemoteCatalogGrouping get _grouping => widget.view == RemoteCatalogView.artists
      ? RemoteCatalogGrouping.artists
      : RemoteCatalogGrouping.albums;

  String get _title =>
      widget.view == RemoteCatalogView.artists ? '艺人' : '专辑';

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _client = services.mediaHubClientService;
    _localLibrary = services.localMediaLibraryRepository;
    _session = services.playbackSessionService;
    _searchController.addListener(_onSearchChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (_loading) return;
    if (!_client.isConnected) {
      if (mounted) {
        setState(() {
          _tracks = const <RemoteAudioTrack>[];
          _localEntries = const {};
          _error = null;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tracks = await _client.fetchTracks();
      final entries = await _localLibrary.getAll();
      final localByTrack = <String, LocalMediaLibraryEntry>{};
      for (final track in tracks) {
        for (final entry in entries) {
          if (!entry.isMissing && remoteTrackMatchesDownloadedEntry(track, entry)) {
            localByTrack[track.id] = entry;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _localEntries = Map.unmodifiable(localByTrack);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '读取桌面音乐库失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<RemoteAudioTrack> get _visibleTracks {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _tracks;
    return _tracks.where((track) {
      return track.title.toLowerCase().contains(query) ||
          (track.artist?.toLowerCase().contains(query) ?? false) ||
          (track.album?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  PlaybackItem _itemFor(RemoteAudioTrack track) {
    final local = _localEntries[track.id];
    if (local != null && File(local.sourcePath).existsSync()) {
      return PlaybackItem(
        id: 'local:${local.sourcePath}',
        title: track.title,
        artist: track.artist,
        artworkPath: local.embeddedArtworkPath,
        hasLyrics: track.hasLyrics,
        audioAsset: AudioAsset(
          originalPath: local.sourcePath,
          format: track.format,
          duration: track.duration,
          thumbnailPath: local.embeddedArtworkPath,
          metadata: <String, dynamic>{
            'transferSource': 'media-hub',
            'remoteTrackId': track.id,
            if (track.album?.trim().isNotEmpty == true)
              'album': track.album!.trim(),
          },
        ),
      );
    }

    final uri = _client.playbackUriFor(track);
    final host = _client.currentConnection?.host ?? 'desktop';
    return PlaybackItem(
      id: 'remote:$host:${track.id}',
      title: track.title,
      artist: track.artist,
      hasLyrics: track.hasLyrics,
      streamUri: uri,
      audioAsset: AudioAsset(
        originalPath: uri.toString(),
        format: track.format,
        duration: track.duration,
        metadata: <String, dynamic>{
          'transferSource': 'media-hub-stream',
          'remoteTrackId': track.id,
          if (track.album?.trim().isNotEmpty == true)
            'album': track.album!.trim(),
        },
      ),
    );
  }

  Future<void> _playTracks(
    List<RemoteAudioTrack> tracks, {
    RemoteAudioTrack? start,
  }) async {
    if (tracks.isEmpty) return;
    final rawIndex = start == null
        ? 0
        : tracks.indexWhere((track) => track.id == start.id);
    final startIndex = rawIndex < 0 ? 0 : rawIndex;
    try {
      await _session.setQueue(
        tracks.map(_itemFor).toList(growable: false),
        startIndex: startIndex,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '播放失败：$error');
    }
  }

  String? _coverFor(List<RemoteAudioTrack> tracks) {
    for (final track in tracks) {
      final path = _localEntries[track.id]?.embeddedArtworkPath;
      if (path != null && File(path).existsSync()) return path;
    }
    return null;
  }

  Future<void> _openGroup(String name, List<RemoteAudioTrack> tracks) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.bgSurface,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.42,
          maxChildSize: 0.94,
          builder: (context, controller) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              '${tracks.length} 首歌曲',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _playTracks(tracks),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('播放全部'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      final local = _localEntries[track.id];
                      return ListTile(
                        onTap: () => _playTracks(tracks, start: track),
                        leading: _CatalogArtwork(
                          path: local?.embeddedArtworkPath,
                          icon: widget.view == RemoteCatalogView.artists
                              ? Icons.person_rounded
                              : Icons.album_rounded,
                          extent: 46,
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          widget.view == RemoteCatalogView.artists
                              ? (track.album?.trim().isNotEmpty == true
                                  ? track.album!
                                  : track.format.toUpperCase())
                              : (track.artist?.trim().isNotEmpty == true
                                  ? track.artist!
                                  : track.format.toUpperCase()),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: local == null
                            ? const Icon(
                                Icons.cloud_outlined,
                                size: 18,
                                color: AppColors.textTertiary,
                              )
                            : const Icon(
                                Icons.offline_pin_rounded,
                                size: 18,
                                color: AppColors.accent,
                              ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final groups = groupRemoteCatalog(_visibleTracks, _grouping);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        automaticallyImplyLeading: false,
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: !_client.isConnected
            ? const _DisconnectedCatalogState()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: EdgeInsets.all(layout.pageGutter),
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: widget.view == RemoteCatalogView.artists
                            ? '搜索艺人或歌曲'
                            : '搜索专辑、艺人或歌曲',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除',
                                onPressed: _searchController.clear,
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    if (_loading && _tracks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (groups.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Center(
                          child: Text(
                            '没有匹配内容',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: groups.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: layout.isCompact ? 2 : 3,
                          childAspectRatio: 0.82,
                          crossAxisSpacing: AppSpacing.sm,
                          mainAxisSpacing: AppSpacing.sm,
                        ),
                        itemBuilder: (context, index) {
                          final name = groups.keys.elementAt(index);
                          final tracks = groups[name]!;
                          return _CatalogGroupCard(
                            name: name,
                            count: tracks.length,
                            coverPath: _coverFor(tracks),
                            icon: widget.view == RemoteCatalogView.artists
                                ? Icons.person_rounded
                                : Icons.album_rounded,
                            onTap: () => _openGroup(name, tracks),
                          );
                        },
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _DisconnectedCatalogState extends StatelessWidget {
  const _DisconnectedCatalogState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.link_off_rounded,
              size: 52,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '请先在“歌曲”页连接电脑',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              '连接成功后，艺人和专辑会自动按桌面音乐库资料分组。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogGroupCard extends StatelessWidget {
  final String name;
  final int count;
  final String? coverPath;
  final IconData icon;
  final VoidCallback onTap;

  const _CatalogGroupCard({
    required this.name,
    required this.count,
    required this.coverPath,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CatalogArtwork(
                  path: coverPath,
                  icon: icon,
                  extent: double.infinity,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                '$count 首',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogArtwork extends StatelessWidget {
  final String? path;
  final IconData icon;
  final double extent;

  const _CatalogArtwork({
    required this.path,
    required this.icon,
    required this.extent,
  });

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final hasImage = file != null && file.existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: Container(
        width: extent,
        height: extent,
        color: AppColors.bgSurface,
        child: hasImage
            ? Image.file(file!, fit: BoxFit.cover)
            : Icon(icon, size: 46, color: AppColors.textSecondary),
      ),
    );
  }
}
