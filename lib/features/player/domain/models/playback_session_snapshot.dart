import '../services/playback_session_service.dart';

/// Durable representation of the app-scoped playback session.
///
/// The snapshot deliberately records a paused/restorable session rather than an
/// autoplay instruction. On application launch the queue and position are
/// restored, but audio only starts after an explicit user action.
class PlaybackSessionSnapshot {
  final PlaybackSessionState state;
  final Duration position;
  final List<String>? unshuffledOrder;
  final DateTime savedAt;

  const PlaybackSessionSnapshot({
    required this.state,
    required this.position,
    required this.savedAt,
    this.unshuffledOrder,
  });
}
