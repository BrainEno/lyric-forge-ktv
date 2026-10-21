import '../../../project/domain/models/lyric_document.dart';
import '../models/timing_provenance.dart';
import 'lyric_alignment_service.dart';
import 'lyric_timeline_validator.dart';
import 'lyric_timeline_auto_repair_service.dart';
import 'reference_timeline_completion_service.dart';

/// 一行被参考歌词纠正的记录，用于摘要展示和 metadata 溯源。
class AppliedReferenceCorrection {
  final int asrLineIndex;
  final int referenceIndex;
  final String previousText;
  final String newText;
  final double similarity;
  final bool timingChanged;

  /// 本次写入的时间来源；没有改动时间或未采用参考时间轴时为 null。
  final LyricTimingProvenance? timingProvenance;

  const AppliedReferenceCorrection({
    required this.asrLineIndex,
    required this.referenceIndex,
    required this.previousText,
    required this.newText,
    required this.similarity,
    required this.timingChanged,
    this.timingProvenance,
  });
}

/// 一行从参考歌词补入的新歌词，用于摘要展示和 metadata 溯源。
class AppliedReferenceInsertion {
  /// 参考行在原始参考列表中的索引。
  final int referenceIndex;

  /// 插入到该 ASR 行之前；等于文档行数时表示追加到末尾。
  ///
  /// 这是**应用前**文档中的位置（索引基准为 pre-application），
  /// 与 [asrLineIndex]（应用后的最终行索引）不同。
  final int insertBeforeAsrLineIndex;

  /// 插入后在文档中的最终行索引（索引基准为应用后的文档）。
  ///
  /// 名称保留历史含义；语义上等同 [appliedLineIndex]。
  final int asrLineIndex;

  final String text;
  final Duration startTime;
  final Duration endTime;
  final bool requiresConfirmation;

  /// 补入行的时间来源：参考时间戳 / 空隙插值 / 末尾估算。
  final LyricTimingProvenance timingProvenance;

  const AppliedReferenceInsertion({
    required this.referenceIndex,
    required this.insertBeforeAsrLineIndex,
    required this.asrLineIndex,
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.requiresConfirmation,
    this.timingProvenance = LyricTimingProvenance.interpolated,
  });

  /// [asrLineIndex] 的语义明确别名：补入行在应用后文档中的最终行索引。
  int get appliedLineIndex => asrLineIndex;
}

class ReferenceAlignmentApplyResult {
  final LyricDocument document;
  final List<AppliedReferenceCorrection> corrections;
  final List<AppliedReferenceInsertion> insertions;

  /// 应用前文档行索引 → 应用后文档行索引。
  ///
  /// 补行会把后续原有行整体后移，该映射让调用方按稳定含义把溯源信息
  /// （纠正行、受保护行）落到应用后的具体行上，而不是错位的行号。
  final Map<int, int> appliedIndexByOriginalIndex;

  final List<int> skippedManuallyEditedIndices;
  final List<int> skippedLowConfidenceIndices;

  /// 逐行确认时用户主动跳过、但相似度其实达到阈值的行。
  final List<int> skippedBySelectionIndices;

  final int timingUpdatedCount;
  final int identicalCount;
  final int missingReferenceCount;
  final int unmatchedAsrCount;

  /// 本次写入时间（含补行）的来源，键为应用后文档行索引。
  final Map<int, LyricTimingProvenance> timingProvenanceByAppliedIndex;

  /// 应用前后时间轴对比；没有改动时间时为 null。
  final LyricTimelineValidationComparison? timelineComparison;

  /// Conservative repairs applied before asking the user to resolve remaining conflicts.
  final List<LyricTimelineAutoRepair> timelineRepairs;

  const ReferenceAlignmentApplyResult({
    required this.document,
    required this.corrections,
    required this.insertions,
    this.appliedIndexByOriginalIndex = const {},
    required this.skippedManuallyEditedIndices,
    required this.skippedLowConfidenceIndices,
    required this.skippedBySelectionIndices,
    required this.timingUpdatedCount,
    required this.identicalCount,
    required this.missingReferenceCount,
    required this.unmatchedAsrCount,
    this.timingProvenanceByAppliedIndex = const {},
    this.timelineComparison,
    this.timelineRepairs = const [],
  });

