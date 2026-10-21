import '../../../project/domain/models/lyric_document.dart';
import '../models/timing_provenance.dart';

enum LyricTimelineAutoRepairType {
  trimOverlap,
  trimAudioBoundary,
  redistributeEstimate,
}

class LyricTimelineAutoRepair {
  final int lineIndex;
  final Duration previousStartTime;
  final Duration previousEndTime;
  final Duration repairedStartTime;
  final Duration repairedEndTime;
  final LyricTimelineAutoRepairType type;

  const LyricTimelineAutoRepair({
    required this.lineIndex,
    required this.previousStartTime,
    required this.previousEndTime,
    required this.repairedStartTime,
    required this.repairedEndTime,
    required this.type,
  });
}

class LyricTimelineAutoRepairResult {
  final List<LyricLine> lines;
  final List<LyricTimelineAutoRepair> repairs;

  const LyricTimelineAutoRepairResult({
    required this.lines,
    required this.repairs,
  });
}

/// Applies only deterministic, non-destructive repairs:
/// - trim an affected line's end to the next strictly later line start;
/// - clip an affected tail line at a known audio boundary when duration remains;
/// - redistribute estimated/interpolated inserted lines inside the fixed anchors
///   when their current intervals conflict with lyric order.
///
/// Start times of reference-timed, original ASR, or manually-timed lines are never
/// moved. If estimated lines cannot fit a positive interval between anchors, the
/// service leaves them unchanged so validation can report the unresolved conflict.
class LyricTimelineAutoRepairService {
  static const Duration minimumDuration = Duration(milliseconds: 10);
  static const Duration defaultTailDuration = Duration(seconds: 5);

  const LyricTimelineAutoRepairService();

