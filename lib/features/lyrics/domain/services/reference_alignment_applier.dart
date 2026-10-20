import '../../../project/domain/models/lyric_document.dart';
import 'lyric_alignment_service.dart';
import 'reference_timeline_completion_service.dart';

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

/// 一行从参考歌词补入的新歌词，用于摘要展示和 metadata 溯源。
class AppliedReferenceInsertion {
  /// 参考行在原始参考列表中的索引。
  final int referenceIndex;

  /// 插入到该 ASR 行之前；等于文档行数时表示追加到末尾。
  ///
  /// 这是原始文档中的位置，与 [asrLineIndex]（插入后的最终索引）不同，
  /// 供调用方把会话级手动编辑索引迁移到补行后的文档，避免保护错位。
  final int insertBeforeAsrLineIndex;

  /// 插入后在文档中的最终行索引。
  final int asrLineIndex;

  final String text;
  final Duration startTime;
  final Duration endTime;
  final bool requiresConfirmation;

  const AppliedReferenceInsertion({
    required this.referenceIndex,
    required this.insertBeforeAsrLineIndex,
    required this.asrLineIndex,
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.requiresConfirmation,
  });
}

class ReferenceAlignmentApplyResult {
  final LyricDocument document;
  final List<AppliedReferenceCorrection> corrections;
  final List<AppliedReferenceInsertion> insertions;
  final List<int> skippedManuallyEditedIndices;
  final List<int> skippedLowConfidenceIndices;

  /// 逐行确认时用户主动跳过、但相似度其实达到阈值的行。
  final List<int> skippedBySelectionIndices;

  final int timingUpdatedCount;
  final int identicalCount;
  final int missingReferenceCount;
  final int unmatchedAsrCount;

  const ReferenceAlignmentApplyResult({
    required this.document,
    required this.corrections,
    required this.insertions,
    required this.skippedManuallyEditedIndices,
    required this.skippedLowConfidenceIndices,
    required this.skippedBySelectionIndices,
    required this.timingUpdatedCount,
    required this.identicalCount,
    required this.missingReferenceCount,
    required this.unmatchedAsrCount,
  });

  bool get hasChanges =>
      corrections.isNotEmpty || insertions.isNotEmpty || timingUpdatedCount > 0;

  int get correctableCount => corrections.length;

  int get insertedCount => insertions.length;
}

/// 把对齐结果安全地写回歌词文档。
///
/// 默认只修改被采纳行的文本（或时间），不删除多余行，未匹配的 ASR 行保持
/// 原样；默认只改文本并保留原时间戳，避免定时参考在断句不一致时打乱时间轴，
/// 调用方可在确认后显式开启 [applyReferenceTiming]。
///
/// [acceptedReferenceIndices] 为 null 时按 [minimumSimilarity] 自动采纳；
/// 非 null 时只采纳集合中的参考行（逐行确认界面使用），此时低于阈值的行也
/// 可以被显式采纳。时间轴是整体开关，与逐行文字选择无关。
///
/// [acceptedMissingReferenceIndices] 非空时，把对应漏行按
/// [ReferenceTimelineCompletionService] 推断的位置与时间插入；null 或空集合
/// 保持旧行为（不插入漏行）。
class ReferenceAlignmentApplier {
  /// 低于该相似度不自动采纳。默认 0.8，界面显示为 80%。
  final double minimumSimilarity;

  /// 漏行插入计划的计算服务；测试或调用方可替换。
  final ReferenceTimelineCompletionService completionService;

  const ReferenceAlignmentApplier({
    this.minimumSimilarity = 0.8,
    this.completionService = const ReferenceTimelineCompletionService(),
  }) : assert(minimumSimilarity >= 0 && minimumSimilarity <= 1);

