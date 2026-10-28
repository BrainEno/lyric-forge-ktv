import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/local_media_library_entry.dart';
import '../../../player/domain/repositories/local_media_library_repository.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/media_hub_connection.dart';
import '../../domain/models/media_transfer_batch.dart';
import '../../domain/models/media_transfer_queue.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_hub_connection_store.dart';
import '../../domain/services/media_transfer_queue_service.dart';
import '../widgets/remote_media_artwork.dart';
import 'remote_catalog_utils.dart';

class MobileRemoteMusicLibraryScreen extends StatefulWidget {
  const MobileRemoteMusicLibraryScreen({super.key});

  @override
  State<MobileRemoteMusicLibraryScreen> createState() =>
      _MobileRemoteMusicLibraryScreenState();
}

enum _RemoteLibraryFilter { all, downloaded, lyrics }

class _MobileRemoteMusicLibraryScreenState
    extends State<MobileRemoteMusicLibraryScreen> {
  late final MediaHubClientService _client;
  late final MediaHubConnectionStore _connectionStore;
  late final MediaTransferQueueService _transferQueue;
  late final LocalMediaLibraryRepository _localLibrary;
  late final PlaybackSessionService _playbackSession;

  final TextEditingController _pairingController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, LocalMediaLibraryEntry> _downloaded =
      <String, LocalMediaLibraryEntry>{};
  final Set<String> _handledCompletedTasks = <String>{};

  StreamSubscription<MediaTransferQueueSnapshot>? _queueSubscription;
  List<RemoteAudioTrack> _tracks = const <RemoteAudioTrack>[];
  MediaHubConnection? _savedConnection;
  _RemoteLibraryFilter _filter = _RemoteLibraryFilter.all;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _client = services.mediaHubClientService;
    _connectionStore = services.mediaHubConnectionStore;
    _transferQueue = services.mediaTransferQueueService;
    _localLibrary = services.localMediaLibraryRepository;
    _playbackSession = services.playbackSessionService;
    _searchController.addListener(_refreshSearch);

    _handledCompletedTasks.addAll(
      _transferQueue.currentState.completed.map((item) => item.id),
    );
    _queueSubscription = _transferQueue.stateStream.listen(_onQueueChanged);

    if (_client.isConnected) {
      unawaited(_loadTracks());
    } else {
      unawaited(_restoreConnection());
    }
  }

  @override
  void dispose() {
    unawaited(_queueSubscription?.cancel());
    _pairingController.dispose();
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshSearch() {
    if (mounted) setState(() {});
  }

  void _onQueueChanged(MediaTransferQueueSnapshot snapshot) {
    if (!mounted) return;
    var completedNewDownload = false;
    for (final item in snapshot.completed) {
      if (item.direction != MediaTransferDirection.downloadFromDesktop) continue;
      if (_handledCompletedTasks.add(item.id)) completedNewDownload = true;
    }
    setState(() {});
    if (completedNewDownload) unawaited(_syncDownloadedState());
  }

  List<RemoteAudioTrack> get _visibleTracks {
    final query = _searchController.text.trim().toLowerCase();
    return _tracks.where((track) {
      if (_filter == _RemoteLibraryFilter.downloaded &&
          !_downloaded.containsKey(track.id)) {
        return false;
      }
      if (_filter == _RemoteLibraryFilter.lyrics && !track.hasLyrics) {
        return false;
      }
      if (query.isEmpty) return true;
      return track.title.toLowerCase().contains(query) ||
          (track.artist?.toLowerCase().contains(query) ?? false) ||
          (track.album?.toLowerCase().contains(query) ?? false) ||
          track.format.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _restoreConnection() async {
    final saved = await _connectionStore.loadLastConnection();
    if (!mounted) return;
    setState(() => _savedConnection = saved);
    if (saved != null) await _connectTo(saved, quiet: true);
  }

  Future<void> _scan() async {
    final value =
        await Navigator.pushNamed<String>(context, Routes.mediaHubScanner);
    if (!mounted || value == null || value.trim().isEmpty) return;
    _pairingController.text = value.trim();
    await _connectRaw(value.trim());
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _pairingController.text = text;
  }

  Future<void> _connectRaw([String? value]) async {
    if (_busy) return;
    final raw = (value ?? _pairingController.text).trim();
    if (raw.isEmpty) return;
    try {
      final connection = MediaHubConnection.fromPairingUri(Uri.parse(raw));
      await _connectTo(connection);
    } catch (error) {
      if (mounted) setState(() => _error = '配对信息无效：$error');
    }
  }

  Future<void> _connectTo(
    MediaHubConnection connection, {
    bool quiet = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client.connectTo(connection);
      await _connectionStore.saveConnection(connection);
      final tracks = await _client.fetchTracks();
      if (!mounted) return;
      setState(() {
        _savedConnection = connection;
        _tracks = tracks;
      });
      await _syncDownloadedState();
      final queueState = _transferQueue.currentState;
      if (queueState.isPaused &&
          queueState.pauseReason?.contains('尚未连接') == true) {
        unawaited(_transferQueue.resume());
      } else {
        unawaited(_transferQueue.processPending());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = quiet
            ? '上次桌面端暂时无法连接，可以重试或重新扫码。'
            : '无法连接桌面端：$error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadTracks() async {
    if (_busy || !_client.isConnected) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tracks = await _client.fetchTracks();
      if (!mounted) return;
      setState(() => _tracks = tracks);
      await _syncDownloadedState();
    } catch (error) {
      if (mounted) setState(() => _error = '刷新音乐库失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncDownloadedState() async {
    final entries = await _localLibrary.getAll();
    if (!mounted) return;
    final next = <String, LocalMediaLibraryEntry>{};
    for (final track in _tracks) {
      for (final entry in entries) {
        if (!entry.isMissing && remoteTrackMatchesDownloadedEntry(track, entry)) {
          next[track.id] = entry;
          break;
        }
      }
    }
    setState(() {
      _downloaded
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _disconnect({bool forget = false}) async {
    if (_playbackSession.currentState.currentItem?.isRemoteStream == true) {
      await _playbackSession.clearQueue(keepCurrent: false);
    }
    await _client.disconnect();
    if (forget) await _connectionStore.clear();
    if (!mounted) return;
    setState(() {
      _tracks = const <RemoteAudioTrack>[];
      _downloaded.clear();
      _error = null;
      if (forget) {
        _savedConnection = null;
        _pairingController.clear();
      }
    });
  }

  Uri? _remoteArtwork(RemoteAudioTrack track) =>
      remoteArtworkUriFor(_client, track);

  PlaybackItem _itemFor(RemoteAudioTrack track) {
    final local = _downloaded[track.id];
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
    final artworkUri = _remoteArtwork(track);
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
          if (artworkUri != null) 'remoteArtworkUri': artworkUri.toString(),
        },
      ),
    );
  }

  Future<void> _play(RemoteAudioTrack track) async {
    final visible = _visibleTracks;
    final index = visible.indexWhere((candidate) => candidate.id == track.id);
    if (index < 0) return;
    try {
      await _playbackSession.setQueue(
        visible.map(_itemFor).toList(growable: false),
        startIndex: index,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '播放失败：$error');
    }
  }

  Future<void> _playAll() async {
    final visible = _visibleTracks;
    if (visible.isEmpty) return;
    try {
      await _playbackSession.setQueue(
        visible.map(_itemFor).toList(growable: false),
        startIndex: 0,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '播放失败：$error');
    }
  }

  MediaTransferQueueItem? _queueItemFor(RemoteAudioTrack track) {
    final items = _transferQueue.currentState.items;
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item.direction == MediaTransferDirection.downloadFromDesktop &&
          item.remoteTrack?.id == track.id) {
        return item;
      }
    }
    return null;
  }

  Future<void> _download(RemoteAudioTrack track) async {
    if (_downloaded.containsKey(track.id)) return;
    setState(() => _error = null);
    try {
      final existing = _queueItemFor(track);
      if (existing?.status == MediaTransferQueueStatus.completed) {
        await _transferQueue.remove(existing!.id);
      } else if (existing?.status == MediaTransferQueueStatus.failed) {
        await _transferQueue.retry(existing!.id);
        _showMessage('已重新加入下载队列');
        return;
      } else if (existing?.status == MediaTransferQueueStatus.queued ||
          existing?.status == MediaTransferQueueStatus.transferring) {
        return;
      }
      await _transferQueue.enqueueDownloads(<RemoteAudioTrack>[track]);
      _showMessage('“${track.title}”已加入下载队列');
    } catch (error) {
      if (mounted) setState(() => _error = '加入下载队列失败：$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final connection = _client.currentConnection;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bgBase,
        title: const Text('桌面音乐库'),
        actions: [
          if (_client.isConnected)
            IconButton(
              tooltip: '刷新',
              onPressed: _busy ? null : _loadTracks,
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (_client.isConnected)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'disconnect') unawaited(_disconnect());
                if (value == 'forget') unawaited(_disconnect(forget: true));
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem(value: 'disconnect', child: Text('断开连接')),
                PopupMenuItem(value: 'forget', child: Text('忘记此桌面端')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: connection == null || !_client.isConnected
            ? _buildConnectState()
            : _buildLibrary(connection),
      ),
    );
  }

  Widget _buildConnectState() {
    final layout = AppResponsive.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(layout.pageGutter),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
              border: Border.all(color: AppColors.borderMuted),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.devices_rounded,
                  size: 54,
                  color: AppColors.accent,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '连接你的桌面音乐库',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '连接后可以搜索、在线播放，并把歌曲加入持久化下载队列。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('扫描桌面二维码'),
                ),
                if (_savedConnection != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _connectTo(_savedConnection!),
                    icon: const Icon(Icons.history_rounded),
                    label: Text('重新连接 ${_savedConnection!.host}'),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _pairingController,
                  minLines: 2,
                  maxLines: 3,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: '配对信息',
                    suffixIcon: IconButton(
                      tooltip: '粘贴',
                      onPressed: _paste,
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _connectRaw,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded),
                  label: Text(_busy ? '连接中…' : '使用配对信息连接'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLibrary(MediaHubConnection connection) {
    final layout = AppResponsive.of(context);
    final visible = _visibleTracks;

    return RefreshIndicator(
      onRefresh: _loadTracks,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          layout.pageGutter,
          layout.pageGutter,
          layout.pageGutter,
          AppSpacing.xl,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
              border: Border.all(color: AppColors.borderMuted),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.bgHighlight,
                  child: Icon(Icons.computer_rounded, color: AppColors.accent),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${_tracks.length} 首歌曲 · ${_downloaded.length} 首已下载',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: visible.isEmpty ? null : _playAll,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索歌曲、艺人或专辑',
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
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _filter == _RemoteLibraryFilter.all,
                  onSelected: (_) =>
                      setState(() => _filter = _RemoteLibraryFilter.all),
                ),
                const SizedBox(width: AppSpacing.sm),
                ChoiceChip(
                  label: const Text('已下载'),
                  selected: _filter == _RemoteLibraryFilter.downloaded,
                  onSelected: (_) => setState(
                    () => _filter = _RemoteLibraryFilter.downloaded,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ChoiceChip(
                  label: const Text('有歌词'),
                  selected: _filter == _RemoteLibraryFilter.lyrics,
                  onSelected: (_) =>
                      setState(() => _filter = _RemoteLibraryFilter.lyrics),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_busy && _tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text(
                  '没有匹配的歌曲',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            for (final track in visible) ...[
              _RemoteTrackTile(
                track: track,
                client: _client,
                localEntry: _downloaded[track.id],
                queueItem: _queueItemFor(track),
                onPlay: () => _play(track),
                onDownload: () => _download(track),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
        ],
      ),
    );
  }
}

class _RemoteTrackTile extends StatelessWidget {
  final RemoteAudioTrack track;
  final MediaHubClientService client;
  final LocalMediaLibraryEntry? localEntry;
  final MediaTransferQueueItem? queueItem;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  const _RemoteTrackTile({
    required this.track,
    required this.client,
    required this.localEntry,
    required this.queueItem,
    required this.onPlay,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final downloaded = localEntry != null;
    final status = queueItem?.status;
    final queued = status == MediaTransferQueueStatus.queued;
    final transferring = status == MediaTransferQueueStatus.transferring;
    final failed = status == MediaTransferQueueStatus.failed;
    final destination = queueItem?.destinationPath;
    final completedFileExists = destination != null && File(destination).existsSync();
    final completed = status == MediaTransferQueueStatus.completed &&
        (downloaded || completedFileExists);
    final staleCompleted = status == MediaTransferQueueStatus.completed &&
        !downloaded &&
        !completedFileExists;
    final total = queueItem?.totalBytes;
    final fraction = total == null || total <= 0
        ? null
        : ((queueItem?.bytesTransferred ?? 0) / total)
            .clamp(0.0, 1.0)
            .toDouble();

    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              RemoteMediaArtwork(
                track: track,
                client: client,
                localPath: localEntry?.embeddedArtworkPath,
                extent: 52,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      <String>[
                        if (track.artist?.trim().isNotEmpty == true)
                          track.artist!.trim(),
                        if (track.album?.trim().isNotEmpty == true)
                          track.album!.trim(),
                        track.format.toUpperCase(),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textTertiary),
                    ),
                    if (queued || transferring) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: transferring ? fraction : null),
                    ],
                    if (failed || staleCompleted) ...[
                      const SizedBox(height: 4),
                      Text(
                        failed
                            ? queueItem?.error ?? '下载失败，点击右侧重试'
                            : '本地文件已不存在，可重新下载',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: failed ? AppColors.error : AppColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              if (track.hasLyrics)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.xs),
                  child: Icon(
                    Icons.lyrics_rounded,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                tooltip: downloaded || completed
                    ? '已下载到手机'
                    : failed || staleCompleted
                        ? '重新下载'
                        : queued
                            ? '等待下载'
                            : transferring
                                ? '正在下载'
                                : '下载到手机',
                onPressed: downloaded || completed || queued || transferring
                    ? null
                    : onDownload,
                icon: transferring
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        downloaded || completed
                            ? Icons.download_done_rounded
                            : failed || staleCompleted
                                ? Icons.refresh_rounded
                                : queued
                                    ? Icons.schedule_rounded
                                    : Icons.download_rounded,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Backward-compatible helper kept for older tests and callers.
bool remoteTrackMatchesLocalEntry(
  RemoteAudioTrack track,
  LocalMediaLibraryEntry entry,
) =>
    remoteTrackMatchesDownloadedEntry(track, entry);
