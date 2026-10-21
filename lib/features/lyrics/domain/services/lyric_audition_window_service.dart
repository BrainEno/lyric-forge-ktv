/// A bounded audio-time window used to audition a single lyric line.
class LyricAuditionWindow {
  /// Position at which playback should begin, including the pre-roll.
  final Duration startAt;

  /// Position at which playback should pause, or null when the line has no
  /// trustworthy end timestamp.
  final Duration? endAt;

  /// False when the lyric's effective start is at or beyond the known duration.
  final bool canAudition;

  const LyricAuditionWindow({
    required this.startAt,
    required this.endAt,
    required this.canAudition,
  });

  bool get hasKnownEnd => endAt != null;
}

/// Calculates an audition interval in audio playback coordinates.
///
/// Lyric timestamps are document coordinates. The document's global offset is
/// applied to both edges before clamping to audio bounds, matching the editor's
/// existing effective-start semantics. No input lyric or document is mutated.
class LyricAuditionWindowService {
  static const Duration defaultPreRoll = Duration(seconds: 1);

  const LyricAuditionWindowService();

  LyricAuditionWindow calculate({
    required Duration lineStart,
    required Duration? lineEnd,
    Duration globalOffset = Duration.zero,
    Duration? audioDuration,
    Duration preRoll = defaultPreRoll,
  }) {
    final boundedAudioDuration =
        audioDuration != null && audioDuration > Duration.zero
        ? audioDuration
        : null;

    var effectiveStart = lineStart + globalOffset;
    if (effectiveStart.isNegative) effectiveStart = Duration.zero;

    final safePreRoll = preRoll.isNegative ? Duration.zero : preRoll;
    var startAt = effectiveStart - safePreRoll;
    if (startAt.isNegative) startAt = Duration.zero;

    if (boundedAudioDuration != null &&
        effectiveStart >= boundedAudioDuration) {
      return LyricAuditionWindow(
        startAt: boundedAudioDuration,
        endAt: boundedAudioDuration,
        canAudition: false,
      );
    }

    // A present but invalid end timestamp must not turn a row audition into an
    // unbounded whole-track playback. A genuinely missing end remains usable
    // with manual pause only.
    if (lineEnd != null && lineEnd <= lineStart) {
      return LyricAuditionWindow(
        startAt: startAt,
        endAt: null,
        canAudition: false,
      );
    }

    Duration? endAt;
    if (lineEnd != null) {
      final rawEffectiveEnd = lineEnd + globalOffset;
      if (rawEffectiveEnd <= Duration.zero) {
        return LyricAuditionWindow(
          startAt: startAt,
          endAt: null,
          canAudition: false,
        );
      }
      var effectiveEnd = rawEffectiveEnd;
      if (boundedAudioDuration != null &&
          effectiveEnd > boundedAudioDuration) {
        effectiveEnd = boundedAudioDuration;
      }
      if (effectiveEnd > startAt) endAt = effectiveEnd;
    }

    return LyricAuditionWindow(
      startAt: startAt,
      endAt: endAt,
      canAudition: true,
    );
  }
}
