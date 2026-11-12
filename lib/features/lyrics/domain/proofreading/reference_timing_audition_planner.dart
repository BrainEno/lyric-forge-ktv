import '../services/lyric_audition_window_service.dart';
import 'reference_forced_alignment_planner.dart';

/// The observable player state at the instant before an audition starts.
///
/// Paths are compared exactly, deliberately not canonicalized or substituted:
/// the verified file must be the file the active player reports using.
class ReferenceTimingPlaybackSnapshot {
  final String? projectId;
  final String? audioPath;
  final bool isRemote;
  final bool isLoading;
  final Duration? duration;

  const ReferenceTimingPlaybackSnapshot({
    required this.projectId,
    required this.audioPath,
    this.isRemote = false,
    this.isLoading = false,
    this.duration,
  });
}

enum ReferenceTimingAuditionFailure {
  wrongProject,
  remoteSource,
  sourceLoading,
  sourceUnavailable,
  wrongAudio,
  invalidEvidence,
  beyondAudioDuration,
}

class ReferenceTimingAuditionPlan {
  final LyricAuditionWindow? window;
  final ReferenceTimingAuditionFailure? failure;

  const ReferenceTimingAuditionPlan._({this.window, this.failure});

  bool get canAudition => window != null && failure == null;
}

/// Plans a bounded audition in absolute audio coordinates, without applying it.
///
/// The evidence is already absolute: document global offsets must never be
/// added. The player must already be on the verified local source, so previewing
/// does not unexpectedly replace the user's queue or switch their audio stem.
/// File hashing and editor revision checks are the caller's responsibility.
class ReferenceTimingAuditionPlanner {
  static const preRoll = Duration(milliseconds: 250);

  const ReferenceTimingAuditionPlanner();

  ReferenceTimingAuditionPlan plan({
    required ReferenceForcedTimingProposal evidence,
    required String projectId,
    required String verifiedAudioPath,
    required ReferenceTimingPlaybackSnapshot playback,
    Duration? verifiedAudioDuration,
  }) {
    ReferenceTimingAuditionPlan reject(ReferenceTimingAuditionFailure reason) =>
        ReferenceTimingAuditionPlan._(failure: reason);

    if (playback.projectId != projectId) {
      return reject(ReferenceTimingAuditionFailure.wrongProject);
    }
    if (playback.isRemote) {
      return reject(ReferenceTimingAuditionFailure.remoteSource);
    }
    if (playback.isLoading) {
      return reject(ReferenceTimingAuditionFailure.sourceLoading);
    }
    final actual = playback.audioPath;
    if (actual == null || actual.isEmpty || verifiedAudioPath.isEmpty) {
      return reject(ReferenceTimingAuditionFailure.sourceUnavailable);
    }
    if (actual != verifiedAudioPath) {
      return reject(ReferenceTimingAuditionFailure.wrongAudio);
    }
    if (evidence.start.isNegative || evidence.end <= evidence.start) {
      return reject(ReferenceTimingAuditionFailure.invalidEvidence);
    }
    for (final duration in [verifiedAudioDuration, playback.duration]) {
      if (duration != null &&
          (duration <= Duration.zero || evidence.end > duration)) {
        return reject(ReferenceTimingAuditionFailure.beyondAudioDuration);
      }
    }
    final window = const LyricAuditionWindowService().calculate(
      lineStart: evidence.start,
      lineEnd: evidence.end,
      preRoll: preRoll,
    );
    if (!window.canAudition || window.endAt == null) {
      return reject(ReferenceTimingAuditionFailure.invalidEvidence);
    }
    return ReferenceTimingAuditionPlan._(window: window);
  }
}
