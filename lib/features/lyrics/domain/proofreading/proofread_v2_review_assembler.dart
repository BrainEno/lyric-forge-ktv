import '../../../project/domain/models/lyric_document.dart';
import 'forced_alignment_proofread_service.dart';
import 'proofread_result.dart';
import 'proofread_review_proposal.dart';
import 'proofread_strategy_selector.dart';
import 'reference_first_pipeline.dart';

/// Everything the proofread review dialog needs from one pipeline run.
///
/// Building this is pure: it reads pipeline output and the draft and produces
/// review rows plus the wording that explains the strategy. The dialog, the
/// snackbars and the undo-able commit stay in the caller.
class ProofreadV2ReviewAssembly {
  final LyricDocument proposalDocument;
  final List<LyricProofreadV2ReviewItem> items;
  final List<LyricProofreadV2DroppedItem> droppedItems;
  final String explanation;
  final ProofreadAlignmentDiagnostics? alignmentDiagnostics;

  ProofreadV2ReviewAssembly({
    required this.proposalDocument,
    required List<LyricProofreadV2ReviewItem> items,
    required List<LyricProofreadV2DroppedItem> droppedItems,
    required this.explanation,
    this.alignmentDiagnostics,
  }) : items = List.unmodifiable(items),
       droppedItems = List.unmodifiable(droppedItems);
}

/// Turns pipeline output into dialog rows.
///
/// The two strategies disagree about where a proposal came from — reference
/// rows may reorder and drop draft lines, ASR rows stay one-to-one with the
/// draft — so they get separate entry points instead of a shared branch that
/// would have to guess which index space it is in.
class ProofreadV2ReviewAssembler {
  const ProofreadV2ReviewAssembler();

  ProofreadV2ReviewAssembly referenceFirst({
    required LyricDocument draft,
    required ReferenceFirstPipelineResult result,
    required LyricSourceStrategy requestedStrategy,
  }) {
    return ProofreadV2ReviewAssembly(
      proposalDocument: result.proposedDocument.copyWith(
        globalOffset: Duration.zero,
      ),
      items: [
        for (var index = 0; index < result.lines.length; index++)
          () {
            final row = result.lines[index];
            final sourceIndex = row.draftIndex;
            final original =
                sourceIndex != null &&
                    sourceIndex >= 0 &&
                    sourceIndex < draft.lines.length
                ? draft.lines[sourceIndex]
                : null;
            return LyricProofreadV2ReviewItem(
              proposalIndex: index,
              sourceIndex: sourceIndex,
              proposedLine: row.line,
              originalLine: original,
              verdict: switch (row.verdict) {
                ReferenceFirstVerdictLevel.locked =>
                  LyricProofreadReviewVerdict.locked,
                ReferenceFirstVerdictLevel.green =>
                  LyricProofreadReviewVerdict.green,
                ReferenceFirstVerdictLevel.amber =>
                  LyricProofreadReviewVerdict.amber,
              },
              referenceReasons: {
                for (final reason in row.reasons) referenceReasonCode(reason),
              },
            );
          }(),
      ],
      droppedItems: [
        for (final row in result.droppedLines)
          LyricProofreadV2DroppedItem(
            sourceIndex: row.draftIndex,
            line: row.line,
          ),
      ],
      explanation: [
        if (requestedStrategy == LyricSourceStrategy.auto)
          '自动策略计算参考文本覆盖率 ${(result.tokenCoverage * 100).round()}%。',
        '参考优先会以参考行组织提案；低置信、歧义、插值时间和结构差异保持琥珀色。',
        if (result.tokenDpBudgetExceeded) '词级对齐达到计算预算上限，覆盖率不能作为完整证据。',
        if (result.warnings.isNotEmpty)
          '参考输入包含 ${result.warnings.length} 条冲突或警告，相关行会要求复核。',
      ].join(' '),
    );
  }