  bool get hasChanges =>
      corrections.isNotEmpty ||
      insertions.isNotEmpty ||
      timingUpdatedCount > 0 ||
      timelineRepairs.isNotEmpty;

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
  /// 低于该相似度不自动采纳。默认与对齐服务的自动替换阈值一致。
  final double minimumSimilarity;

  /// 漏行插入计划的计算服务；测试或调用方可替换。
  final ReferenceTimelineCompletionService completionService;

  /// 时间轴校验器，用于区分应用前已有问题与本次引入的问题。
  final LyricTimelineValidator timelineValidator;
  final LyricTimelineAutoRepairService timelineRepairService;

  const ReferenceAlignmentApplier({
    this.minimumSimilarity = LyricAlignmentService.defaultAutoReplaceThreshold,
    this.completionService = const ReferenceTimelineCompletionService(),
    this.timelineValidator = const LyricTimelineValidator(),
    this.timelineRepairService = const LyricTimelineAutoRepairService(),
  }) : assert(minimumSimilarity >= 0 && minimumSimilarity <= 1);

  /// [audioDuration] 提供后会用于检查补行/时间替换是否越过音频末尾。
  ReferenceAlignmentApplyResult apply({
    required LyricDocument document,
    required LyricAlignmentResult alignment,
    bool applyReferenceTiming = false,
    Set<int>? acceptedReferenceIndices,
    Set<int>? acceptedMissingReferenceIndices,
    Set<int> protectedLineIndices = const {},
    Duration? audioDuration,
  }) {
    final lines = List<LyricLine>.from(document.lines);
    final corrections = <AppliedReferenceCorrection>[];
    final skippedManuallyEdited = <int>{};
    final skippedLowConfidence = <int>{};
    final skippedBySelection = <int>{};
    final timingByOriginalIndex = <int, LyricTimingProvenance>{};
    final timingChangedOriginalIndices = <int>{};
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
        final timing = _resolveTiming(
          alignment.entries,
          entryIndex,
          audioDuration: audioDuration,
        );
        if (timing != null &&
            (previousLine.startTime != timing.start ||
                previousLine.endTime != timing.end)) {
          updated = updated.copyWith(
            startTime: timing.start,
            endTime: timing.end,
          );
          timingChanged = true;
          timingUpdatedCount++;
          timingChangedOriginalIndices.add(asrIndex);
          timingByOriginalIndex[asrIndex] = LyricTimingProvenance.reference;
        }
      }

      if (!textChanged && !timingChanged) continue;

