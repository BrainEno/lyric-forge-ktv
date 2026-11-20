import '../../../lyrics/domain/models/vocal_check_record.dart';

/// Loudness of a vocal stem, one value per short frame.
///
/// [frameRms] is the root mean square of each frame on a 0–1 full-scale
/// range (one channel, or the channels averaged).
class VocalEnergyEnvelope {
  final Duration frameLength;
  final List<double> frameRms;

  const VocalEnergyEnvelope({
    required this.frameLength,
    required this.frameRms,
  });

  Duration get duration => frameLength * frameRms.length;
}

/// Where a vocal stem has singing, as found by `VocalActivityAnalyzer`.
///
/// Levels are dBFS. [referenceDb] is how loud the singing is (a high
/// percentile of the frames), [floorDb] how quiet the stem gets between
/// phrases, and [thresholdDb] the level from which a frame counts as sung.
class VocalActivityProfile {
  final Duration duration;
  final double referenceDb;
  final double floorDb;
  final double thresholdDb;

  /// Sung stretches in timeline order, never overlapping.
  final List<LyricVocalCheckSpan> regions;

  /// Why the profile must not be used to judge lyrics, or null when it can.
  final VocalActivityUnreliability? unreliability;

  const VocalActivityProfile({
    required this.duration,
    required this.referenceDb,
    required this.floorDb,
    required this.thresholdDb,
    required this.regions,
    this.unreliability,
  });

  bool get isReliable => unreliability == null;

  /// Distance between the singing and the quiet between phrases.
  double get contrastDb => referenceDb - floorDb;

  Duration get voiced =>
      regions.fold(Duration.zero, (sum, region) => sum + region.duration);

  /// How much singing lies between [start] and [end].
  Duration voicedWithin(Duration start, Duration end) {
    if (end <= start) return Duration.zero;
    var total = Duration.zero;
    for (final region in regions) {
      if (region.end <= start) continue;
      if (region.start >= end) break;
      final from = region.start > start ? region.start : start;
      final to = region.end < end ? region.end : end;
      total += to - from;
    }
    return total;
  }

  /// Where the first singing between [start] and [end] begins, or null.
  Duration? firstVoiceIn(Duration start, Duration end) {
    for (final region in regions) {
      if (region.end <= start) continue;
      if (region.start >= end) return null;
      return region.start > start ? region.start : start;
    }
    return null;
  }

  /// Where the last singing between [start] and [end] stops, or null.
  Duration? lastVoiceIn(Duration start, Duration end) {
    for (final region in regions.reversed) {
      if (region.start >= end) continue;
      if (region.end <= start) return null;
      return region.end < end ? region.end : end;
    }
    return null;
  }

  Map<String, Object?> summaryJson() => {
    'durationMs': duration.inMilliseconds,
    'referenceDb': _round(referenceDb),
    'floorDb': _round(floorDb),
    'thresholdDb': _round(thresholdDb),
    'voicedMs': voiced.inMilliseconds,
    'regions': regions.length,
    'unreliability': unreliability?.name,
  };

  static double _round(double value) => (value * 10).roundToDouble() / 10;
}

/// Why a [VocalActivityProfile] cannot tell singing from silence.
enum VocalActivityUnreliability {
  /// Less than a few seconds of audio.
  tooShort,

  /// Practically nothing above digital silence.
  silent,

  /// Loud and quiet frames are too close: not a clean vocal stem (a full mix
  /// imported as the vocal, heavy bleed, or constant noise).
  lowContrast,
}
