import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../data/services/remote_playback_queue_builder.dart';
import '../../domain/models/media_transfer_batch.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_hub_connection_store.dart';
import '../../domain/services/media_transfer_service.dart';

/// Remote Media Hub browser whose streaming path uses the same app-scoped
/// PlaybackSessionService as local Library playback.
class UnifiedRemoteMediaLibraryScreen extends StatefulWidget {
  const UnifiedRemoteMediaLibraryScreen({super.key});

  @override
  State<UnifiedRemoteMediaLibraryScreen> createState() =>
      _UnifiedRemoteMediaLibraryScreenState();
}

class _UnifiedRemoteMediaLibraryScreenState
    extends State<UnifiedRemoteMediaLibraryScreen> {
  late final MediaHubClientService _client;
  late final MediaHubConnectionStore _connectionStore;
  late final MediaTransferService _transfers;
  late final PlaybackSessionService _session;

  final Set<String> _selected = <String>{};
  final Map<String, MediaTransferItemProgress> _progress = {};
  List<RemoteAudioTrack> _tracks = const [];
  bool _loading = false;
  bool _transferring = false;
  String? _error;

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _client = services.mediaHubClientService;
    _connectionStore = services.mediaHubConnectionStore;
    _transfers = services.mediaTransferService;
    _session = services.playbackSessionService;
    unawaited(_ensureConnected());
  }

  Future<void> _ensureConnected() async {
    if (_client.isConnected) {
      await _refresh();
      return;
    }
    final saved = await _connectionStore.loadLastConnection();
    if (saved == null) return;
    setState(() => _loading = true);
    try {
      await _client.connectTo(saved);
      await _refresh(keepBusy: true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '上次连接的电脑暂时不可用，请重新扫码连接。');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanAndConnect() async {
    final raw = await Navigator.pushNamed<String>(context, Routes.mediaHubScanner);
    if (!mounted || raw == null || raw.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final connection = await _client.connect(Uri.parse(raw.trim()));
      await _connectionStore.saveConnection(connection);
      await _refresh(keepBusy: true);
    } catch (error) {
      if (mounted) setState(() => _error = '连接电脑失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh({bool keepBusy = false}) async {
    if (!keepBusy) {
      if (_loading) return;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final tracks = await _client.fetchTracks();
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _selected.removeWhere(
          (id) => tracks.every((track) => track.id != id),
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = '读取电脑音乐库失败：$error');
    } finally {
      if (!keepBusy && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play(RemoteAudioTrack track) async {
    if (_selectionMode) {
      _toggle(track.id);
      return;
    }
    final builder = RemotePlaybackQueueBuilder(_client);
    final queue = builder.buildQueue(_tracks);
    final index = _tracks.indexWhere((item) => item.id == track.id);
    if (queue.isEmpty || index < 0) return;
    try {
      await _session.setQueue(queue, startIndex: index);
      if (mounted) await Navigator.pushNamed(context, Routes.nowPlaying);
    } catch (error) {
      _show('在线播放失败：$error', error: true);
    }
  }

  void _toggle(String id) {
    if (_transferring) return;
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _toggleAll() {
    if (_transferring) return;
    setState(() {
      if (_selected.length == _tracks.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_tracks.map((track) => track.id));
      }
    });
  }

  Future<void> _downloadSelected({required bool playAfter}) async {
    final tracks = _tracks
        .where((track) => _selected.contains(track.id))
        .toList(growable: false);
    if (tracks.isEmpty || _transferring) return;
    setState(() {
      _transferring = true;
      _error = null;
    });
    try {
      final result = await _transfers.downloadRemoteTracks(
        tracks,
        onProgress: (progress) {
          if (mounted) setState(() => _progress[progress.id] = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _selected.removeAll(result.completed.map((item) => item.id));
      });
      _show(
        result.failed.isEmpty
            ? '已下载并导入 ${result.completed.length} 首到本地音乐库'
            : '成功 ${result.completed.length} 首，失败 ${result.failed.length} 首',
        error: result.completed.isEmpty && result.failed.isNotEmpty,
      );
      if (playAfter && result.completed.isNotEmpty) {
        await _playDownloaded(tracks, result);
      }
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _playDownloaded(
    List<RemoteAudioTrack> requested,
    MediaTransferBatchResult result,
  ) async {
    final paths = <String, String>{
      for (final item in result.completed)
        if (item.destinationPath != null) item.id: item.destinationPath!,
    };
    final items = <PlaybackItem>[];
    for (final track in requested) {
      final path = paths[track.id];
      if (path == null) continue;
      items.add(
        PlaybackItem(
          id: 'local:$path',
          title: track.title,
          artist: track.artist,
          audioAsset: AudioAsset(
            originalPath: path,
            format: track.format,
            duration: track.duration,
            metadata: {
              'transferSource': 'media-hub',
              'remoteTrackId': track.id,
              if (track.album != null) 'album': track.album,
            },
          ),
        ),
      );
    }
    if (items.isEmpty) return;
    await _session.setQueue(items);
    if (mounted) await Navigator.pushNamed(context, Routes.nowPlaying);
  }

  Future<void> _disconnect() async {
    final current = _session.currentState.currentItem;
    if (current != null &&
        RemotePlaybackQueueBuilder.trackFromItem(current) != null) {
      await _session.clearQueue(keepCurrent: false);
    }
    await _client.disconnect();
    if (!mounted) return;
    setState(() {
      _tracks = const [];
      _selected.clear();
      _error = null;
    });
  }

  void _show(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.bgSurface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final connected = _client.isConnected;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        title: Text(_selectionMode ? '已选择 ${_selected.length} 首' : '电脑音乐库'),
        leading: _selectionMode
            ? IconButton(
                onPressed: _transferring
                    ? null
                    : () => setState(_selected.clear),
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        actions: [
          if (connected && _selectionMode)
            IconButton(
              tooltip: _selected.length == _tracks.length ? '取消全选' : '全选',
              onPressed: _transferring ? null : _toggleAll,
              icon: const Icon(Icons.select_all_rounded),
            ),
          if (connected && !_selectionMode)
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (connected && !_selectionMode)
            IconButton(
              tooltip: '断开连接',
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off_rounded),
            ),
        ],
      ),
      bottomNavigationBar: !_selectionMode
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _transferring
                            ? null
                            : () => _downloadSelected(playAfter: false),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('下载到本机'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _transferring
                            ? null
                            : () => _downloadSelected(playAfter: true),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('下载并播放'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: !connected
            ? _DisconnectedState(
                loading: _loading,
                error: _error,
                onConnect: _scanAndConnect,
              )
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: EdgeInsets.all(layout.pageGutter),
                  children: [
                    Text(
                      '直接在线播放不会占用手机存储；需要离线时再长按歌曲进行多选下载。在线播放同样使用 LyricForge 的统一播放队列、锁屏与耳机控制。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
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
                      const Center(child: CircularProgressIndicator())
                    else if (_tracks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Center(child: Text('电脑端当前没有共享音乐')),
                      )
                    else
                      for (final track in _tracks)
                        _TrackTile(
                          track: track,
                          selected: _selected.contains(track.id),
                          progress: _progress[track.id],
                          onTap: () => _play(track),
                          onLongPress: () => _toggle(track.id),
                        ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _DisconnectedState extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback onConnect;

  const _DisconnectedState({
    required this.loading,
    required this.error,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(layout.pageGutter),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  const Icon(
                    Icons.devices_rounded,
                    size: 52,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '连接电脑音乐库',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    '扫描桌面端跨设备传输中心二维码后，可直接在线播放或批量下载。',
                    textAlign: TextAlign.center,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      error!,
                      style: const TextStyle(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: loading ? null : onConnect,
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(loading ? '连接中...' : '扫描二维码连接'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final RemoteAudioTrack track;
  final bool selected;
  final MediaTransferItemProgress? progress;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TrackTile({
    required this.track,
    required this.selected,
    required this.progress,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (track.artist?.trim().isNotEmpty == true) track.artist!.trim(),
      if (track.album?.trim().isNotEmpty == true) track.album!.trim(),
      track.format.toUpperCase(),
    ].join(' · ');
    return Card(
      color: selected ? AppColors.bgHighlight : null,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: selected
            ? const Icon(Icons.check_circle_rounded, color: AppColors.accent)
            : const CircleAvatar(child: Icon(Icons.music_note_rounded)),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (progress?.status == MediaTransferItemStatus.transferring)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(value: progress!.fraction),
              ),
          ],
        ),
        trailing: selected
            ? null
            : Icon(
                track.hasLyrics
                    ? Icons.lyrics_rounded
                    : Icons.play_arrow_rounded,
              ),
      ),
    );
  }
}