      lines[asrIndex] = updated;
      if (textChanged) {
        final provenance = timingChanged
            ? LyricTimingProvenance.reference
            : entry.referenceHasTimestamp && applyReferenceTiming
            ? LyricTimingProvenance.reference
            : (applyReferenceTiming ? LyricTimingProvenance.mappedAsr : null);
        if (provenance != null) {
          timingByOriginalIndex[asrIndex] = provenance;
        }
        corrections.add(
          AppliedReferenceCorrection(
            asrLineIndex: asrIndex,
            referenceIndex: entry.referenceIndex,
            previousText: previousLine.text,
            newText: entry.referenceText,
            similarity: entry.similarity,
            timingChanged: timingChanged,
            timingProvenance: provenance,
          ),
        );
      }
    }

    final sortedProtected = skippedManuallyEdited.toList()..sort();
    final sortedLowConfidence = skippedLowConfidence.toList()..sort();
    final sortedBySelection = skippedBySelection.toList()..sort();

    final insertions = <AppliedReferenceInsertion>[];
    final finalLines = <LyricLine>[];
    final appliedIndexByOriginalIndex = <int, int>{};
    final selectedMissing = acceptedMissingReferenceIndices;
    if (selectedMissing != null && selectedMissing.isNotEmpty) {
      final plan = completionService.buildPlan(
        document: document,
        alignment: alignment,
        audioDuration: audioDuration,
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

      // 歧义匹配条目若用户选择"作为漏行插入"，不会出现在补全计划中，
      // 需按其匹配到的 ASR 行位置合成插入项（insertBeforeAsrLineIndex =
      // 匹配行的索引，保持时间轴连续、不静默覆盖）。
      final unresolvedMissing = <int>[];
      for (final referenceIndex in selectedMissing) {
        if (!byPosition.values.any(
          (list) => list.any((i) => i.referenceIndex == referenceIndex),
        )) {
          unresolvedMissing.add(referenceIndex);
        }
      }
      for (final entry in alignment.entries) {
        if (!unresolvedMissing.contains(entry.referenceIndex)) continue;
        final asrIndex = entry.asrLineIndex;
        if (asrIndex == null || asrIndex < 0 || asrIndex >= lines.length) {
          continue;
        }
        final asrLine = lines[asrIndex];
        byPosition
            .putIfAbsent(asrIndex, () => [])
            .add(
              ReferenceLineCompletionInsertion(
                referenceIndex: entry.referenceIndex,
                text: entry.referenceText,
                insertBeforeAsrLineIndex: asrIndex,
                startTime: asrLine.startTime,
                endTime: asrLine.endTime,
                requiresConfirmation: true,
                previousAsrLineIndex: null,
                nextAsrLineIndex: null,
                timingProvenance:
                    ReferenceTimelineCompletionService.provenanceFor(entry),
              ),
            );
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
                timingProvenance: insertion.timingProvenance,
              ),
            );
            finalIndex++;
          }
        }
        if (index < lines.length) {
          appliedIndexByOriginalIndex[index] = finalIndex;
          finalLines.add(lines[index]);
          finalIndex++;
        }
      }
    } else {
      for (var index = 0; index < lines.length; index++) {
        appliedIndexByOriginalIndex[index] = index;
      }
      finalLines.addAll(lines);
    }

    final timingProvenance = <int, LyricTimingProvenance>{
      for (final item in timingByOriginalIndex.entries)
        appliedIndexByOriginalIndex[item.key] ?? item.key: item.value,
      for (final insertion in insertions)
        insertion.appliedLineIndex: insertion.timingProvenance,
    };

    final changedTimelineIndices = <int>{
      for (final insertion in insertions) insertion.appliedLineIndex,
      for (final index in timingChangedOriginalIndices)
        appliedIndexByOriginalIndex[index] ?? index,
    };
    final protectedTimelineIndices = <int>{};
    final originalTimingProvenance =
        document.metadata[kLyricTimingProvenanceKey];
    if (originalTimingProvenance is Map) {
      for (var index = 0; index < finalLines.length; index++) {
        final lineId = finalLines[index].id;
        if (lineId != null &&
            originalTimingProvenance[lineId] == LyricTimingProvenance.manual.name) {
          protectedTimelineIndices.add(index);
        }
      }
    }
    final autoRepair = timelineRepairService.repair(
      lines: finalLines,
      changedLineIndices: changedTimelineIndices,
      protectedLineIndices: protectedTimelineIndices,
      audioDuration: audioDuration,
    );
    final repairedLines = autoRepair.lines;
    for (final repair in autoRepair.repairs) {
      timingProvenance[repair.lineIndex] = LyricTimingProvenance.autoRepaired;
    }

    final comparison =
        timingUpdatedCount > 0 ||
            insertions.isNotEmpty ||
            autoRepair.repairs.isNotEmpty
        ? timelineValidator.compare(
            before: document.lines,
            after: repairedLines,
            audioDuration: audioDuration,
            globalOffset: applyReferenceTiming
                ? Duration.zero
                : document.globalOffset ?? Duration.zero,
          )
        : null;

    return ReferenceAlignmentApplyResult(
      document: document.copyWith(lines: repairedLines),
      corrections: corrections,
      insertions: insertions,
      appliedIndexByOriginalIndex: appliedIndexByOriginalIndex,
      skippedManuallyEditedIndices: sortedProtected,
      skippedLowConfidenceIndices: sortedLowConfidence,
      skippedBySelectionIndices: sortedBySelection,
      timingUpdatedCount: timingUpdatedCount,
      identicalCount: identicalCount,
      missingReferenceCount: alignment.missingReferenceIndices.length,
      unmatchedAsrCount: alignment.unmatchedAsrIndices.length,
      timingProvenanceByAppliedIndex: timingProvenance,
      timelineComparison: comparison,
      timelineRepairs: autoRepair.repairs,
    );
  }

  ({Duration start, Duration end})? _resolveTiming(
    List<LyricAlignmentEntry> entries,
    int entryIndex, {
    Duration? audioDuration,
  }) {
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
    // 结束时间越过音频末尾时收尾到音频结束；开始时间本身越界则保留，
    // 由时间轴校验器明确提示，不静默删除或挪动该行。
    if (audioDuration != null &&
        nonNegativeStart < audioDuration &&
        end > audioDuration) {
      end = audioDuration;
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
