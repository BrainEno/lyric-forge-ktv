import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../domain/models/media_hub_connection.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';

class RemoteMediaLibraryScreen extends StatefulWidget {
  const RemoteMediaLibraryScreen({super.key});

  @override
  State<RemoteMediaLibraryScreen> createState() =>
      _RemoteMediaLibraryScreenState();
}

class _RemoteMediaLibraryScreenState extends State<RemoteMediaLibraryScreen> {
  late final MediaHubClientService _client;
  late final AudioPlayerService _audioService;
  final TextEditingController _pairingController = TextEditingController();

  List<RemoteAudioTrack> _tracks = const [];
  RemoteAudioTrack? _currentTrack;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = ServiceLocatorGlobal.I.mediaHubClientService;
    _audioService = ServiceLocatorGlobal.I.audioPlayerService;
    if (_client.isConnected) {
      _loadTracks();
    }
  }

  @override
  void dispose() {
    _pairingController.dispose();
    super.dispose();
  }

  Future<void> _pastePairingInfo() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _pairingController.text = text;
  }

  Future<void> _connect() async {
    final raw = _pairingController.text.trim();
    if (raw.isEmpty || _busy) return;

    final uri = Uri.tryParse(raw);
    if (uri == null) {
      setState(() => _error = '配对信息格式不正确');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _client.connect(uri);
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
      _error = null;
    });

    try {
      final uri = _client.playbackUriFor(track);
      await _audioService.loadAudioUri(uri: uri);
      await _audioService.play();
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

  Future<void> _disconnect() async {
    await _audioService.stop();
    await _client.disconnect();
    if (!mounted) return;
    setState(() {
      _tracks = const [];
      _currentTrack = null;
      _error = null;
    });
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
            IconButton(
              tooltip: '断开连接',
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off),
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
                    '在桌面端打开“远程音乐库”，复制配对信息后粘贴到这里。Tailscale 在线时可跨公网连接。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
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
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.pureWhite,
                            ),
                          )
                        : const Icon(Icons.link),
                    label: Text(_busy ? '连接中...' : '连接桌面端'),
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
              Chip(
                label: Text(_connectionLabel(connection.transport)),
              ),
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
    ].join(' · ');

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
        trailing: const Icon(Icons.play_arrow),
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
                    state.formattedPosition + ' / ' + state.formattedDuration,
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
