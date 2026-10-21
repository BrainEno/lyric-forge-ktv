import '../../../project/domain/models/lyric_document.dart';

enum LyricTimelineAutoRepairType { trimOverlap, trimAudioBoundary }

class LyricTimelineAutoRepair {
  final int lineIndex;
  final Duration previousEndTime;
  final Duration repairedEndTime;
  final LyricTimelineAutoRepairType type;

  const LyricTimelineAutoRepair({
    required this.lineIndex,
    required this.previousEndTime,
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

/// Conservatively repairs intervals when surrounding start times provide an
/// unambiguous boundary. It never reorders lines or moves a start timestamp.
/// Duplicate or descending starts remain unresolved for manual review.
class LyricTimelineAutoRepairService {
  static const Duration minimumDuration = Duration(milliseconds: 10);

  const LyricTimelineAutoRepairService();

  LyricTimelineAutoRepairResult repair({
    required List<LyricLine> lines,
    required Set<int> changedLineIndices,
    Set<int> protectedLineIndices = const {},
    Duration? audioDuration,
  }) {
    final repaired = List<LyricLine>.from(lines);
    final repairs = <LyricTimelineAutoRepair>[];

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

      repairs.add(
        LyricTimelineAutoRepair(
          lineIndex: index,
          previousEndTime: current.endTime,
          repairedEndTime: next.startTime,
          type: LyricTimelineAutoRepairType.trimOverlap,
        ),
      );
      repaired[index] = current.copyWith(endTime: next.startTime);
    }

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

        repairs.add(
          LyricTimelineAutoRepair(
            lineIndex: index,
            previousEndTime: current.endTime,
            repairedEndTime: audioDuration,
            type: LyricTimelineAutoRepairType.trimAudioBoundary,
          ),
        );
        repaired[index] = current.copyWith(endTime: audioDuration);
      }
    }

    return LyricTimelineAutoRepairResult(
      lines: repaired,
      repairs: repairs,
    );
  }
}
