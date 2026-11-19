import 'package:flutter/material.dart';

import '../../../../core/navigation/app_chrome_scope.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_button_spinner.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';
import '../local_library_dependencies.dart';
import 'playback_action_feedback.dart';
import 'playback_artwork.dart';
import 'player_bar_semantics.dart';
import 'seekable_progress_bar.dart';

/// Compact Spotify-style player chrome for mobile.
///
/// This intentionally shares the same PlaybackSessionService used by the full
/// player, remote library and desktop player bar. Route changes therefore never
/// create a second playback stack or desynchronised transport state.
class MobileGlobalPlayerBar extends StatefulWidget {
  /// Supplied by the app shell (`lib/app/app.dart`).
  final LocalLibraryDependencies dependencies;

  const MobileGlobalPlayerBar({super.key, required this.dependencies});

  @override
  State<MobileGlobalPlayerBar> createState() => _MobileGlobalPlayerBarState();
}

class _MobileGlobalPlayerBarState extends State<MobileGlobalPlayerBar> {
  late final PlaybackSessionService _session;
  late final AudioPlayerService _audio;

  @override
  void initState() {
    super.initState();
    _session = widget.dependencies.playbackSession;
    _audio = widget.dependencies.audioPlayer;
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
            final playback =
                playbackSnapshot.data ?? const PlaybackState.idle();
            final busy = PlayerBarSemantics.isBusy(playback);
            final subtitle = PlayerBarSemantics.subtitleFor(
              item,
              projectLabel: item.isRemoteStream ? '桌面音乐库' : '本地音乐',
              remoteLabel: '桌面音乐库',
              localLabel: '本地音乐',
            );
            void openNowPlaying() =>
                AppChromeScope.pushNamed<void>(context, Routes.nowPlaying);

            return Material(
              color: AppColors.bgElevated,
              elevation: 12,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SeekableProgressBar.mini(
                      state: playback,
                      onSeek: _session.seek,
                      hitHeight: 28,
                    ),
                    SizedBox(
                      height: 66,
                      child: InkWell(
                        // The title block below carries the label; the
                        // buttons keep their own.
                        excludeFromSemantics: true,
                        onTap: openNowPlaying,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: PlayerBarNowPlayingTarget(
                                  title: item.title,
                                  subtitle: subtitle,
                                  onOpen: openNowPlaying,
                                  child: Row(
                                    children: [
                                      PlaybackArtwork(item: item, size: 48),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: _TitleBlock(
                                          title: item.title,
                                          subtitle: subtitle,
                                        ),
                                      ),
                                    ],
                                  ),
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
                                  tooltip: PlayerBarSemantics.playPause(
                                    playback,
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => runPlaybackActionWithFeedback(
                                          context,
                                          _session.togglePlayPause,
                                        ),
                                  style: AppTheme.playDisc,
                                  icon: busy
                                      ? const AppButtonSpinner()
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

/// Title and subtitle of the mobile bar.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}
