import '../../../project/domain/models/lyric_document.dart';
import 'lyric_timeline_validator.dart';

/// How a range of rows is re-timed.
enum LyricTimingShiftMode {
  /// Every start and end in the range moves by the same offset.
  offset,

  /// Two anchor rows are pinned to new start times and every timestamp in
  /// the range is mapped linearly between them, which corrects both an
  /// offset and a tempo drift (a different recording of the song, a sped up
  /// upload, timestamps typed against another edit).
  twoPoint,
}

/// A re-timing of the rows [firstIndex]..[lastIndex] (inclusive).
class LyricTimingShift {
  final LyricTimingShiftMode mode;
  final int firstIndex;
  final int lastIndex;

  /// [LyricTimingShiftMode.offset]: the amount every timestamp moves.
  final Duration delta;

  /// [LyricTimingShiftMode.twoPoint]: the anchor rows and the start times
  /// they should have afterwards.
  final int fromIndex;
  final Duration fromTarget;
  final int toIndex;
  final Duration toTarget;

  const LyricTimingShift.offset({
    required this.firstIndex,
    required this.lastIndex,
    required this.delta,
  }) : mode = LyricTimingShiftMode.offset,
       fromIndex = 0,
       fromTarget = Duration.zero,
       toIndex = 0,
       toTarget = Duration.zero;

  const LyricTimingShift.twoPoint({
    required this.firstIndex,
    required this.lastIndex,
    required this.fromIndex,
    required this.fromTarget,
    required this.toIndex,
    required this.toTarget,
  }) : mode = LyricTimingShiftMode.twoPoint,
       delta = Duration.zero;
}

/// Why a [LyricTimingShift] could not be applied.
enum LyricTimingShiftFailure {
  /// The range is empty or outside the document.
  invalidRange,

  /// An anchor row is outside the document.
  invalidAnchor,

  /// Both anchors start at the same time, so no scale can be derived.
  anchorsCoincide,

  /// The anchors would swap order, or stretch the timeline by more than
  /// [LyricTimingShiftService.maximumScale] in either direction; that is
  /// almost certainly a typing mistake.
  implausibleScale,

  /// The shift changes nothing.
  noChange,
}

/// The outcome of [LyricTimingShiftService.apply].
class LyricTimingShiftResult {
  final LyricDocument? document;
  final LyricTimingShiftFailure? failure;

  /// Rows whose start or end changed.
  final List<int> changedIndices;

  /// Rows that would have started before 0:00 or ended after the audio and
  /// were clamped to that boundary.
  final int clampedCount;

  /// The time scale applied (1.0 for a plain offset).
  final double scale;

  /// Timeline problems the shift creates (for example the shifted range now
  /// overlapping the row before it). Problems that already existed are not
  /// listed.
  final List<TimelineIssue> introducedIssues;

  /// Problems that existed before and are gone afterwards.
  final List<TimelineIssue> resolvedIssues;

  const LyricTimingShiftResult._({
    required this.document,
    required this.failure,
    required this.changedIndices,
    required this.clampedCount,
    required this.scale,
    required this.introducedIssues,
    required this.resolvedIssues,
  });

  const LyricTimingShiftResult.failed(LyricTimingShiftFailure this.failure)
    : document = null,
      changedIndices = const [],
      clampedCount = 0,
      scale = 1,
      introducedIssues = const [],
      resolvedIssues = const [];

  bool get isSuccess => document != null;
}

/// Moves or stretches the timestamps of a range of rows.
///
/// The document's global offset already shifts everything at once; what it
/// cannot do is correct only part of a song (timestamps that drift after an
/// interlude, a second half recognised against a different edit) or a tempo
/// difference. This service handles both:
///
/// * an offset moves every start and end in the range by the same amount;
/// * a two-point calibration pins two anchor rows to new start times and
///   maps every timestamp linearly through them.
///
/// Timestamps are rounded to whole milliseconds. A start that would fall
/// before 0:00 is clamped to 0:00 and an end past a known audio end is
/// clamped to it; a row never ends up shorter than [minimumDuration]. Text,
/// row order and rows outside the range are never touched; the result
/// reports which timeline problems the shift introduced so the user can see,
/// for example, that the range now overlaps the row before it.
class LyricTimingShiftService {
  const LyricTimingShiftService({
    this.validator = const LyricTimelineValidator(),
  });

  final LyricTimelineValidator validator;

  /// Stretching beyond this factor (or shrinking below its inverse) is
  /// rejected as implausible.
  static const double maximumScale = 2.0;

  static const Duration minimumDuration = Duration(milliseconds: 10);

