import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/media_hub_connection.dart';
import '../../domain/models/media_transfer_batch.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_hub_connection_store.dart';
import '../../domain/services/media_transfer_service.dart';

/// Desktop Media Hub browser with first-class local-library transfer.
///
/// Remote streaming stays available, but downloaded tracks are imported into
/// the same persistent local Library used by the regular player.
class CrossDeviceMediaLibraryScreen extends StatefulWidget {
  const CrossDeviceMediaLibraryScreen({super.key});

  @override
  State<CrossDeviceMediaLibraryScreen> createState() =>
      _CrossDeviceMediaLibraryScreenState();
}

class _CrossDeviceMediaLibraryScreenState
    extends State<CrossDeviceMediaLibraryScreen> {
  late final MediaHubClientService _client;
  late final MediaHubConnectionStore _connectionStore;
  late final MediaTransferService _transfers;
  late final AudioPlayerService _audio;
  late final PlaybackSessionService _playbackSession;

  final TextEditingController _pairingController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  final Map<String, MediaTransferItemProgress> _progress = {};
  final Map<String, String> _downloadedPaths = {};

  List<RemoteAudioTrack> _tracks = const [];
  MediaHubConnection? _savedConnection;
  RemoteAudioTrack? _streamingTrack;
  LyricDocument? _streamingLyrics;
  bool _busy = false;
  bool _transferBusy = false;
  String? _error;

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _client = services.mediaHubClientService;
    _connectionStore = services.mediaHubConnectionStore;
    _transfers = services.mediaTransferService;
    _audio = services.audioPlayerService;
    _playbackSession = services.playbackSessionService;
    if (_client.isConnected) {
      unawaited(_loadTracks());
    } else {
      unawaited(_restoreConnection());
    }
  }

  @override
  void dispose() {
    _pairingController.dispose();
    super.dispose();
  }

  Future<void> _restoreConnection() async {
    final saved = await _connectionStore.loadLastConnection();
    if (!mounted) return;
    setState(() => _savedConnection = saved);
    if (saved == null) return;
    await _connectTo(saved, quiet: true);
  }

  Future<void> _scan() async {
    if (_busy) return;
    final value = await Navigator.pushNamed<String>(context, Routes.mediaHubScanner);
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
    final raw = (value ?? _pairingController.text).trim();
    if (raw.isEmpty || _busy) return;
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
        _selectedIds.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = quiet
          ? '上次桌面端暂时无法连接，可重试或重新扫码。'
          : '无法连接桌面端：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadTracks() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tracks = await _client.fetchTracks();
      if (mounted) {
        setState(() {
          _tracks = tracks;
          _selectedIds.removeWhere(
            (id) => tracks.every((track) => track.id != id),
          );
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '刷新失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect({bool forget = false}) async {
    if (_playbackSession.currentState.currentItem?.isRemoteStream == true) {
      await _playbackSession.clearQueue(keepCurrent: false);
    }
    await _client.disconnect();
    if (forget) await _connectionStore.clear();
    if (!mounted) return;
    setState(() {
      if (forget) {
        _savedConnection = null;
        _pairingController.clear();
      }
      _tracks = const [];
      _selectedIds.clear();
      _streamingTrack = null;
      _streamingLyrics = null;
      _error = null;
    });
  }

  void _toggleSelection(String id) {
    if (_transferBusy) return;
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _selectAll() {
    if (_transferBusy) return;
    setState(() {
      if (_selectedIds.length == _tracks.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_tracks.map((track) => track.id));
      }
    });
  }

  List<RemoteAudioTrack> _selectedTracks() => _tracks
      .where((track) => _selectedIds.contains(track.id))
      .toList(growable: false);

  Future<void> _stream(RemoteAudioTrack track) async {
    if (_selectionMode) {
      _toggleSelection(track.id);
      return;
    }
    setState(() {
      _streamingTrack = track;
      _streamingLyrics = null;
      _error = null;
    });
    try {
      final uri = _client.playbackUriFor(track);
      final host = _client.currentConnection?.host ?? 'desktop';
      final item = PlaybackItem(
        id: 'remote:$host:${track.id}',
        title: track.title,
        artist: track.artist,
        hasLyrics: track.hasLyrics,
        streamUri: uri,
        audioAsset: AudioAsset(
          originalPath: uri.toString(),
          format: track.format,
          duration: track.duration,
          metadata: {
            'transferSource': 'media-hub-stream',
            'remoteTrackId': track.id,
            if (track.album?.trim().isNotEmpty == true) 'album': track.album!.trim(),
          },
        ),
      );
      await _playbackSession.setQueue([item]);
      if (track.hasLyrics) {
        try {
          final lyrics = await _client.fetchLyrics(track);
          if (mounted && _streamingTrack?.id == track.id) {
            setState(() => _streamingLyrics = lyrics);
          }
        } catch (_) {}
      }
    } catch (error) {
      if (mounted) setState(() => _error = '在线播放失败：$error');
    }
  }

  Future<void> _downloadOne(RemoteAudioTrack track) async {
    await _downloadTracks([track]);
  }

  Future<void> _downloadSelected({required bool playAfter}) async {
    final tracks = _selectedTracks();
    if (tracks.isEmpty) return;
    await _downloadTracks(tracks, playAfter: playAfter);
  }

  Future<void> _downloadTracks(
    List<RemoteAudioTrack> tracks, {
    bool playAfter = false,
  }) async {
    if (_transferBusy || tracks.isEmpty) return;
    setState(() {
      _transferBusy = true;
      _error = null;
    });

    final result = await _transfers.downloadRemoteTracks(
      tracks,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _progress[progress.id] = progress;
          if (progress.status == MediaTransferItemStatus.completed &&
              progress.destinationPath != null) {
            _downloadedPaths[progress.id] = progress.destinationPath!;
          }
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _transferBusy = false;
      for (final item in result.completed) {
        final path = item.destinationPath;
        if (path != null) _downloadedPaths[item.id] = path;
      }
      _selectedIds.removeAll(result.completed.map((item) => item.id));
    });

    final completed = result.completed.length;
    final failed = result.failed.length;
    _showMessage(
      failed == 0
          ? '已传送并导入 $completed 首歌曲到本地音乐库'
          : '已导入 $completed 首，$failed 首传送失败，可重新选择后重试',
      error: completed == 0 && failed > 0,
    );

    if (playAfter && completed > 0) {
      await _playDownloadedBatch(tracks, result);
    }
  }

  Future<void> _playDownloadedBatch(
    List<RemoteAudioTrack> requested,
    MediaTransferBatchResult result,
  ) async {
    final paths = <String, String>{
      for (final item in result.completed)
        if (item.destinationPath != null) item.id: item.destinationPath!,
    };
    final queue = <PlaybackItem>[];
    for (final track in requested) {
      final path = paths[track.id];
      if (path == null) continue;
      queue.add(
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
            },
          ),
        ),
      );
    }
    if (queue.isEmpty) return;
    _streamingTrack = null;
    _streamingLyrics = null;
    await _playbackSession.setQueue(queue);
    if (mounted) {
      await Navigator.pushNamed(context, Routes.nowPlaying);
    }
  }

  void _showMessage(String message, {bool error = false}) {
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
    final connection = _client.currentConnection;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        title: Text(_selectionMode ? '已选择 ${_selectedIds.length} 首' : '跨设备音乐'),
        leading: _selectionMode
            ? IconButton(
                tooltip: '退出多选',
                onPressed: _transferBusy
                    ? null
                    : () => setState(_selectedIds.clear),
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        actions: [
          if (_client.isConnected && !_selectionMode)
            IconButton(
              tooltip: '刷新',
              onPressed: _busy || _transferBusy ? null : _loadTracks,
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (_client.isConnected && _selectionMode)
            IconButton(
              tooltip: _selectedIds.length == _tracks.length ? '取消全选' : '全选',
              onPressed: _transferBusy ? null : _selectAll,
              icon: const Icon(Icons.select_all_rounded),
            ),
          if (_client.isConnected)
            PopupMenuButton<String>(
              enabled: !_transferBusy,
              onSelected: (value) {
                if (value == 'disconnect') unawaited(_disconnect());
                if (value == 'forget') unawaited(_disconnect(forget: true));
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'disconnect', child: Text('断开连接')),
                PopupMenuItem(value: 'forget', child: Text('忘记此桌面端')),
              ],
            ),
        ],
      ),
      bottomNavigationBar: _selectionMode
          ? _SelectionTransferBar(
              count: _selectedIds.length,
              busy: _transferBusy,
              onDownload: () => _downloadSelected(playAfter: false),
              onDownloadAndPlay: () => _downloadSelected(playAfter: true),
            )
          : _streamingTrack == null
              ? null
              : _RemoteMiniPlayer(
                  track: _streamingTrack!,
                  lyrics: _streamingLyrics,
                  audio: _audio,
                ),
      body: SafeArea(
        child: connection == null || !_client.isConnected
            ? _buildConnectState()
            : _buildRemoteLibrary(connection),
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
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(layout.isCompact ? AppSpacing.md : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.devices_rounded, size: 52, color: AppColors.accent),
                  const SizedBox(height: AppSpacing.md),
                  Text('连接桌面音乐库', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    '连接后可以直接在线播放，也可以多选歌曲批量传到本机并自动加入本地音乐库。',
                    textAlign: TextAlign.center,
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
                      onPressed: _busy ? null : () => _connectTo(_savedConnection!),
                      icon: const Icon(Icons.history_rounded),
                      label: Text('重试上次桌面 · ${_savedConnection!.host}'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _pairingController,
                    minLines: 2,
                    maxLines: 4,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: '配对信息',
                      hintText: 'lyricforge://media-hub/connect?...',
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
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link_rounded),
                    label: Text(_busy ? '连接中...' : '使用配对信息连接'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteLibrary(MediaHubConnection connection) {
    final layout = AppResponsive.of(context);
    return RefreshIndicator(
      onRefresh: _loadTracks,
      child: ListView(
        padding: EdgeInsets.all(layout.pageGutter),
        children: [
          _RemoteLibraryHeader(
            connection: connection,
            count: _tracks.length,
            onSelectAll: _tracks.isEmpty ? null : _selectAll,
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
          else if (_tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: Text('桌面端当前没有共享音乐')),
            )
          else
            for (final track in _tracks) _buildTrackTile(track),
        ],
      ),
    );
  }

  Widget _buildTrackTile(RemoteAudioTrack track) {
    final selected = _selectedIds.contains(track.id);
    final progress = _progress[track.id];
    final downloaded = _downloadedPaths.containsKey(track.id) ||
        progress?.status == MediaTransferItemStatus.completed;
    final transferring = progress?.status == MediaTransferItemStatus.transferring ||
        progress?.status == MediaTransferItemStatus.queued;
    final subtitle = [
      if (track.artist?.isNotEmpty == true) track.artist!,
      track.format.toUpperCase(),
      _formatBytes(track.byteLength),
      if (track.hasLyrics) '有歌词',
      if (downloaded) '已入本地库',
    ].join(' · ');

    return Card(
      color: selected ? AppColors.bgHighlight : null,
      child: ListTile(
        onTap: () => _stream(track),
        onLongPress: () => _toggleSelection(track.id),
        leading: _selectionMode
            ? Checkbox(
                value: selected,
                onChanged: _transferBusy ? null : (_) => _toggleSelection(track.id),
              )
            : const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.music_note_rounded),
              ),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (transferring)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(value: progress?.fraction),
              ),
            if (progress?.status == MediaTransferItemStatus.failed)
              Text(
                progress?.error ?? '传送失败',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.error),
              ),
          ],
        ),
        trailing: _selectionMode
            ? null
            : IconButton(
                tooltip: downloaded ? '已下载到本地库' : '下载到本地库',
                onPressed: _transferBusy || transferring || downloaded
                    ? null
                    : () => _downloadOne(track),
                icon: Icon(
                  downloaded ? Icons.download_done_rounded : Icons.download_rounded,
                ),
              ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _RemoteLibraryHeader extends StatelessWidget {
  final MediaHubConnection connection;
  final int count;
  final VoidCallback? onSelectAll;

  const _RemoteLibraryHeader({
    required this.connection,
    required this.count,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return Container(
      padding: EdgeInsets.all(layout.isCompact ? AppSpacing.md : AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: layout.isCompact ? layout.width - layout.pageGutter * 4 : 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('来自 ${connection.host}', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text('$count 首共享音乐 · 长按歌曲开始多选批量传送'),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onSelectAll,
            icon: const Icon(Icons.library_add_check_rounded),
            label: const Text('多选传送'),
          ),
        ],
      ),
    );
  }
}

class _SelectionTransferBar extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onDownload;
  final VoidCallback onDownloadAndPlay;

  const _SelectionTransferBar({
    required this.count,
    required this.busy,
    required this.onDownload,
    required this.onDownloadAndPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Expanded(child: Text('已选择 $count 首')),
              OutlinedButton.icon(
                onPressed: busy ? null : onDownload,
                icon: const Icon(Icons.download_rounded),
                label: const Text('下载入库'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: busy ? null : onDownloadAndPlay,
                icon: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text('下载并播放'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteMiniPlayer extends StatelessWidget {
  final RemoteAudioTrack track;
  final LyricDocument? lyrics;
  final AudioPlayerService audio;

  const _RemoteMiniPlayer({
    required this.track,
    required this.lyrics,
    required this.audio,
  });

  LyricLine? _lineAt(Duration position) {
    final lines = lyrics?.lines ?? const <LyricLine>[];
    for (var i = lines.length - 1; i >= 0; i--) {
      if (position >= lines[i].startTime) return lines[i];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: audio.stateStream,
      initialData: audio.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PlaybackState.idle();
        final line = _lineAt(state.position);
        return Material(
          color: AppColors.bgSurface,
          child: SafeArea(
            top: false,
            child: ListTile(
              leading: const Icon(Icons.cloud_queue_rounded),
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                line?.text ?? '${state.formattedPosition} / ${state.formattedDuration}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: state.isPlaying ? '暂停' : '播放',
                onPressed: () async {
                  if (state.isPlaying) {
                    await audio.pause();
                  } else {
                    await audio.play();
                  }
                },
                icon: Icon(state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
            ),
          ),
        );
      },
    );
  }
}
