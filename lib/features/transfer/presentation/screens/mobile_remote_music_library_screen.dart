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
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_hub_connection_store.dart';
import '../../domain/services/media_transfer_service.dart';

/// Mobile-first browser for the paired desktop music library.
///
/// The screen deliberately behaves like a normal music library rather than a
/// transfer utility: search/filter first, tap to play, download as a secondary
/// action. Downloaded files are detected again from the persistent local library
/// after relaunch, so the "downloaded" badge is not session-only state.
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
  late final MediaTransferService _transfers;
  late final LocalMediaLibraryRepository _localLibrary;
  late final PlaybackSessionService _playbackSession;

  final TextEditingController _pairingController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _downloadedPaths = <String, String>{};
  final Map<String, MediaTransferItemProgress> _progress =
      <String, MediaTransferItemProgress>{};

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
    _transfers = services.mediaTransferService;
    _localLibrary = services.localMediaLibraryRepository;
    _playbackSession = services.playbackSessionService;
    _searchController.addListener(_refreshSearch);

    if (_client.isConnected) {
      unawaited(_loadTracks());
    } else {
      unawaited(_restoreConnection());
    }
  }

  @override
  void dispose() {
    _pairingController.dispose();
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshSearch() {
    if (mounted) setState(() {});
  }

  List<RemoteAudioTrack> get _visibleTracks {
    final query = _searchController.text.trim().toLowerCase();
    return _tracks.where((track) {
      if (_filter == _RemoteLibraryFilter.downloaded &&
          !_downloadedPaths.containsKey(track.id)) {
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
    final next = <String, String>{};
    for (final track in _tracks) {
      for (final entry in entries) {
        if (!entry.isMissing && remoteTrackMatchesLocalEntry(track, entry)) {
          next[track.id] = entry.sourcePath;
          break;
        }
      }
    }
    setState(() {
      _downloadedPaths
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
      _downloadedPaths.clear();
      _progress.clear();
      _error = null;
      if (forget) {
        _savedConnection = null;
        _pairingController.clear();
      }
    });
  }

  PlaybackItem _itemFor(RemoteAudioTrack track) {
    final localPath = _downloadedPaths[track.id];
    if (localPath != null && File(localPath).existsSync()) {
      return PlaybackItem(
        id: 'local:$localPath',
        title: track.title,
        artist: track.artist,
        hasLyrics: track.hasLyrics,
        audioAsset: AudioAsset(
          originalPath: localPath,
          format: track.format,
          duration: track.duration,
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

  Future<void> _play(RemoteAudioTrack track) async {
    final visible = _visibleTracks;
    final index = visible.indexWhere((candidate) => candidate.id == track.id);
    if (index < 0) return;
    final queue = visible.map(_itemFor).toList(growable: false);
    try {
      await _playbackSession.setQueue(queue, startIndex: index);
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

  Future<void> _download(RemoteAudioTrack track) async {
    final currentProgress = _progress[track.id];
    if (currentProgress?.status == MediaTransferItemStatus.queued ||
        currentProgress?.status == MediaTransferItemStatus.transferring ||
        _downloadedPaths.containsKey(track.id)) {
      return;
    }

    setState(() {
      _error = null;
      _progress[track.id] = MediaTransferItemProgress(
        id: track.id,
        title: track.title,
        direction: MediaTransferDirection.downloadFromDesktop,
        status: MediaTransferItemStatus.queued,
        totalBytes: track.byteLength > 0 ? track.byteLength : null,
      );
    });

    final result = await _transfers.downloadRemoteTracks(
      <RemoteAudioTrack>[track],
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _progress[track.id] = progress);
      },
    );

    if (!mounted) return;
    if (result.completed.isNotEmpty) {
      final path = result.completed.first.destinationPath;
      if (path != null) {
        setState(() => _downloadedPaths[track.id] = path);
      }
      await _syncDownloadedState();
      _showMessage('“${track.title}”已下载到本地音乐库');
    } else {
      final message = result.failed.isEmpty
          ? '下载失败'
          : result.failed.first.error ?? '下载失败';
      setState(() => _error = message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = _client.currentConnection;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
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
                  '连接后可以像普通音乐库一样搜索、在线播放，并把歌曲下载到手机离线播放。',
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
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
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
    final downloadedCount = _tracks
        .where((track) => _downloadedPaths.containsKey(track.id))
        .length;

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
                      const SizedBox(height: 2),
                      Text(
                        '${_tracks.length} 首歌曲 · $downloadedCount 首已下载',
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
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    size: 42,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _tracks.isEmpty ? '桌面端当前没有共享音乐' : '没有匹配的歌曲',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          else
            for (final track in visible) ...[
              _RemoteTrackTile(
                track: track,
                downloaded: _downloadedPaths.containsKey(track.id),
                progress: _progress[track.id],
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
  final bool downloaded;
  final MediaTransferItemProgress? progress;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  const _RemoteTrackTile({
    required this.track,
    required this.downloaded,
    required this.progress,
    required this.onPlay,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final transferring = progress?.status == MediaTransferItemStatus.queued ||
        progress?.status == MediaTransferItemStatus.transferring;
    final failed = progress?.status == MediaTransferItemStatus.failed;

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
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: Icon(
                  downloaded
                      ? Icons.offline_pin_rounded
                      : Icons.music_note_rounded,
                  color: downloaded ? AppColors.accent : AppColors.textSecondary,
                ),
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
                    if (transferring) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: progress?.fraction),
                    ],
                    if (failed) ...[
                      const SizedBox(height: 4),
                      Text(
                        progress?.error ?? '下载失败',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: AppColors.error),
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
                tooltip: downloaded
                    ? '已下载到手机'
                    : transferring
                        ? '正在下载'
                        : '下载到手机',
                onPressed: downloaded || transferring ? null : onDownload,
                icon: transferring
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        downloaded
                            ? Icons.download_done_rounded
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

/// The transfer service names downloaded files as
/// `<sanitised-title>_<first-8-id>.<format>`. Matching on the stable id suffix
/// lets the UI recover downloaded state after relaunch even when the title
/// contains characters that were sanitised on disk.
bool remoteTrackMatchesLocalEntry(
  RemoteAudioTrack track,
  LocalMediaLibraryEntry entry,
) {
  final segments = entry.sourcePath.replaceAll('\\', '/').split('/');
  final fileName = segments.isEmpty ? entry.sourcePath : segments.last;
  final id = track.id.trim();
  final suffix = id.length > 8 ? id.substring(0, 8) : id;
  final format = track.format.trim().toLowerCase().isEmpty
      ? 'audio'
      : track.format.trim().toLowerCase();
  return fileName.toLowerCase().endsWith('_${suffix.toLowerCase()}.$format');
}
