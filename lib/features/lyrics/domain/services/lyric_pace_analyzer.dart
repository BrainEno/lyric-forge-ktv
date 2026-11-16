import '../../../project/domain/models/lyric_document.dart';
import '../models/timing_provenance.dart';
import 'lyric_line_structure_service.dart';
import 'lyric_timeline_validator.dart';

/// Which way a row's singing pace is off.
enum LyricPaceIssueKind {
  /// Far more text than the row's time allows: the end was cut early, the
  /// start is late, or recognition invented words.
  crowded,

  /// Far too little text for the row's time: the row runs across an
  /// interlude, starts too early, or recognition dropped words.
  sparse,
}

/// One row whose pace is far from the song's own.
class LyricPaceIssue {
  final int index;
  final LyricPaceIssueKind kind;
  final LyricLine before;

  /// Sung units per second in this row.
  final double rate;

  /// How long the row's text takes at the song's median pace.
  final Duration expected;

  /// A proposed end time that brings the row back to a plausible pace, or
  /// null when only a person can tell what is wrong (no room to extend, or
  /// the row is hand-timed).
  final Duration? proposedEnd;

  const LyricPaceIssue({
    required this.index,
    required this.kind,
    required this.before,
    required this.rate,
    required this.expected,
    required this.proposedEnd,
  });

  bool get fixable => proposedEnd != null;

  /// How many times faster (crowded) or slower (sparse) than the median.
  double factor(double medianRate) {
    if (medianRate <= 0 || rate <= 0) return 0;
    return kind == LyricPaceIssueKind.crowded
        ? rate / medianRate
        : medianRate / rate;
  }
}

/// The pace check for a whole document.
class LyricPacePlan {
  /// The song's median pace in sung units per second.
  final double medianRate;

  /// Whether [medianRate] was measured on enough rows; when false it is the
  /// default pace and the check is less reliable.
  final bool measured;

  final List<LyricPaceIssue> issues;

  const LyricPacePlan({
    required this.medianRate,
    required this.measured,
    required this.issues,
  });

  static const LyricPacePlan empty = LyricPacePlan(
    medianRate: LyricPaceAnalyzer.defaultRate,
    measured: false,
    issues: [],
  );

  /// Positions in [issues] that carry a proposed fix.
  List<int> get fixablePositions => [
    for (var position = 0; position < issues.length; position++)
      if (issues[position].fixable) position,
  ];

  /// [document] with the proposed ends at [selectedPositions] applied.
  /// Adjusted rows are recorded as [LyricTimingProvenance.autoRepaired],
  /// like the timeline check's repairs.
  LyricDocument applyTo(LyricDocument document, Set<int> selectedPositions) {
    final lines = List<LyricLine>.from(document.lines);
    final provenance = <String, Object?>{
      if (document.metadata[kLyricTimingProvenanceKey] case final Map raw)
        for (final entry in raw.entries)
          if (entry.key is String) entry.key as String: entry.value,
    };
    var changed = false;
    for (final position in selectedPositions) {
      if (position < 0 || position >= issues.length) continue;
      final issue = issues[position];
      final end = issue.proposedEnd;
      if (end == null || issue.index >= lines.length) continue;
      final line = lines[issue.index];
      lines[issue.index] = line.copyWith(endTime: end);
      final id = line.id;
      if (id != null) provenance[id] = LyricTimingProvenance.autoRepaired.name;
      changed = true;
    }
    if (!changed) return document;
    return document.copyWith(
      lines: lines,
      metadata: {...document.metadata, kLyricTimingProvenanceKey: provenance},
    );
  }
}

/// Finds rows sung implausibly fast or slow compared with the rest of the
/// song.
///
/// A recognised draft's text and timing fail together in tell-tale ways: a
/// row that "sings" twelve characters in one second usually had its end cut
/// at a breath or got words that were never sung; a row that holds four
/// characters for nine seconds usually swallowed an interlude or lost the
/// words of a whole phrase. Absolute limits would misjudge ballads and rap
/// alike, so the check measures the song's own median pace (sung units per
/// second, Han characters weigh 1 and Latin letters 0.5) and flags rows far
/// from it:
///
/// * rows with less than [minimumWeight] units are skipped — a held "啊"
///   is supposed to be slow;
/// * [LyricPaceIssueKind.crowded] — faster than [crowdedFactor] × the median and at least
///   [crowdedMinimumRate]; when the next row leaves room, the end is moved
///   later, towards the median duration, but never closer than the
///   validator's minimum gap to the next row;
/// * [LyricPaceIssueKind.sparse] — slower than [sparseFactor] × the median and at least
///   [sparseMinimumExcess] longer than the median duration; the end is
///   pulled in to [sparseSlack] × the median duration, so the lyric stops
///   showing during the interlude;
/// * rows whose timing provenance is manual (hand-timed or tapped) are
///   reported without a proposal, as are rows in [protectedIndices].
class LyricPaceAnalyzer {
  const LyricPaceAnalyzer({
    this.structure = const LyricLineStructureService(),
  });

