import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';
import 'playback_action_feedback.dart';

/// Compact Spotify-style player chrome for mobile.
///
/// This intentionally shares the same PlaybackSessionService used by the full
/// player, remote library and desktop player bar. Route changes therefore never
/// create a second playback stack or desynchronised transport state.
class MobileGlobalPlayerBar extends StatefulWidget {
  const MobileGlobalPlayerBar({super.key});

  @override
  State<MobileGlobalPlayerBar> createState() => _MobileGlobalPlayerBarState();
}

class _MobileGlobalPlayerBarState extends State<MobileGlobalPlayerBar> {
  late final PlaybackSessionService _session;
  late final AudioPlayerService _audio;

  @override
  void initState() {
    super.initState();
    _session = ServiceLocatorGlobal.I.playbackSessionService;
    _audio = ServiceLocatorGlobal.I.audioPlayerService;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackSessionState>(
      stream: _session.stateStream,
      initialData: _session.currentState,
      builder: (context, sessionSnapshot) {
        final session = sessionSnapshot.data ?? const PlaybackSessionState();
        final item = session.currentItem;
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: _audio.stateStream,
          initialData: _audio.currentState,
          builder: (context, playbackSnapshot) {
            final playback = playbackSnapshot.data ?? const PlaybackState.idle();
            final progress = playback.duration == null
                ? 0.0
                : playback.progressPercent.clamp(0.0, 1.0).toDouble();
            final rawRemoteArtwork = item.audioAsset.metadata['remoteArtworkUri'];
            final remoteArtwork = rawRemoteArtwork is String
                ? Uri.tryParse(rawRemoteArtwork)
                : null;

            return Material(
              color: AppColors.bgElevated,
              elevation: 12,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: AppColors.bgHighlight,
                      valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                    ),
                    SizedBox(
                      height: 66,
                      child: InkWell(
                        onTap: () => Navigator.pushNamed(context, Routes.nowPlaying),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          child: Row(
                            children: [
                              _MobileArtwork(
                                path: item.artworkPath,
                                remoteUri: remoteArtwork,
                                remote: item.isRemoteStream,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.artist?.trim().isNotEmpty == true
                                          ? item.artist!
                                          : item.isRemoteStream
                                              ? '桌面音乐库'
                                              : '本地音乐',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppColors.textTertiary),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '上一首',
                                onPressed: session.canSkipPrevious
                                    ? () => runPlaybackActionWithFeedback(
                                          context,
                                          _session.skipPrevious,
                                        )
                                    : null,
                                icon: const Icon(Icons.skip_previous_rounded),
                              ),
                              SizedBox(
                                width: 44,
                                height: 44,
                                child: IconButton(
                                  tooltip: playback.isPlaying ? '暂停' : '播放',
                                  onPressed: playback.isBuffering || playback.isLoading
                                      ? null
                                      : () => runPlaybackActionWithFeedback(
                                            context,
                                            _session.togglePlayPause,
                                          ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppColors.pureWhite,
                                    foregroundColor: AppColors.pureBlack,
                                    disabledBackgroundColor: AppColors.textDisabled,
                                  ),
                                  icon: playback.isBuffering || playback.isLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.pureBlack,
                                          ),
                                        )
                                      : Icon(
                                          playback.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                        ),
                                ),
                              ),
                              IconButton(
                                tooltip: '下一首',
                                onPressed: session.canSkipNext
                                    ? () => runPlaybackActionWithFeedback(
                                          context,
                                          _session.skipNext,
                                        )
                                    : null,
                                icon: const Icon(Icons.skip_next_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MobileArtwork extends StatelessWidget {
  final String? path;
  final Uri? remoteUri;
  final bool remote;

  const _MobileArtwork({
    required this.path,
    required this.remoteUri,
    required this.remote,
  });

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final hasArtwork = file != null && file.existsSync();
    final fallback = Icon(
      remote ? Icons.cloud_rounded : Icons.music_note_rounded,
      color: AppColors.textSecondary,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      child: Container(
        width: 48,
        height: 48,
        color: AppColors.bgSurface,
        child: hasArtwork
            ? Image.file(file!, fit: BoxFit.cover)
            : remoteUri == null
                ? fallback
                : Image.network(
                    remoteUri.toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => fallback,
                  ),
      ),
    );
  }
}