  ReferenceAlignmentApplyResult apply({
    required LyricDocument document,
    required LyricAlignmentResult alignment,
    bool applyReferenceTiming = false,
    Set<int>? acceptedReferenceIndices,
    Set<int>? acceptedMissingReferenceIndices,
    Set<int> protectedLineIndices = const {},
  }) {
    final lines = List<LyricLine>.from(document.lines);
    final corrections = <AppliedReferenceCorrection>[];
    final skippedManuallyEdited = <int>{};
    final skippedLowConfidence = <int>{};
    final skippedBySelection = <int>{};
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

      // 漏行由插入计划处理；低置信度与歧义匹配不自动采纳，需显式确认。
      if (entry.status == ReferenceLineAlignmentStatus.missing) continue;

      final isReplace = entry.status == ReferenceLineAlignmentStatus.replace;
      final isIdentical =
          entry.status == ReferenceLineAlignmentStatus.identical;

      // 逐行确认模式（acceptedReferenceIndices != null）：仅采纳显式选中的行。
      // 自动模式：replace 高置信匹配自动采纳；lowConfidence/ambiguous 不自动采纳。
      bool acceptedForText;
      if (isIdentical) {
        acceptedForText = true;
      } else if (acceptedReferenceIndices != null) {
        acceptedForText = acceptedReferenceIndices.contains(
          entry.referenceIndex,
        );
      } else {
        acceptedForText = isReplace && entry.similarity >= minimumSimilarity;
      }

      if (!acceptedForText) {
        if (entry.status == ReferenceLineAlignmentStatus.lowConfidence) {
          skippedLowConfidence.add(asrIndex);
        } else if (acceptedReferenceIndices != null) {
          skippedBySelection.add(asrIndex);
        } else if (isReplace && entry.similarity < minimumSimilarity) {
          // 自动模式下因阈值收紧未采纳的 replace 行，记为低置信度跳过。
          skippedLowConfidence.add(asrIndex);
        }
      }

      if (protectedLineIndices.contains(asrIndex)) {
        if (isReplace && acceptedForText) skippedManuallyEdited.add(asrIndex);
        continue;
      }

      final previousLine = lines[asrIndex];
      var updated = previousLine;
      var textChanged = false;
      if (acceptedForText && !isIdentical) {
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
    final sortedBySelection = skippedBySelection.toList()..sort();

    final insertions = <AppliedReferenceInsertion>[];
    final finalLines = <LyricLine>[];
    final selectedMissing = acceptedMissingReferenceIndices;
    if (selectedMissing != null && selectedMissing.isNotEmpty) {
      final plan = completionService.buildPlan(
        document: document,
        alignment: alignment,
      );
      final byPosition = <int, List<ReferenceLineCompletionInsertion>>{};
      for (final insertion in plan.insertions) {
        if (!selectedMissing.contains(insertion.referenceIndex)) continue;
        final position = insertion.insertBeforeAsrLineIndex.clamp(
          0,
          lines.length,
        );
        byPosition.putIfAbsent(position, () => []).add(insertion);
      }

      var finalIndex = 0;
      for (var index = 0; index <= lines.length; index++) {
        final pending = byPosition[index];
        if (pending != null) {
          for (final insertion in pending) {
            finalLines.add(
              LyricLine(
                text: insertion.text,
                startTime: insertion.startTime,
                endTime: insertion.endTime,
              ),
            );
            insertions.add(
              AppliedReferenceInsertion(
                referenceIndex: insertion.referenceIndex,
                insertBeforeAsrLineIndex: insertion.insertBeforeAsrLineIndex,
                asrLineIndex: finalIndex,
                text: insertion.text,
                startTime: insertion.startTime,
                endTime: insertion.endTime,
                requiresConfirmation: insertion.requiresConfirmation,
              ),
            );
            finalIndex++;
          }
        }
        if (index < lines.length) {
          finalLines.add(lines[index]);
          finalIndex++;
        }
      }
    } else {
      finalLines.addAll(lines);
    }

    return ReferenceAlignmentApplyResult(
      document: document.copyWith(lines: finalLines),
      corrections: corrections,
      insertions: insertions,
      skippedManuallyEditedIndices: sortedProtected,
      skippedLowConfidenceIndices: sortedLowConfidence,
      skippedBySelectionIndices: sortedBySelection,
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