  final LyricLineStructureService structure;

  /// Rows lighter than this are never judged.
  static const double minimumWeight = 3;

  /// Fewer measurable rows than this and [defaultRate] is used instead.
  static const int minimumSamples = 6;

  /// About 0.35 s per Han character, the timeline check's estimate.
  static const double defaultRate = 1 / 0.35;

  static const double crowdedFactor = 2.2;
  static const double crowdedMinimumRate = 6;
  static const double sparseFactor = 0.4;
  static const Duration sparseMinimumExcess = Duration(seconds: 2);
  static const double sparseSlack = 1.4;

  /// A proposal that moves the end by less than this is not worth a row.
  static const Duration minimumChange = Duration(milliseconds: 300);

  LyricPacePlan plan(
    LyricDocument document, {
    Set<int> protectedIndices = const {},
  }) {
    final lines = document.lines;
    if (lines.isEmpty) return LyricPacePlan.empty;

    final weights = [for (final line in lines) structure.sungWeight(line.text)];
    final rates = <double>[];
    for (var index = 0; index < lines.length; index++) {
      final rate = _rate(lines[index], weights[index]);
      if (rate != null) rates.add(rate);
    }
    final measured = rates.length >= minimumSamples;
    final median = measured ? _median(rates) : defaultRate;
    if (median <= 0) return LyricPacePlan.empty;

    final manual = _manualIds(document);
    final issues = <LyricPaceIssue>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final rate = _rate(line, weights[index]);
      if (rate == null) continue;
      final expected = Duration(
        microseconds: (weights[index] / median * 1000000).round(),
      );
      final duration = line.endTime - line.startTime;
      final locked =
          protectedIndices.contains(index) ||
          (line.id != null && manual.contains(line.id));

      if (rate > median * crowdedFactor && rate >= crowdedMinimumRate) {
        issues.add(
          LyricPaceIssue(
            index: index,
            kind: LyricPaceIssueKind.crowded,
            before: line,
            rate: rate,
            expected: expected,
            proposedEnd: locked ? null : _extendedEnd(lines, index, expected),
          ),
        );
      } else if (rate < median * sparseFactor &&
          duration - expected >= sparseMinimumExcess) {
        final target = Duration(
          microseconds: (expected.inMicroseconds * sparseSlack).round(),
        );
        final end = _roundToTenMs(line.startTime + target);
        issues.add(
          LyricPaceIssue(
            index: index,
            kind: LyricPaceIssueKind.sparse,
            before: line,
            rate: rate,
            expected: expected,
            proposedEnd: locked || line.endTime - end < minimumChange
                ? null
                : end,
          ),
        );
      }
    }
    return LyricPacePlan(medianRate: median, measured: measured, issues: issues);
  }

  /// Sung units per second, or null for rows that are not judged.
  double? _rate(LyricLine line, double weight) {
    if (weight < minimumWeight) return null;
    final duration = line.endTime - line.startTime;
    if (duration <= Duration.zero) return null;
    return weight / (duration.inMicroseconds / 1000000);
  }

  /// A later end for a crowded row, bounded by the next row, or null when
  /// there is no worthwhile room.
  Duration? _extendedEnd(List<LyricLine> lines, int index, Duration expected) {
    final line = lines[index];
    var end = line.startTime + expected;
    Duration? nextStart;
    for (var next = index + 1; next < lines.length; next++) {
      if (lines[next].text.trim().isEmpty) continue;
      nextStart = lines[next].startTime;
      break;
    }
    if (nextStart != null) {
      final limit = nextStart - LyricTimelineValidator.defaultMinGap;
      if (end > limit) end = limit;
    }
    end = _roundToTenMs(end);
    if (end - line.endTime < minimumChange) return null;
    return end;
  }

  static Set<String> _manualIds(LyricDocument document) {
    final raw = document.metadata[kLyricTimingProvenanceKey];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String &&
            entry.value == LyricTimingProvenance.manual.name)
          entry.key as String,
    };
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static Duration _roundToTenMs(Duration value) =>
      Duration(milliseconds: (value.inMilliseconds / 10).round() * 10);
}
