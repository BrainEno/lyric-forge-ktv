import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transfer/data/services/remote_playback_queue_builder.dart';
import '../../../transfer/domain/services/media_transfer_service.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/remote_playback_source.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/playback_queue_panel.dart';

class RemoteStreamNowPlayingScreen extends StatefulWidget {
  const RemoteStreamNowPlayingScreen({super.key});

  @override
  State<RemoteStreamNowPlayingScreen> createState() =>
      _RemoteStreamNowPlayingScreenState();
}

class _RemoteStreamNowPlayingScreenState
    extends State<RemoteStreamNowPlayingScreen> {
  late final PlaybackSessionService _session;
  late final AudioPlayerService _audio;
  late final MediaTransferService _transfers;
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _session = services.playbackSessionService;
    _audio = services.audioPlayerService;
    _transfers = services.mediaTransferService;
    _sessionSubscription = _session.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _seekRelative(Duration delta) async {
    final state = _audio.currentState;
    final duration = state.duration;
    var target = state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration != null && target > duration) target = duration;
    await _session.seek(target);
  }

  Future<void> _downloadCurrent() async {
    if (_downloading) return;
    final item = _session.currentState.currentItem;
    if (item == null) return;
    final track = RemotePlaybackQueueBuilder.trackFromItem(item);
    if (track == null) return;
    setState(() => _downloading = true);
    try {
      final result = await _transfers.downloadRemoteTracks([track]);
      if (!mounted) return;
      if (result.completed.isNotEmpty) {
        _show('已下载并导入本地音乐库');
      } else {
        final message = result.failed.isNotEmpty
            ? result.failed.first.error ?? '下载失败'
            : '下载失败';
        _show(message, error: true);
      }
    } catch (error) {
      _show('下载失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
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
    final sessionState = _session.currentState;
    final item = sessionState.currentItem;
    if (item == null || !RemotePlaybackSource.isRemote(item.audioAsset)) {
      return const Scaffold(
        backgroundColor: AppColors.bgBase,
        body: Center(child: Text('当前没有远程播放项目')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        title: const Text('正在播放'),
      ),
      body: SafeArea(
        child: StreamBuilder<PlaybackState>(
          stream: _audio.stateStream,
          initialData: _audio.currentState,
          builder: (context, snapshot) {
            final playback = snapshot.data ?? const PlaybackState.idle();
            return LayoutBuilder(
              builder: (context, constraints) {
                final layout = AppResponsive.fromConstraints(constraints);
                final player = _RemotePlayerCard(
                  layout: layout,
                  item: item,
                  playback: playback,
                  session: _session,
                  audio: _audio,
                  downloading: _downloading,
                  onBack10: () => _seekRelative(const Duration(seconds: -10)),
                  onForward10: () => _seekRelative(const Duration(seconds: 10)),
                  onDownload: _downloadCurrent,
                );

                if (!layout.supportsTwoPane) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.all(layout.pageGutter),
                    child: Column(
                      children: [
                        player,
                        SizedBox(height: layout.sectionGap),
                        PlaybackQueuePanel(
                          session: _session,
                          height: layout.isShort ? 220 : 320,
                          allowClearAll: true,
                        ),
                      ],
                    ),
                  );
                }

                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: layout.playerContentMaxWidth),
                    child: Padding(
                      padding: EdgeInsets.all(layout.pageGutter),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: SingleChildScrollView(child: player)),
                          SizedBox(width: layout.sectionGap),
                          SizedBox(
                            width: layout.sidePanelWidth,
                            child: PlaybackQueuePanel(
                              session: _session,
                              height: (constraints.maxHeight - layout.pageGutter * 2)
                                  .clamp(280.0, 720.0)
                                  .toDouble(),
                              allowClearAll: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }
}

class _RemotePlayerCard extends StatelessWidget {
  final AppLayoutSpec layout;
  final PlaybackItem item;
  final PlaybackState playback;
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final bool downloading;
  final VoidCallback onBack10;
  final VoidCallback onForward10;
  final VoidCallback onDownload;

  const _RemotePlayerCard({
    required this.layout,
    required this.item,
    required this.playback,
    required this.session,
    required this.audio,
    required this.downloading,
    required this.onBack10,
    required this.onForward10,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final album = item.audioAsset.metadata['album'];
    final titleStyle = (layout.isCompact
            ? Theme.of(context).textTheme.headlineSmall
            : Theme.of(context).textTheme.headlineMedium)
        ?.copyWith(fontWeight: FontWeight.w900, height: 1.08);
    final artworkExtent =
        layout.playerArtworkMaxExtent.clamp(200.0, 340.0).toDouble();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(layout.isCompact ? AppSpacing.md : AppSpacing.xl),
        child: Column(
          children: [
            SizedBox(
              width: artworkExtent,
              height: artworkExtent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
                ),
                child: const Icon(
                  Icons.cast_connected_rounded,
                  size: 92,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(height: layout.sectionGap),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '电脑音乐 · 在线流播',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(item.title, style: titleStyle),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item.artist?.trim().isNotEmpty == true ? item.artist! : '未知艺人',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
            if (album is String && album.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  album.trim(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ),
            ],
            SizedBox(height: layout.isShort ? AppSpacing.md : AppSpacing.xl),
            _Progress(playback: playback, onSeek: session.seek),
            const SizedBox(height: AppSpacing.md),
            _Transport(
              layout: layout,
              playback: playback,
              session: session,
              onBack10: onBack10,
              onForward10: onForward10,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Icon(
                  Icons.volume_down_rounded,
                  color: AppColors.textTertiary,
                ),
                Expanded(
                  child: Slider(
                    value: playback.volume.clamp(0.0, 1.0).toDouble(),
                    onChanged: audio.setVolume,
                  ),
                ),
                const Icon(
                  Icons.volume_up_rounded,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: downloading ? null : onDownload,
                icon: downloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(downloading ? '下载中...' : '下载当前歌曲到本机'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  final PlaybackState playback;
  final ValueChanged<Duration> onSeek;

  const _Progress({required this.playback, required this.onSeek});

  @override
  Widget build(BuildContext context) {
    final duration = playback.duration ?? Duration.zero;
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final value = playback.position.inMilliseconds
        .clamp(0, maxMs.toInt())
        .toDouble();
    return Column(
      children: [
        Slider(
          value: value,
          max: maxMs,
          onChanged: duration > Duration.zero
              ? (next) => onSeek(Duration(milliseconds: next.round()))
              : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(playback.formattedPosition),
            Text(playback.formattedDuration),
          ],
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  final AppLayoutSpec layout;
  final PlaybackState playback;
  final PlaybackSessionService session;
  final VoidCallback onBack10;
  final VoidCallback onForward10;

  const _Transport({
    required this.layout,
    required this.playback,
    required this.session,
    required this.onBack10,
    required this.onForward10,
  });

  @override
  Widget build(BuildContext context) {
    final queue = session.currentState;
    final secondary = layout.minimumInteractiveExtent;
    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback? action,
    ) =>
        SizedBox(
          width: secondary,
          height: secondary,
          child: IconButton(
            onPressed: action,
            tooltip: tooltip,
            icon: Icon(icon),
          ),
        );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      children: [
        button(
          Icons.skip_previous_rounded,
          '上一首',
          queue.canSkipPrevious ? session.skipPrevious : null,
        ),
        button(Icons.replay_10_rounded, '后退 10 秒', onBack10),
        SizedBox(
          width: layout.primaryPlayerControlExtent,
          height: layout.primaryPlayerControlExtent,
          child: IconButton(
            onPressed: playback.isLoading || playback.isBuffering
                ? null
                : session.togglePlayPause,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.pureWhite,
              foregroundColor: AppColors.pureBlack,
            ),
            icon: playback.isPlaying
                ? const Icon(Icons.pause_rounded)
                : const Icon(Icons.play_arrow_rounded),
          ),
        ),
        button(Icons.forward_10_rounded, '前进 10 秒', onForward10),
        button(
          Icons.skip_next_rounded,
          '下一首',
          queue.canSkipNext ? session.skipNext : null,
        ),
      ],
    );
  }
}
