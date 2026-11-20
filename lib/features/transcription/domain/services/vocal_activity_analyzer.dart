import 'dart:math' as math;

import '../../../lyrics/domain/models/vocal_check_record.dart';
import '../models/vocal_activity.dart';

/// Finds the sung stretches of a vocal stem from its loudness (D-044).
///
/// A separated vocal stem is close to silent wherever nobody sings, so
/// loudness alone separates singing from the rest. Thresholds are relative to
/// the song: a frame is sung when it is within [rangeDb] of the singing's
/// level (the [referencePercentile] of the frames), never below
/// [absoluteFloorDb], and clearly above the quiet between phrases. Short
/// gaps (breaths, stops) are bridged and isolated blips dropped.
///
/// A stem where loud and quiet frames are too close is reported as
/// unreliable instead of being guessed at: it is not a clean vocal stem.
class VocalActivityAnalyzer {
  const VocalActivityAnalyzer({
    this.referencePercentile = 0.95,
    this.floorPercentile = 0.10,
    this.rangeDb = 30,
    this.absoluteFloorDb = -55,
    this.floorMarginDb = 6,
    this.minimumContrastDb = 18,
    this.bridgeGap = const Duration(milliseconds: 250),
    this.minimumRegion = const Duration(milliseconds: 100),
    this.minimumDuration = const Duration(seconds: 3),
    this.minimumAudible = const Duration(milliseconds: 500),
  });

  final double referencePercentile;
  final double floorPercentile;
  final double rangeDb;
  final double absoluteFloorDb;
  final double floorMarginDb;
  final double minimumContrastDb;
  final Duration bridgeGap;
  final Duration minimumRegion;
  final Duration minimumDuration;
  final Duration minimumAudible;

  /// Frames at or below this are digital silence and do not count towards
  /// the singing's level.
  static const double silenceDb = -90;

  static double toDb(double rms) =>
      rms <= 0 ? -120.0 : math.max(-120.0, 20 * math.log(rms) / math.ln10);

  VocalActivityProfile analyze(VocalEnergyEnvelope envelope) {
    final frame = envelope.frameLength;
    final duration = envelope.duration;
    final db = [for (final rms in envelope.frameRms) toDb(rms)];

    VocalActivityProfile unreliable(
      VocalActivityUnreliability reason, {
      double reference = -120,
      double floor = -120,
    }) => VocalActivityProfile(
      duration: duration,
      referenceDb: reference,
      floorDb: floor,
      thresholdDb: reference,
      regions: const [],
      unreliability: reason,
    );

    if (frame <= Duration.zero || duration < minimumDuration) {
      return unreliable(VocalActivityUnreliability.tooShort);
    }
    final audible = db.where((value) => value > silenceDb).toList()..sort();
    if (frame * audible.length < minimumAudible) {
      return unreliable(VocalActivityUnreliability.silent);
    }
    final reference = _percentile(audible, referencePercentile);
    final floor = _percentile(List.of(db)..sort(), floorPercentile);
    if (reference - floor < minimumContrastDb) {
      return unreliable(
        VocalActivityUnreliability.lowContrast,
        reference: reference,
        floor: floor,
      );
    }
    final threshold = [
      reference - rangeDb,
      absoluteFloorDb,
      floor + floorMarginDb,
    ].reduce(math.max);

    // Runs of sung frames, as frame indices [start, end).
    final runs = <List<int>>[];
    int? runStart;
    for (var index = 0; index <= db.length; index++) {
      final sung = index < db.length && db[index] >= threshold;
      if (sung) {
        runStart ??= index;
      } else if (runStart != null) {
        runs.add([runStart, index]);
        runStart = null;
      }
    }

    final bridgeFrames = _frames(bridgeGap, frame);
    final merged = <List<int>>[];
    for (final run in runs) {
      if (merged.isNotEmpty && run[0] - merged.last[1] <= bridgeFrames) {
        merged.last[1] = run[1];
      } else {
        merged.add(List.of(run));
      }
    }
    final minimumFrames = math.max(1, _frames(minimumRegion, frame));
    final regions = [
      for (final run in merged)
        if (run[1] - run[0] >= minimumFrames)
          LyricVocalCheckSpan(frame * run[0], frame * run[1]),
    ];

    return VocalActivityProfile(
      duration: duration,
      referenceDb: reference,
      floorDb: floor,
      thresholdDb: threshold,
      regions: regions,
    );
  }

  static int _frames(Duration span, Duration frame) =>
      (span.inMicroseconds / frame.inMicroseconds).round();

  /// [sorted] must be ascending and non-empty.
  static double _percentile(List<double> sorted, double fraction) {
    final position = (sorted.length - 1) * fraction.clamp(0.0, 1.0);
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    final weight = position - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  }
}
