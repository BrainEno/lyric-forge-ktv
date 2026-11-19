import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/playback_session_service.dart';
import 'transport_bar.dart';

/// A [TransportBar] wired to the playback session: play/pause toggles it,
/// previous and next skip through its queue and are disabled when the queue
/// cannot move.
///
/// Now Playing and quick play each had a private wrapper doing exactly this
/// (`_TransportControls` and `_Transport`); one of them read the queue from
/// the session stream and the other from the session, so they could
/// disagree for a frame. Both use this widget now.
class SessionTransportBar extends StatelessWidget {
  const SessionTransportBar({
    super.key,
    required this.session,
    required this.playback,
    this.queue,
    this.onSeekBack,
    this.onSeekForward,
    this.layout,
    this.wrap = false,
  });

  final PlaybackSessionService session;

  /// Player state; loading and buffering show the busy play button.
  final PlaybackState playback;

  /// Queue snapshot from a session stream. Defaults to
  /// [PlaybackSessionService.currentState].
  final PlaybackSessionState? queue;

  final VoidCallback? onSeekBack;
  final VoidCallback? onSeekForward;

  /// See [TransportBar.layout].
  final AppLayoutSpec? layout;

  /// See [TransportBar.wrap].
  final bool wrap;

  /// Whether [playback] should show the busy play button.
  static bool isBusy(PlaybackState playback) =>
      playback.isBuffering || playback.isLoading;

  @override
  Widget build(BuildContext context) {
    final state = queue ?? session.currentState;
    return TransportBar(
      layout: layout,
      wrap: wrap,
      isPlaying: playback.isPlaying,
      isBusy: isBusy(playback),
      onPlayPause: session.togglePlayPause,
      onPrevious: state.canSkipPrevious ? session.skipPrevious : null,
      onNext: state.canSkipNext ? session.skipNext : null,
      onSeekBack: onSeekBack,
      onSeekForward: onSeekForward,
    );
  }
}
