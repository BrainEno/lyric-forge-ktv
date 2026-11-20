import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_lyrics_availability.dart';
import '../../domain/repositories/local_media_collection_repository.dart';
import '../../domain/services/playback_session_service.dart';
import '../playback_screen_dependencies.dart';
import '../widgets/now_playing_lyrics_project_action.dart';
import '../widgets/playback_artwork.dart';
import '../widgets/playback_facts.dart';
import '../widgets/playback_mode_controls.dart';
import '../widgets/playback_queue_panel.dart';
import '../widgets/seekable_progress_bar.dart';
import '../widgets/session_transport_bar.dart';

/// Full-screen view of the app-scoped playback session.
///
/// Unlike [QuickPlayScreen], this screen is source-agnostic: local files,
/// desktop Media Hub streams and lyric projects all share the same transport
/// state while presenting source-appropriate metadata and artwork.
class NowPlayingScreen extends StatefulWidget {
  /// Supplied by the routing table (`lib/app/playback_assembly.dart`).
  final NowPlayingDependencies dependencies;

  const NowPlayingScreen({super.key, required this.dependencies});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  late final PlaybackSessionService _session;
  late final AudioPlayerService _audio;

  @override
  void initState() {
    super.initState();
    final dependencies = widget.dependencies;
    _session = dependencies.playbackSession;
    _audio = dependencies.audioPlayer;
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
            collectionRepository: widget.dependencies.localCollectionRepository,
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
                      final playback =
                          playbackSnapshot.data ?? _audio.currentState;
                      return _NowPlayingBody(
                        item: item,
                        lyricsResolver: widget.dependencies.lyricsResolver,
                        immersiveKtv: widget.dependencies.immersiveKtv,
                        collectionRepository:
                            widget.dependencies.localCollectionRepository,
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
    final layout = AppResponsive.of(context);
    return AppEmptyState(
      icon: Icons.music_off_rounded,
      title: '当前没有正在播放的音乐',
      actions: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(
              layout.minimumInteractiveExtent,
              layout.minimumInteractiveExtent,
            ),
          ),
          onPressed: () =>
              Navigator.pushReplacementNamed(context, Routes.library),
          icon: const Icon(Icons.library_music_rounded),
          label: const Text('打开音乐库'),
        ),
      ],
    );
  }
}

class _NowPlayingBody extends StatelessWidget {
  final PlaybackItem item;
  final PlaybackLyricsResolver lyricsResolver;
  final ImmersiveKtvDependencies immersiveKtv;
  final LocalMediaCollectionRepository collectionRepository;
  final PlaybackSessionState sessionState;
  final PlaybackState playback;
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;

  const _NowPlayingBody({
    required this.item,
    required this.lyricsResolver,
    required this.immersiveKtv,
    required this.collectionRepository,
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
          lyricsResolver: lyricsResolver,
          immersiveKtv: immersiveKtv,
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
                        collectionRepository: collectionRepository,
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
  final PlaybackLyricsResolver lyricsResolver;
  final ImmersiveKtvDependencies immersiveKtv;
  final PlaybackSessionState sessionState;
  final PlaybackState playback;
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;

  const _NowPlayingCard({
    required this.item,
    required this.lyricsResolver,
    required this.immersiveKtv,
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
    final origin = PlaybackOrigin.of(item);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: layout.isCompact ? 560 : 820,
        maxHeight: layout.isCompact ? double.infinity : 760,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(
          layout.isCompact ? AppSpacing.md : AppSpacing.xl,
        ),
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
              lyricsResolver: lyricsResolver,
              immersiveKtv: immersiveKtv,
              album: albumText,
              origin: origin,
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
  final PlaybackLyricsResolver lyricsResolver;
  final ImmersiveKtvDependencies immersiveKtv;
  final String? album;
  final PlaybackOrigin origin;
  final PlaybackSessionState sessionState;
  final PlaybackState playback;
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;

  const _NowPlayingDetails({
    required this.item,
    required this.lyricsResolver,
    required this.immersiveKtv,
    required this.album,
    required this.origin,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          origin.label,
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
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        PlaybackFactBadges(item: item, showMissingLyrics: false),
        const SizedBox(height: AppSpacing.md),
        SeekableProgressBar(state: playback, onSeek: session.seek),
        const SizedBox(height: AppSpacing.sm),
        SessionTransportBar(
          session: session,
          playback: playback,
          queue: sessionState,
          onSeekBack: onSeekBack,
          onSeekForward: onSeekForward,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Icon(
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
            Icon(
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
            NowPlayingLyricsProjectAction(
              item: item,
              lyricsResolver: lyricsResolver,
              immersiveKtv: immersiveKtv,
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
    return RepaintBoundary(
      child: PlaybackArtwork(item: item, borderRadius: AppSpacing.radiusXLarge),
    );
  }
}