  LyricTimelineAutoRepairResult repair({
    required List<LyricLine> lines,
    required Set<int> changedLineIndices,
    Map<int, LyricTimingProvenance> timingProvenanceByLineIndex = const {},
    Set<int> protectedLineIndices = const {},
    Duration? audioDuration,
  }) {
    final repaired = List<LyricLine>.from(lines);
    final repairs = <LyricTimelineAutoRepair>[];

    void record({
      required int index,
      required LyricLine before,
      required LyricLine after,
      required LyricTimelineAutoRepairType type,
    }) {
      if (before.startTime == after.startTime &&
          before.endTime == after.endTime) {
        return;
      }
      repairs.add(
        LyricTimelineAutoRepair(
          lineIndex: index,
          previousStartTime: before.startTime,
          previousEndTime: before.endTime,
          repairedStartTime: after.startTime,
          repairedEndTime: after.endTime,
          type: type,
        ),
      );
      repaired[index] = after;
    }

    // First fix overlaps that have an unambiguous next-line start boundary.
    for (var index = 0; index < repaired.length - 1; index++) {
      if (!changedLineIndices.contains(index) &&
          !changedLineIndices.contains(index + 1)) {
        continue;
      }

      final current = repaired[index];
      final next = repaired[index + 1];
      if (protectedLineIndices.contains(index) ||
          current.startTime >= next.startTime ||
          current.endTime <= next.startTime ||
          next.startTime - current.startTime < minimumDuration) {
        continue;
      }

      record(
        index: index,
        before: current,
        after: current.copyWith(endTime: next.startTime),
        type: LyricTimelineAutoRepairType.trimOverlap,
      );
    }

    // A known audio duration is a hard boundary, but only clip lines whose
    // starts remain valid and whose clipped duration is still positive.
    if (audioDuration != null) {
      for (var index = 0; index < repaired.length; index++) {
        final current = repaired[index];
        final hasChangedContext = changedLineIndices.contains(index) ||
            repairs.any((repair) => repair.lineIndex == index);
        if (!hasChangedContext ||
            protectedLineIndices.contains(index) ||
            current.startTime >= audioDuration ||
            current.endTime <= audioDuration ||
            audioDuration - current.startTime < minimumDuration) {
          continue;
        }

        record(
          index: index,
          before: current,
          after: current.copyWith(endTime: audioDuration),
          type: LyricTimelineAutoRepairType.trimAudioBoundary,
        );
      }
    }

    final estimatedIndices = timingProvenanceByLineIndex.entries
        .where(
          (entry) =>
              entry.key >= 0 &&
              entry.key < repaired.length &&
              !protectedLineIndices.contains(entry.key) &&
              (entry.value == LyricTimingProvenance.interpolated ||
                  entry.value == LyricTimingProvenance.estimatedTail),
        )
        .map((entry) => entry.key)
        .toSet();

    // Only redistribute an estimated run when its current timing is actually
    // conflicting. Reliable neighboring ASR/reference timestamps remain anchors.
    var index = 0;
    while (index < repaired.length) {
      if (!estimatedIndices.contains(index)) {
        index++;
        continue;
      }

      final runStart = index;
      while (index < repaired.length && estimatedIndices.contains(index)) {
        index++;
      }
      final runEndExclusive = index;
      if (!_runNeedsRedistribution(
        repaired,
        runStart: runStart,
        runEndExclusive: runEndExclusive,
      )) {
        continue;
      }

      final runCount = runEndExclusive - runStart;
      final leftBoundary = runStart > 0
          ? repaired[runStart - 1].endTime
          : Duration.zero;
      final rightBoundary = runEndExclusive < repaired.length
          ? repaired[runEndExclusive].startTime
          : _tailBoundary(
              start: leftBoundary,
              lineCount: runCount,
              audioDuration: audioDuration,
            );
      final available = rightBoundary - leftBoundary;
      if (available < minimumDuration * runCount) {
        continue;
      }

      final weights = <int>[
        for (var runIndex = runStart; runIndex < runEndExclusive; runIndex++)
          repaired[runIndex].text.runes.length.clamp(1, 100000).toInt(),
      ];
      final totalWeight = weights.fold<int>(0, (sum, value) => sum + value);
      final extraAvailable = available - minimumDuration * runCount;
      var cumulativeWeight = 0;

      for (var offset = 0; offset < runCount; offset++) {
        final lineIndex = runStart + offset;
        final before = repaired[lineIndex];
        final weight = weights[offset];
        final start = leftBoundary +
            minimumDuration * offset +
            Duration(
              microseconds:
                  extraAvailable.inMicroseconds * cumulativeWeight ~/ totalWeight,
            );
        cumulativeWeight += weight;
        final end = leftBoundary +
            minimumDuration * (offset + 1) +
            Duration(
              microseconds:
                  extraAvailable.inMicroseconds * cumulativeWeight ~/ totalWeight,
            );
        if (end - start < minimumDuration) {
          // Do not partially repair a run when the available slot cannot be
          // represented safely. Validation will show the remaining conflict.
          break;
        }
        record(
          index: lineIndex,
          before: before,
          after: before.copyWith(startTime: start, endTime: end),
          type: LyricTimelineAutoRepairType.redistributeEstimate,
        );
      }
    }

    return LyricTimelineAutoRepairResult(
      lines: repaired,
      repairs: repairs,
    );
  }

  bool _runNeedsRedistribution(
    List<LyricLine> lines, {
    required int runStart,
    required int runEndExclusive,
  }) {
    final left = runStart > 0 ? lines[runStart - 1] : null;
    final right = runEndExclusive < lines.length
        ? lines[runEndExclusive]
        : null;

    for (var index = runStart; index < runEndExclusive; index++) {
      final line = lines[index];
      if (line.endTime <= line.startTime) return true;
      if (index == runStart) {
        if (left != null &&
            (line.startTime < left.endTime ||
                line.startTime < left.startTime)) {
          return true;
        }
      } else {
        final previous = lines[index - 1];
        if (line.startTime <= previous.startTime ||
            line.startTime < previous.endTime) {
          return true;
        }
      }
      if (right != null &&
          index == runEndExclusive - 1 &&
          (line.endTime > right.startTime ||
              line.startTime >= right.startTime)) {
        return true;
      }
    }
    return false;
  }

  Duration _tailBoundary({
    required Duration start,
    required int lineCount,
    required Duration? audioDuration,
  }) {
    final nominal = start + defaultTailDuration * lineCount;
    if (audioDuration != null && audioDuration < nominal) {
      return audioDuration;
    }
    return nominal;
  }
}
