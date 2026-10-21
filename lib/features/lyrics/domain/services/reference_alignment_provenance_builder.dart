import '../../../project/domain/models/lyric_document.dart';
import '../models/reference_lyric_input.dart';
import '../models/timing_provenance.dart';
import 'reference_alignment_applier.dart';

/// 把一次参考对齐应用结果整理成可追溯的 `metadata['referenceAlignment']`。
///
/// 溯源语义固定如下：
/// - `indexBase` 恒为 `pre-application`：`corrections[].asrLineIndex` 与
///   `insertions[].insertBeforeAsrLineIndex` 都指向**应用前**文档的行号；
/// - `insertions[].appliedLineIndex` 是补入行在**应用后**文档中的最终行号；
/// - 每个纠正、补入与跳过的保护行都附带 `lineId`（稳定行标识），
///   后续插入/删除/重排后仍能定位到具体行，不依赖会漂移的行号。
class ReferenceAlignmentProvenanceBuilder {
  const ReferenceAlignmentProvenanceBuilder();

  /// 溯源信息在文档 metadata 中的键。
  static const String metadataKey = 'referenceAlignment';

  /// 行号语义：应用前文档。
  static const String indexBasePreApplication = 'pre-application';

  /// 应用后文档中 [index] 行的稳定标识；越界或未分配时返回 null。
  static String? lineIdAt(LyricDocument document, int index) {
    if (index < 0 || index >= document.lines.length) return null;
    return document.lines[index].id;
  }

  Map<String, dynamic> build({
    required DateTime appliedAt,
    required ReferenceLyricInput input,
    required double minimumSimilarity,
    required bool applyReferenceTiming,
    required int acceptedReferenceCount,
    required int acceptedMissingReferenceCount,
    required int overriddenManuallyEditedCount,
    required ReferenceAlignmentApplyResult result,
    required LyricDocument appliedDocument,
  }) {
    return <String, dynamic>{
      'source': 'reference-alignment',
      'appliedAt': appliedAt.toIso8601String(),
      'indexBase': indexBasePreApplication,
      if (input.sourcePath != null) 'sourcePath': input.sourcePath,
      'format': input.format,
      if (input.title != null) 'referenceTitle': input.title,
      if (input.artist != null) 'referenceArtist': input.artist,
      'referenceTimed': input.timed,
      'referenceOffsetMs': input.offset.inMilliseconds,
      'referenceConflictCount': input.conflicts.length,
      'referenceWarningCount': input.warnings.length,
      'minimumSimilarity': minimumSimilarity,
      'applyReferenceTiming': applyReferenceTiming,
      'acceptedReferenceCount': acceptedReferenceCount,
      'acceptedMissingReferenceCount': acceptedMissingReferenceCount,
      'overriddenManuallyEditedCount': overriddenManuallyEditedCount,
      'appliedCorrectionCount': result.corrections.length,
      'insertedReferenceCount': result.insertions.length,
      'skippedMissingReferenceCount':
          result.missingReferenceCount - result.insertions.length,
      'timingUpdatedCount': result.timingUpdatedCount,
      'skippedManuallyEditedCount': result.skippedManuallyEditedIndices.length,
      'skippedLowConfidenceCount': result.skippedLowConfidenceIndices.length,
      'skippedBySelectionCount': result.skippedBySelectionIndices.length,
      'missingReferenceCount': result.missingReferenceCount,
      'unmatchedAsrCount': result.unmatchedAsrCount,
      'corrections': [
        for (final correction in result.corrections)
          <String, dynamic>{
            'asrLineIndex': correction.asrLineIndex,
            ..._lineRef(
              appliedDocument,
              result.appliedIndexByOriginalIndex[correction.asrLineIndex] ??
                  correction.asrLineIndex,
            ),
            'referenceIndex': correction.referenceIndex,
            'similarity': correction.similarity,
          },
      ],
      'insertions': [
        for (final insertion in result.insertions)
          <String, dynamic>{
            'insertBeforeAsrLineIndex': insertion.insertBeforeAsrLineIndex,
            'appliedLineIndex': insertion.appliedLineIndex,
            ..._lineRef(appliedDocument, insertion.appliedLineIndex),
            'referenceIndex': insertion.referenceIndex,
            'startTime': insertion.startTime.inMilliseconds,
            'endTime': insertion.endTime.inMilliseconds,
            'requiresConfirmation': insertion.requiresConfirmation,
          },
      ],
      'skippedManuallyEditedLineIds': _lineIds(
        appliedDocument,
        result.skippedManuallyEditedIndices.map(
          (index) => result.appliedIndexByOriginalIndex[index] ?? index,
        ),
      ),
      kLyricTimingProvenanceKey: _timingProvenance(appliedDocument, result),
    };
  }

  /// 以稳定行标识为键合并时间来源。
  ///
  /// 已有 `manual` 记录不会被本次自动写入覆盖；其余本次涉及的行走新来源。
  Map<String, String> _timingProvenance(
    LyricDocument appliedDocument,
    ReferenceAlignmentApplyResult result,
  ) {
    final merged = <String, String>{};
    final existing = appliedDocument.metadata[kLyricTimingProvenanceKey];
    if (existing is Map) {
      for (final item in existing.entries) {
        if (item.key is String && item.value is String) {
          merged[item.key as String] = item.value as String;
        }
      }
    }
    for (final item in result.timingProvenanceByAppliedIndex.entries) {
      final lineId = lineIdAt(appliedDocument, item.key);
      if (lineId == null) continue;
      if (merged[lineId] == LyricTimingProvenance.manual.name) continue;
      merged[lineId] = item.value.name;
    }
    return merged;
  }

  Map<String, dynamic> _lineRef(LyricDocument document, int index) {
    final lineId = lineIdAt(document, index);
    return lineId == null ? const {} : {'lineId': lineId};
  }

  List<String> _lineIds(LyricDocument document, Iterable<int> indices) => [
    for (final index in indices)
      if (lineIdAt(document, index) != null) lineIdAt(document, index)!,
  ];
}
