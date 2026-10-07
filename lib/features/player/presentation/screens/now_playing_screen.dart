import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/playback_mode_controls.dart';
import '../widgets/playback_queue_panel.dart';

/// Full-screen view of the app-scoped playback session.
///
/// Unlike [QuickPlayScreen], this screen is source-agnostic: local files,
/// desktop Media Hub streams and lyric projects all share the same transport
/// state while presenting source-appropriate metadata and artwork.
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  late final PlaybackSessionService _session;
  late final AudioPlayerService _audio;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _session = services.playbackSessionService;
    _audio = services.audioPlayerService;
  }

  Future<void> _seekRelative(Duration delta) async {
    final state = _audio.currentState;
    var target = state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    final duration = state.duration;
    if (duration != null && target > duration) target = duration;
    await _session.seek(target);
  }

  Future<void> _showQueue() async {
    final height = (MediaQuery.sizeOf(context).height * 0.68)
        .clamp(320.0, 620.0)
        .toDouble();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: PlaybackQueuePanel(
            session: _session,
            height: height,
            allowClearAll: true,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackSessionState>(
      stream: _session.stateStream,
      initialData: _session.currentState,
      builder: (context, sessionSnapshot) {
        final session = sessionSnapshot.data ?? _session.currentState;
        final item = session.currentItem;

        return Scaffold(
          backgroundColor: AppColors.bgBase,
          appBar: AppBar(
            backgroundColor: AppColors.bgBase,
            title: const Text('正在播放'),
            actions: [
              if (item != null)
                IconButton(
                  onPressed: _showQueue,
                  tooltip: '播放队列',
                  icon: const Icon(Icons.queue_music_rounded),
                ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
          body: SafeArea(
            child: item == null
                ? const _EmptyNowPlaying()
                : StreamBuilder<PlaybackState>(
                    stream: _audio.stateStream,
                    initialData: _audio.currentState,
                    builder: (context, playbackSnapshot) {
                      final playback = playbackSnapshot.data ?? _audio.currentState;
                      return _NowPlayingBody(
                        item: item,
                        sessionState: session,
                        playback: playback,
                        session: _session,
                        audio: _audio,
                        onSeekBack: () =>
                            _seekRelative(const Duration(seconds: -10)),
                        onSeekForward: () =>
                            _seekRelative(const Duration(seconds: 10)),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _EmptyNowPlaying extends StatelessWidget {
  const _EmptyNowPlaying();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.music_off_rounded,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '当前没有正在播放的音乐',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushReplacementNamed(
                context,
                Routes.library,
              ),
              icon: const Icon(Icons.library_music_rounded),
              label: const Text('打开音乐库'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingBody extends StatelessWidget {
  final PlaybackItem item;
  final PlaybackSessionState sessionState;
  final PlaybackState playback;
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;

  const _NowPlayingBody({
    required this.item,
    required this.sessionState,
    required this.playback,
    required this.session,
    required this.audio,
    required this.onSeekBack,
    required this.onSeekForward,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final content = _NowPlayingCard(
          item: item,
          sessionState: sessionState,
          playback: playback,
          session: session,
          audio: audio,
          onSeekBack: onSeekBack,
          onSeekForward: onSeekForward,
        );

        if (layout.supportsTwoPane) {
          final queueHeight = constraints.maxHeight.isFinite
              ? (constraints.maxHeight - layout.pageGutter * 2)
                  .clamp(360.0, 760.0)
                  .toDouble()
              : 560.0;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
              child: Padding(
                padding: EdgeInsets.all(layout.pageGutter),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: content),
                    SizedBox(width: layout.sectionGap),
                    SizedBox(
                      width: layout.sidePanelWidth,
                      child: PlaybackQueuePanel(
                        session: session,
                        height: queueHeight,
                        allowClearAll: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.all(layout.pageGutter),
          child: Center(child: content),
        );
      },
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  final PlaybackItem item;
  final PlaybackSessionState sessionState;
  final PlaybackState playback;
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;

  const _NowPlayingCard({
    required this.item,
    required this.sessionState,
    required this.playback,
    required this.session,
    required this.audio,
    required this.onSeekBack,
    required this.onSeekForward,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final album = item.audioAsset.metadata['album'];
    final albumText = album is String && album.trim().isNotEmpty
        ? album.trim()
        : null;
    final source = _sourcePresentation(item);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: layout.isCompact ? 560 : 820,
        maxHeight: layout.isCompact ? double.infinity : 760,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(layout.isCompact ? AppSpacing.md : AppSpacing.xl),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
          border: Border.all(color: AppColors.borderMuted),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final vertical = layout.isCompact || constraints.maxWidth < 680;
            final details = _NowPlayingDetails(
              item: item,
              album: albumText,
              source: source,
              sessionState: sessionState,
              playback: playback,
              session: session,
              audio: audio,
              onSeekBack: onSeekBack,
              onSeekForward: onSeekForward,
            );
            if (vertical) {
              final artworkExtent = constraints.maxHeight.isFinite
                  ? (constraints.maxHeight * 0.42)
                      .clamp(150.0, 340.0)
                      .toDouble()
                  : (constraints.maxWidth - AppSpacing.md * 2)
                      .clamp(180.0, 340.0)
                      .toDouble();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Center(
                      child: SizedBox(
                        width: artworkExtent,
                        height: artworkExtent,
                        child: _PlaybackArtwork(item: item),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  details,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  height: 300,
                  child: _PlaybackArtwork(item: item),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NowPlayingDetails extends StatelessWidget {
  final PlaybackItem item;
  final String? album;
  final ({String label, String chip}) source;
  final PlaybackSessionState sessionState;
  final PlaybackState playback;
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;

  const _NowPlayingDetails({
    required this.item,
    required this.album,
    required this.source,
    required this.sessionState,
    required this.playback,
    required this.session,
    required this.audio,
    required this.onSeekBack,
    required this.onSeekForward,
  });

  @override
  Widget build(BuildContext context) {
    final artist = item.artist?.trim();
    final format = item.audioAsset.format.trim().toUpperCase();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          source.label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.08,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          artist?.isNotEmpty == true ? artist! : '未知艺人',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
        if (album != null) ...[
          const SizedBox(height: 2),
          Text(
            album!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textTertiary),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (format.isNotEmpty) _InfoChip(format),
            _InfoChip(source.chip),
            if (item.hasLyrics) const _InfoChip('LYRICS'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _NowPlayingProgress(playback: playback, onSeek: session.seek),
        const SizedBox(height: AppSpacing.sm),
        _TransportControls(
          sessionState: sessionState,
          playback: playback,
          session: session,
          onSeekBack: onSeekBack,
          onSeekForward: onSeekForward,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            const Icon(
              Icons.volume_down_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
            Expanded(
              child: Slider(
                value: playback.volume.clamp(0.0, 1.0).toDouble(),
                min: 0,
                max: 1,
                onChanged: audio.setVolume,
              ),
            ),
            const Icon(
              Icons.volume_up_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
        Row(
          children: [
            PlaybackModeControls(session: session, compact: true),
            const Spacer(),
            if (item.projectId != null)
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(
                  context,
                  Routes.playerPath(item.projectId!),
                ),
                icon: const Icon(Icons.lyrics_rounded),
                label: const Text('打开工程播放器'),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlaybackArtwork extends StatelessWidget {
  final PlaybackItem item;

  const _PlaybackArtwork({required this.item});

  @override
  Widget build(BuildContext context) {
    final localPath = item.artworkPath?.trim().isNotEmpty == true
        ? item.artworkPath!.trim()
        : item.audioAsset.thumbnailPath?.trim();
    final local = localPath == null ? null : File(localPath);
    final hasLocal = local != null && local.existsSync();
    final remote = _remoteArtworkUri(item);

    final fallback = Container(
      color: AppColors.bgSurface,
      child: Icon(
        item.isRemoteStream ? Icons.cloud_rounded : Icons.album_rounded,
        size: 92,
        color: AppColors.textSecondary,
      ),
    );

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.playerGradient),
          child: hasLocal
              ? Image.file(local!, fit: BoxFit.cover)
              : remote != null
                  ? Image.network(
                      remote.toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => fallback,
                    )
                  : fallback,
        ),
      ),
    );
  }
}

class _NowPlayingProgress extends StatefulWidget {
  final PlaybackState playback;
  final ValueChanged<Duration> onSeek;

  const _NowPlayingProgress({
    required this.playback,
    required this.onSeek,
  });

  @override
  State<_NowPlayingProgress> createState() => _NowPlayingProgressState();
}

class _NowPlayingProgressState extends State<_NowPlayingProgress> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final duration = widget.playback.duration;
    final rawMax = duration?.inMilliseconds.toDouble() ?? 1.0;
    final max = rawMax <= 0 ? 1.0 : rawMax;
    final current = widget.playback.position.inMilliseconds
        .toDouble()
        .clamp(0.0, max)
        .toDouble();
    final value = (_dragValue ?? current).clamp(0.0, max).toDouble();
    final position = _dragValue == null
        ? widget.playback.position
        : Duration(milliseconds: value.round());

    return Column(
      children: [
        Slider(
          value: value,
          min: 0,
          max: max,
          onChangeStart: duration == null
              ? null
              : (next) => setState(() => _dragValue = next),
          onChanged: duration == null
              ? null
              : (next) => setState(() => _dragValue = next),
          onChangeEnd: duration == null
              ? null
              : (next) {
                  setState(() => _dragValue = null);
                  widget.onSeek(Duration(milliseconds: next.round()));
                },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(position),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textTertiary),
            ),
            Text(
              _formatDuration(duration ?? Duration.zero),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ],
    );
  }
}

class _TransportControls extends StatelessWidget {
  final PlaybackSessionState sessionState;
  final PlaybackState playback;
  final PlaybackSessionService session;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;

  const _TransportControls({
    required this.sessionState,
    required this.playback,
    required this.session,
    required this.onSeekBack,
    required this.onSeekForward,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: sessionState.canSkipPrevious ? session.skipPrevious : null,
          tooltip: '上一首',
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        IconButton(
          onPressed: onSeekBack,
          tooltip: '后退 10 秒',
          icon: const Icon(Icons.replay_10_rounded),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 58,
          height: 58,
          child: IconButton(
            onPressed: playback.isBuffering || playback.isLoading
                ? null
                : session.togglePlayPause,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.pureWhite,
              foregroundColor: AppColors.pureBlack,
              disabledBackgroundColor: AppColors.textDisabled,
            ),
            icon: playback.isBuffering || playback.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.pureBlack,
                    ),
                  )
                : Icon(
                    playback.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 34,
                  ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          onPressed: onSeekForward,
          tooltip: '前进 10 秒',
          icon: const Icon(Icons.forward_10_rounded),
        ),
        IconButton(
          onPressed: sessionState.canSkipNext ? session.skipNext : null,
          tooltip: '下一首',
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgHighlight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

({String label, String chip}) _sourcePresentation(PlaybackItem item) {
  if (item.projectId != null) {
    return (label: '歌词工程', chip: 'PROJECT');
  }
  if (item.isRemoteStream) {
    return (label: '桌面音乐库', chip: 'REMOTE');
  }
  return (label: '本地音乐', chip: 'LOCAL');
}

Uri? _remoteArtworkUri(PlaybackItem item) {
  final raw = item.audioAsset.metadata['remoteArtworkUri'];
  if (raw is! String || raw.trim().isEmpty) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '${duration.inMinutes}:$seconds';
}