  ProofreadV2ReviewAssembly asrFirst({
    required LyricDocument draft,
    required ProofreadResult result,
    required bool usedForcedAlignment,
    required bool hasSecondaryTranscript,
    bool autoFellBackToAsr = false,
    ForcedAlignmentProofreadOutcome? alignmentOutcome,
  }) {
    return ProofreadV2ReviewAssembly(
      proposalDocument: result.proposedDocument,
      alignmentDiagnostics: result.alignmentDiagnostics,
      items: [
        for (var index = 0; index < result.lines.length; index++)
          () {
            final row = result.lines[index];
            return LyricProofreadV2ReviewItem(
              proposalIndex: index,
              sourceIndex: index,
              proposedLine: row.line,
              originalLine: index < draft.lines.length
                  ? draft.lines[index]
                  : null,
              verdict: switch (row.verdict) {
                ProofreadVerdict.locked => LyricProofreadReviewVerdict.locked,
                ProofreadVerdict.green => LyricProofreadReviewVerdict.green,
                ProofreadVerdict.amber => LyricProofreadReviewVerdict.amber,
              },
              proofreadReasons: row.reasons,
              alignmentHints: {
                if (usedForcedAlignment)
                  row.tokens.isEmpty
                      ? LyricProofreadV2AlignmentHint.wordTimingMissing
                      : LyricProofreadV2AlignmentHint.wordTimingAvailable,
              },
              alignmentTokens: row.tokens,
            );
          }(),
      ],
      droppedItems: [
        for (final row in result.droppedLines)
          LyricProofreadV2DroppedItem(
            sourceIndex: row.sourceIndex,
            line: row.line,
          ),
      ],
      explanation: [
        autoFellBackToAsr
            ? '自动策略因参考文本覆盖率低于 25% 而退回 ASR 优先。'
            : !hasSecondaryTranscript
            ? '未提供第二份 ASR 转写稿，因此只标记当前草稿风险。'
            : '已将第二份带时间戳的转写稿作为独立证据；文本分歧仍需逐行复核。',
        'ASR 优先阶段不会猜测新时间或改写现有歌词；没有可证明的变更时，应用按钮会保持禁用。',
        if (alignmentOutcome != null &&
            alignmentOutcome.warning != null &&
            result.alignmentDiagnostics == null)
          alignmentOutcome.warning!,
        if (alignmentOutcome != null &&
            alignmentOutcome.alignmentAvailable &&
            result.lines.any((line) => line.tokens.isNotEmpty))
          'ForcedAligner 已提供词级时间证据；这些证据仅供复核，不会直接写入歌词时间戳。',
      ].join(' '),
    );
  }

  /// One-line verdict counts for the dialog header.
  String summary({
    required LyricSourceStrategy effectiveStrategy,
    required List<LyricProofreadV2ReviewItem> items,
    required List<LyricProofreadV2DroppedItem> droppedItems,
    double? referenceCoverage,
  }) {
    int count(LyricProofreadReviewVerdict verdict) =>
        items.where((item) => item.verdict == verdict).length;
    return [
      '策略：${strategyLabel(effectiveStrategy)}',
      if (referenceCoverage != null)
        '参考覆盖率 ${(referenceCoverage * 100).round()}%',
      '绿色 ${count(LyricProofreadReviewVerdict.green)}',
      '琥珀色 ${count(LyricProofreadReviewVerdict.amber)}',
      '受保护 ${count(LyricProofreadReviewVerdict.locked)}',
      '灰色 ${droppedItems.length}',
    ].join(' · ');
  }

  static String strategyLabel(LyricSourceStrategy strategy) {
    return switch (strategy) {
      LyricSourceStrategy.referenceFirst => '参考歌词优先',
      LyricSourceStrategy.asrFirst => 'ASR 优先',
      LyricSourceStrategy.auto => '自动选择',
    };
  }

  static LyricProofreadV2ReferenceReason referenceReasonCode(
    ReferenceFirstReason reason,
  ) {
    return switch (reason) {
      ReferenceFirstReason.lowConfidenceAlignment =>
        LyricProofreadV2ReferenceReason.lowConfidenceAlignment,
      ReferenceFirstReason.ambiguousAlignment =>
        LyricProofreadV2ReferenceReason.ambiguousAlignment,
      ReferenceFirstReason.structuralMismatch =>
        LyricProofreadV2ReferenceReason.structuralMismatch,
      ReferenceFirstReason.referenceTimestamp =>
        LyricProofreadV2ReferenceReason.referenceTimestamp,
      ReferenceFirstReason.mappedAsrTiming =>
        LyricProofreadV2ReferenceReason.mappedAsrTiming,
      ReferenceFirstReason.interpolatedTiming =>
        LyricProofreadV2ReferenceReason.interpolatedTiming,
      ReferenceFirstReason.estimatedTailTiming =>
        LyricProofreadV2ReferenceReason.estimatedTailTiming,
      ReferenceFirstReason.timelineAdjusted =>
        LyricProofreadV2ReferenceReason.timelineAdjusted,
      ReferenceFirstReason.protectedLine =>
        LyricProofreadV2ReferenceReason.protectedLine,
      ReferenceFirstReason.referenceImportWarning =>
        LyricProofreadV2ReferenceReason.referenceImportWarning,
    };
  }
}
