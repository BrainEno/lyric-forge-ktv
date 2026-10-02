import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/media_hub_connection.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_hub_connection_store.dart';

class RemoteMediaLibraryScreen extends StatefulWidget {
  const RemoteMediaLibraryScreen({super.key});

  @override
  State<RemoteMediaLibraryScreen> createState() =>
      _RemoteMediaLibraryScreenState();
}

class _RemoteMediaLibraryScreenState extends State<RemoteMediaLibraryScreen> {
  late final MediaHubClientService _client;
  late final AudioPlayerService _audioService;
  late final MediaHubConnectionStore _connectionStore;

  final TextEditingController _pairingController = TextEditingController();

  List<RemoteAudioTrack> _tracks = const [];
  RemoteAudioTrack? _currentTrack;
  LyricDocument? _currentLyrics;
  MediaHubConnection? _savedConnection;
  final Map<String, double?> _downloadProgress = {};
  final Map<String, String> _downloadedPaths = {};

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = ServiceLocatorGlobal.I.mediaHubClientService;
    _audioService = ServiceLocatorGlobal.I.audioPlayerService;
    _connectionStore = ServiceLocatorGlobal.I.mediaHubConnectionStore;

    if (_client.isConnected) {
      unawaited(_loadTracks());
    } else {
      unawaited(_restoreLastConnection());
    }
  }

  @override
  void dispose() {
    _pairingController.dispose();
    super.dispose();
  }

  Future<void> _restoreLastConnection() async {
    final saved = await _connectionStore.loadLastConnection();
    if (!mounted) return;

    setState(() => _savedConnection = saved);
    if (saved == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _client.connectTo(saved);
      await _loadTracks(keepBusy: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '上次桌面端暂时无法连接，可重试或重新扫码配对。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retrySavedConnection() async {
    final saved = _savedConnection;
    if (saved == null || _busy) return;
    await _connectTo(saved);
  }

  Future<void> _pastePairingInfo() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _pairingController.text = text;
  }

  Future<void> _scanPairingCode() async {
    if (_busy) return;

    final result = await Navigator.pushNamed<String>(
      context,
      Routes.mediaHubScanner,
    );
    if (!mounted || result == null || result.trim().isEmpty) return;

    _pairingController.text = result.trim();
    await _connectRaw(result.trim());
  }

  Future<void> _connect() async {
    final raw = _pairingController.text.trim();
    if (raw.isEmpty || _busy) return;
    await _connectRaw(raw);
  }

  Future<void> _connectRaw(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      setState(() => _error = '配对信息格式不正确');
      return;
    }

    MediaHubConnection connection;
    try {
      connection = MediaHubConnection.fromPairingUri(uri);
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }

    await _connectTo(connection);
  }

  Future<void> _connectTo(MediaHubConnection connection) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _client.connectTo(connection);
      await _connectionStore.saveConnection(connection);
      if (mounted) {
        setState(() => _savedConnection = connection);
      }
      await _loadTracks(keepBusy: true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '无法连接桌面端：' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadTracks({bool keepBusy = false}) async {
    if (!keepBusy && mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }

    try {
      final tracks = await _client.fetchTracks();
      if (mounted) {
        setState(() => _tracks = tracks);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '读取桌面音乐库失败：' + error.toString());
      }
    } finally {
      if (!keepBusy && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(RemoteAudioTrack track) async {
    setState(() {
      _currentTrack = track;
      _currentLyrics = null;
      _error = null;
    });

    try {
      final uri = _client.playbackUriFor(track);
      await _audioService.loadAudioUri(uri: uri);
      await _audioService.play();

      if (track.hasLyrics) {
        try {
          final lyrics = await _client.fetchLyrics(track);
          if (mounted && _currentTrack?.id == track.id) {
            setState(() => _currentLyrics = lyrics);
          }
        } catch (error) {
          _showMessage('音频已播放，但歌词加载失败：' + error.toString());
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '播放失败：' + error.toString());
      }
    }
  }

  Future<void> _playPause() async {
    if (_currentTrack == null) return;
    final state = _audioService.currentState;
    if (state.isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.play();
    }
  }

  Future<void> _downloadTrack(RemoteAudioTrack track) async {
    if (_downloadProgress.containsKey(track.id)) return;

    setState(() => _downloadProgress[track.id] = null);

    try {
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(
        documents.path +
            Platform.pathSeparator +
            'LyricForge' +
            Platform.pathSeparator +
            'Downloads',
      );
      await directory.create(recursive: true);

      final idSuffix =
          track.id.length > 8 ? track.id.substring(0, 8) : track.id;
      final fileName =
          _safeFileName(track.title) + '_' + idSuffix + '.' + track.format;
      final destination =
          directory.path + Platform.pathSeparator + fileName;

      await _client.downloadTrack(
        track: track,
        destinationPath: destination,
        onProgress: (transferred, total) {
          if (!mounted) return;
          final progress =
              total == null || total <= 0 ? null : transferred / total;
          setState(() => _downloadProgress[track.id] = progress);
        },
      );

      if (!mounted) return;
      setState(() {
        _downloadProgress.remove(track.id);
        _downloadedPaths[track.id] = destination;
      });
      _showMessage('已下载到：' + destination);
    } catch (error) {
      if (!mounted) return;
      setState(() => _downloadProgress.remove(track.id));
      _showMessage('下载失败：' + error.toString(), error: true);
    }
  }

  Future<void> _disconnect() async {
    await _audioService.stop();
    await _client.disconnect();
    if (!mounted) return;
    setState(() {
      _tracks = const [];
      _currentTrack = null;
      _currentLyrics = null;
      _error = null;
    });
  }

  Future<void> _forgetDesktop() async {
    await _audioService.stop();
    await _client.disconnect();
    await _connectionStore.clear();
    _pairingController.clear();

    if (!mounted) return;
    setState(() {
      _savedConnection = null;
      _tracks = const [];
      _currentTrack = null;
      _currentLyrics = null;
      _error = null;
    });
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

  String _safeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'audio' : sanitized;
  }

  String _connectionLabel(MediaHubTransport transport) {
    return switch (transport) {
      MediaHubTransport.tailscale => 'Tailscale',
      MediaHubTransport.lan => '局域网',
      MediaHubTransport.unknown => '远程连接',
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toStringAsFixed(0) + ' KB';
    }
    return (bytes / (1024 * 1024)).toStringAsFixed(1) + ' MB';
  }

  LyricLine? _currentLyricLine(Duration position) {
    final lyrics = _currentLyrics?.lines ?? const <LyricLine>[];
    for (var i = lyrics.length - 1; i >= 0; i--) {
      if (position >= lyrics[i].startTime) return lyrics[i];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final connection = _client.currentConnection;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('桌面音乐库'),
        backgroundColor: AppColors.bgBase,
        actions: [
          if (_client.isConnected)
            IconButton(
              tooltip: '刷新',
              onPressed: _busy ? null : _loadTracks,
              icon: const Icon(Icons.refresh),
            ),
          if (_client.isConnected)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'disconnect') {
                  unawaited(_disconnect());
                } else if (value == 'forget') {
                  unawaited(_forgetDesktop());
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'disconnect',
                  child: Text('断开连接'),
                ),
                PopupMenuItem(
                  value: 'forget',
                  child: Text('忘记此桌面端'),
                ),
              ],
            ),
        ],
      ),
      bottomNavigationBar:
          _currentTrack == null ? null : _buildMiniPlayer(_currentTrack!),
      body: SafeArea(
        child: _client.isConnected && connection != null
            ? _buildLibrary(connection)
            : _buildConnectState(),
      ),
    );
  }

  Widget _buildConnectState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.devices_other,
                    size: 52,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '连接你的桌面音乐库',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '扫描桌面端二维码即可配对。Tailscale 在线时可跨公网访问，也可继续手动粘贴配对信息。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _scanPairingCode,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('扫描桌面二维码'),
                  ),
                  if (_savedConnection != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _retrySavedConnection,
                      icon: const Icon(Icons.history),
                      label: Text(
                        '重试上次桌面 · ' + _savedConnection!.host,
                      ),
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
                        onPressed: _pastePairingInfo,
                        icon: const Icon(Icons.content_paste),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.error,
                          ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
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

  Widget _buildLibrary(MediaHubConnection connection) {
    return RefreshIndicator(
      onRefresh: _loadTracks,
      color: AppColors.accent,
      backgroundColor: AppColors.bgElevated,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '来自 ' + connection.host,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Chip(label: Text(_connectionLabel(connection.transport))),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _tracks.length.toString() + ' 首可播放音乐',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
            ),
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
            ..._tracks.map(_buildTrackTile),
        ],
      ),
    );
  }

  Widget _buildTrackTile(RemoteAudioTrack track) {
    final selected = _currentTrack?.id == track.id;
    final subtitle = [
      if (track.artist != null && track.artist!.isNotEmpty) track.artist!,
      track.format.toUpperCase(),
      _formatBytes(track.byteLength),
      if (track.hasLyrics) '有歌词',
    ].join(' · ');

    final downloading = _downloadProgress.containsKey(track.id);
    final progress = _downloadProgress[track.id];
    final downloaded = _downloadedPaths.containsKey(track.id);

    return Card(
      color: selected ? AppColors.bgHighlight : null,
      child: ListTile(
        onTap: () => _play(track),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          ),
          child: Icon(
            selected ? Icons.graphic_eq : Icons.music_note,
            color: selected ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (downloading)
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                ),
              )
            else
              IconButton(
                tooltip: downloaded ? '已下载' : '下载到手机',
                onPressed: downloaded ? null : () => _downloadTrack(track),
                icon: Icon(
                  downloaded ? Icons.download_done : Icons.download_outlined,
                ),
              ),
            const Icon(Icons.play_arrow),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPlayer(RemoteAudioTrack track) {
    return StreamBuilder<PlaybackState>(
      stream: _audioService.stateStream,
      initialData: _audioService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PlaybackState.idle();
        final progress = state.duration == null
            ? 0.0
            : state.progressPercent.clamp(0.0, 1.0).toDouble();
        final lyricLine = _currentLyricLine(state.position);

        return Material(
          color: AppColors.bgSurface,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: state.duration == null ? null : progress,
                  minHeight: 2,
                ),
                ListTile(
                  leading: const Icon(Icons.album),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    lyricLine?.text ??
                        (state.formattedPosition +
                            ' / ' +
                            state.formattedDuration),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: state.isBuffering || state.isLoading
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          onPressed: _playPause,
                          icon: Icon(
                            state.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
