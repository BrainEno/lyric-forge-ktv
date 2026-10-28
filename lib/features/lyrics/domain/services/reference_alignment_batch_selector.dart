import 'lyric_alignment_service.dart';
import 'reference_timeline_completion_service.dart';

/// 一批可安全采纳 / 需要用户显式确认的参考行。
class ReferenceAlignmentBatchSelection {
  /// 可直接批量采纳的正行：高置信、无歧义、无结构差异、非手动编辑。
  final Set<int> safeReferenceIndices;

  /// 低置信、歧义或结构差异行：只能逐行显式确认。
  final Set<int> uncertainReferenceIndices;

  /// 可直接补入的漏行（插入计划不要求确认）。
  final Set<int> safeMissingReferenceIndices;

  /// 需要确认的漏行（空隙不足、夹着未匹配行或结构差异）。
  final Set<int> uncertainMissingReferenceIndices;

  const ReferenceAlignmentBatchSelection({
    required this.safeReferenceIndices,
    required this.uncertainReferenceIndices,
    required this.safeMissingReferenceIndices,
    required this.uncertainMissingReferenceIndices,
  });

  static const empty = ReferenceAlignmentBatchSelection(
    safeReferenceIndices: {},
    uncertainReferenceIndices: {},
    safeMissingReferenceIndices: {},
    uncertainMissingReferenceIndices: {},
  );
}

/// 把对齐结果拆成"安全批量"和"必须显式确认"两组。
///
/// 安全批量**只**包含 [ReferenceLineAlignmentStatus.replace]：相似度达标不代表
/// 没有歧义；[ReferenceLineAlignmentStatus.ambiguous]、低置信度和结构差异
/// 一律进入需确认组，避免一次批量操作覆盖正确行。
class ReferenceAlignmentBatchSelector {
  const ReferenceAlignmentBatchSelector();

  ReferenceAlignmentBatchSelection select({
    required LyricAlignmentResult alignment,
    required ReferenceLineCompletionPlan completionPlan,
    required double minimumSimilarity,
    Set<int> protectedLineIndices = const {},
  }) {
    final safe = <int>{};
    final uncertain = <int>{};

    for (final entry in alignment.entries) {
      final asrIndex = entry.asrLineIndex;
      if (asrIndex == null) continue;
      if (entry.status == ReferenceLineAlignmentStatus.identical) continue;
      if (entry.status == ReferenceLineAlignmentStatus.missing) continue;

      final isSafe =
          entry.status == ReferenceLineAlignmentStatus.replace &&
          !entry.ambiguous &&
          !entry.structuralMismatch &&
          entry.similarity >= minimumSimilarity &&
          !protectedLineIndices.contains(asrIndex);
      if (isSafe) {
        safe.add(entry.referenceIndex);
      } else {
        uncertain.add(entry.referenceIndex);
      }
    }

    final safeMissing = <int>{};
    final uncertainMissing = <int>{};
    for (final insertion in completionPlan.insertions) {
      if (insertion.requiresConfirmation) {
        uncertainMissing.add(insertion.referenceIndex);
      } else {
        safeMissing.add(insertion.referenceIndex);
      }
    }

    return ReferenceAlignmentBatchSelection(
      safeReferenceIndices: safe,
      uncertainReferenceIndices: uncertain,
      safeMissingReferenceIndices: safeMissing,
      uncertainMissingReferenceIndices: uncertainMissing,
    );
  }
}
