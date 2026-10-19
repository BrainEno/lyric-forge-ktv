import '../../../project/domain/models/lyric_document.dart';
import 'lyric_alignment_service.dart';

/// 一行被参考歌词纠正的记录，用于摘要展示和 metadata 溯源。
class AppliedReferenceCorrection {
  final int asrLineIndex;
  final int referenceIndex;
  final String previousText;
  final String newText;
  final double similarity;
  final bool timingChanged;

  const AppliedReferenceCorrection({
    required this.asrLineIndex,
    required this.referenceIndex,
    required this.previousText,
    required this.newText,
    required this.similarity,
    required this.timingChanged,
  });
}

class ReferenceAlignmentApplyResult {
  final LyricDocument document;
  final List<AppliedReferenceCorrection> corrections;
  final List<int> skippedManuallyEditedIndices;
  final List<int> skippedLowConfidenceIndices;
  final int timingUpdatedCount;
  final int identicalCount;
  final int missingReferenceCount;
  final int unmatchedAsrCount;

  const ReferenceAlignmentApplyResult({
    required this.document,
    required this.corrections,
    required this.skippedManuallyEditedIndices,
    required this.skippedLowConfidenceIndices,
    required this.timingUpdatedCount,
    required this.identicalCount,
    required this.missingReferenceCount,
    required this.unmatchedAsrCount,
  });

  bool get hasChanges => corrections.isNotEmpty || timingUpdatedCount > 0;

  int get correctableCount => corrections.length;
}

/// 把对齐结果安全地写回歌词文档。
///
/// 只修改被采纳行的文本（或时间），不插入漏行、不删除多余行；未匹配的
/// ASR 行保持原样。默认只改文本并保留原时间戳，避免定时参考在断句不一致时
/// 打乱时间轴；调用方可在确认后显式开启 [applyReferenceTiming]。
class ReferenceAlignmentApplier {
  /// 低于该相似度不自动采纳。默认 0.8，界面显示为 80%。
  final double minimumSimilarity;

  const ReferenceAlignmentApplier({this.minimumSimilarity = 0.8})
    : assert(minimumSimilarity >= 0 && minimumSimilarity <= 1);

  ReferenceAlignmentApplyResult apply({
    required LyricDocument document,
    required LyricAlignmentResult alignment,
    bool applyReferenceTiming = false,
    Set<int> protectedLineIndices = const {},
  }) {
    final lines = List<LyricLine>.from(document.lines);
    final corrections = <AppliedReferenceCorrection>[];
    final skippedManuallyEdited = <int>{};
    final skippedLowConfidence = <int>{};
    var timingUpdatedCount = 0;
    var identicalCount = 0;

    for (
      var entryIndex = 0;
      entryIndex < alignment.entries.length;
      entryIndex++
    ) {
      final entry = alignment.entries[entryIndex];
      final asrIndex = entry.asrLineIndex;
      if (asrIndex == null || asrIndex < 0 || asrIndex >= lines.length) {
        continue;
      }

      if (entry.status == ReferenceLineAlignmentStatus.identical) {
        identicalCount++;
      }

      final isReplace = entry.status == ReferenceLineAlignmentStatus.replace;
      final isIdentical =
          entry.status == ReferenceLineAlignmentStatus.identical;
      if (!isReplace && !isIdentical) continue;

      final accepted = isIdentical || entry.similarity >= minimumSimilarity;
      if (!accepted) {
        if (isReplace) skippedLowConfidence.add(asrIndex);
        continue;
      }

      if (protectedLineIndices.contains(asrIndex)) {
        if (isReplace) skippedManuallyEdited.add(asrIndex);
        continue;
      }

      final previousLine = lines[asrIndex];
      var updated = previousLine;
      var textChanged = false;
      if (isReplace) {
        updated = updated.copyWith(text: entry.referenceText, confidence: 100);
        textChanged = true;
      }

      var timingChanged = false;
      if (applyReferenceTiming &&
          entry.referenceHasTimestamp &&
          entry.startTime != null) {
        final timing = _resolveTiming(alignment.entries, entryIndex);
        if (timing != null &&
            (previousLine.startTime != timing.start ||
                previousLine.endTime != timing.end)) {
          updated = updated.copyWith(
            startTime: timing.start,
            endTime: timing.end,
          );
          timingChanged = true;
          timingUpdatedCount++;
        }
      }

      if (!textChanged && !timingChanged) continue;

      lines[asrIndex] = updated;
      if (textChanged) {
        corrections.add(
          AppliedReferenceCorrection(
            asrLineIndex: asrIndex,
            referenceIndex: entry.referenceIndex,
            previousText: previousLine.text,
            newText: entry.referenceText,
            similarity: entry.similarity,
            timingChanged: timingChanged,
          ),
        );
      }
    }

    final sortedProtected = skippedManuallyEdited.toList()..sort();
    final sortedLowConfidence = skippedLowConfidence.toList()..sort();

    return ReferenceAlignmentApplyResult(
      document: document.copyWith(lines: lines),
      corrections: corrections,
      skippedManuallyEditedIndices: sortedProtected,
      skippedLowConfidenceIndices: sortedLowConfidence,
      timingUpdatedCount: timingUpdatedCount,
      identicalCount: identicalCount,
      missingReferenceCount: alignment.missingReferenceIndices.length,
      unmatchedAsrCount: alignment.unmatchedAsrIndices.length,
    );
  }

  ({Duration start, Duration end})? _resolveTiming(
    List<LyricAlignmentEntry> entries,
    int entryIndex,
  ) {
    final entry = entries[entryIndex];
    final start = entry.startTime;
    if (start == null) return null;

    final nonNegativeStart = start.isNegative ? Duration.zero : start;
    var end = entry.endTime;
    if (end == null || end <= nonNegativeStart) {
      end =
          _nextTimedStart(entries, entryIndex + 1, nonNegativeStart) ??
          nonNegativeStart + const Duration(seconds: 5);
      if (end <= nonNegativeStart) {
        end = nonNegativeStart + const Duration(milliseconds: 500);
      }
    }

    return (start: nonNegativeStart, end: end);
  }

  Duration? _nextTimedStart(
    List<LyricAlignmentEntry> entries,
    int fromIndex,
    Duration currentStart,
  ) {
    for (var index = fromIndex; index < entries.length; index++) {
      final candidate = entries[index];
      if (!candidate.referenceHasTimestamp || candidate.startTime == null) {
        continue;
      }
      if (candidate.startTime! > currentStart) return candidate.startTime;
    }
    return null;
  }
}