  LyricTimingShiftResult apply(
    LyricDocument document,
    LyricTimingShift shift, {
    Duration? audioDuration,
  }) {
    final lines = document.lines;
    if (lines.isEmpty ||
        shift.firstIndex < 0 ||
        shift.lastIndex >= lines.length ||
        shift.firstIndex > shift.lastIndex) {
      return const LyricTimingShiftResult.failed(
        LyricTimingShiftFailure.invalidRange,
      );
    }

    final Duration Function(Duration) map;
    var scale = 1.0;
    switch (shift.mode) {
      case LyricTimingShiftMode.offset:
        if (shift.delta == Duration.zero) {
          return const LyricTimingShiftResult.failed(
            LyricTimingShiftFailure.noChange,
          );
        }
        map = (time) => time + shift.delta;
      case LyricTimingShiftMode.twoPoint:
        if (shift.fromIndex < 0 ||
            shift.fromIndex >= lines.length ||
            shift.toIndex < 0 ||
            shift.toIndex >= lines.length) {
          return const LyricTimingShiftResult.failed(
            LyricTimingShiftFailure.invalidAnchor,
          );
        }
        final fromSource = lines[shift.fromIndex].startTime;
        final toSource = lines[shift.toIndex].startTime;
        final sourceSpan = toSource - fromSource;
        if (sourceSpan == Duration.zero) {
          return const LyricTimingShiftResult.failed(
            LyricTimingShiftFailure.anchorsCoincide,
          );
        }
        final targetSpan = shift.toTarget - shift.fromTarget;
        scale = targetSpan.inMicroseconds / sourceSpan.inMicroseconds;
        if (scale <= 0 || scale > maximumScale || scale < 1 / maximumScale) {
          return const LyricTimingShiftResult.failed(
            LyricTimingShiftFailure.implausibleScale,
          );
        }
        final factor = scale;
        map = (time) =>
            shift.fromTarget +
            Duration(
              microseconds: ((time - fromSource).inMicroseconds * factor)
                  .round(),
            );
    }

    final next = List<LyricLine>.from(lines);
    final changed = <int>[];
    var clamped = 0;
    for (var index = shift.firstIndex; index <= shift.lastIndex; index++) {
      final line = lines[index];
      var start = _roundToMs(map(line.startTime));
      var end = _roundToMs(map(line.endTime));
      var wasClamped = false;
      if (start.isNegative) {
        // Keep the row's length when it can, so a clamped row still covers
        // the words it had.
        end = end - start;
        start = Duration.zero;
        wasClamped = true;
      }
      if (audioDuration != null && audioDuration > Duration.zero) {
        if (end > audioDuration) {
          end = audioDuration;
          wasClamped = true;
        }
        if (start >= audioDuration - minimumDuration) {
          start = audioDuration - minimumDuration;
          if (start.isNegative) start = Duration.zero;
          wasClamped = true;
        }
      }
      // A row that had a positive length keeps one.
      if (line.endTime > line.startTime && end - start < minimumDuration) {
        end = start + minimumDuration;
      }
      if (wasClamped) clamped++;
      if (start == line.startTime && end == line.endTime) continue;
      next[index] = line.copyWith(startTime: start, endTime: end);
      changed.add(index);
    }

    if (changed.isEmpty) {
      return const LyricTimingShiftResult.failed(
        LyricTimingShiftFailure.noChange,
      );
    }

    final comparison = validator.compare(
      before: lines,
      after: next,
      audioDuration: audioDuration,
      globalOffset: document.globalOffset ?? Duration.zero,
    );
    return LyricTimingShiftResult._(
      document: document.copyWith(lines: next),
      failure: null,
      changedIndices: List.unmodifiable(changed),
      clampedCount: clamped,
      scale: scale,
      introducedIssues: comparison.introduced,
      resolvedIssues: comparison.resolved,
    );
  }

  static Duration _roundToMs(Duration value) =>
      Duration(milliseconds: (value.inMicroseconds / 1000).round());
}

/// Parses a time typed by the user: `1:23.45`, `83.45`, `-0.5`, `1:02:03.5`.
///
/// Returns null for anything else. A leading minus is allowed so the same
/// parser reads offsets.
Duration? parseLyricTimeInput(String raw) {
  var text = raw.trim().replaceAll('：', ':').replaceAll('，', '.');
  if (text.isEmpty) return null;
  var negative = false;
  if (text.startsWith('-') || text.startsWith('−')) {
    negative = true;
    text = text.substring(1).trim();
  } else if (text.startsWith('+')) {
    text = text.substring(1).trim();
  }
  if (text.endsWith('s') || text.endsWith('秒')) {
    text = text.substring(0, text.length - 1).trim();
  }
  final parts = text.split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  final secondsPart = double.tryParse(parts.last);
  if (secondsPart == null || secondsPart.isNaN || secondsPart < 0) return null;
  if (parts.length > 1 && secondsPart >= 60) return null;
  var totalSeconds = secondsPart;
  var multiplier = 60.0;
  for (var index = parts.length - 2; index >= 0; index--) {
    final value = int.tryParse(parts[index].trim());
    if (value == null || value < 0) return null;
    if (index > 0 && value >= 60) return null;
    totalSeconds += value * multiplier;
    multiplier *= 60;
  }
  final milliseconds = (totalSeconds * 1000).round();
  return Duration(milliseconds: negative ? -milliseconds : milliseconds);
}

/// Formats a timestamp the way [parseLyricTimeInput] reads it: `m:ss.cc`.
String formatLyricTimeInput(Duration value) {
  final negative = value.isNegative;
  final totalCentis = (value.inMilliseconds.abs() / 10).round();
  final minutes = totalCentis ~/ 6000;
  final seconds = (totalCentis % 6000) / 100;
  final body = '$minutes:${seconds.toStringAsFixed(2).padLeft(5, '0')}';
  return negative ? '-$body' : body;
}

/// Formats an offset in seconds with a sign: `+1.25 s`, `-0.10 s`.
String formatLyricOffset(Duration value) {
  final seconds = value.inMilliseconds / 1000;
  final sign = value.isNegative ? '-' : '+';
  return '$sign${seconds.abs().toStringAsFixed(2)} s';
}
