import '../../../project/domain/models/lyric_document.dart';
import 'forced_alignment_proofread_service.dart';
import 'proofread_result.dart';
import 'proofread_review_proposal.dart';
import 'proofread_strategy_selector.dart';
import 'reference_first_pipeline.dart';

/// Everything the proofread review dialog needs from one pipeline run.
///
/// Building this is pure: it reads pipeline output and the draft and produces
/// review rows plus typed explanation data. Presentation owns the wording;
/// the dialog, snackbars and undo-able commit stay in the caller.
class ProofreadV2ReviewAssembly {
  final LyricDocument proposalDocument;
  final List<LyricProofreadV2ReviewItem> items;
  final List<LyricProofreadV2DroppedItem> droppedItems;
  final List<LyricProofreadV2Explanation> explanations;
  final ProofreadAlignmentDiagnostics? alignmentDiagnostics;

  ProofreadV2ReviewAssembly({
    required this.proposalDocument,
    required List<LyricProofreadV2ReviewItem> items,
    required List<LyricProofreadV2DroppedItem> droppedItems,
    required List<LyricProofreadV2Explanation> explanations,
    this.alignmentDiagnostics,
  }) : items = List.unmodifiable(items),
       droppedItems = List.unmodifiable(droppedItems),
       explanations = List.unmodifiable(explanations);
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
    bool requestedForcedAlignment = false,
    bool hasSecondaryTranscript = false,
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
      explanations: [
        if (requestedStrategy == LyricSourceStrategy.auto)
          LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode.automaticReferenceCoverage,
            referenceCoveragePercent: (result.tokenCoverage * 100).round(),
          ),
        const LyricProofreadV2Explanation(
          LyricProofreadV2ExplanationCode.referenceFirstGuidance,
        ),
        if (requestedForcedAlignment)
          const LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode.forcedAlignmentIgnoredByReference,
          ),
        if (hasSecondaryTranscript)
          const LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode
                .secondaryTranscriptIgnoredByReference,
          ),
        if (result.tokenDpBudgetExceeded)
          const LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode.referenceAlignmentBudgetExceeded,
          ),
        if (result.warnings.isNotEmpty)
          LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode.referenceInputWarnings,
            referenceWarningCount: result.warnings.length,
          ),
      ],
    );
  }

  ProofreadV2ReviewAssembly asrFirst({
    required LyricDocument draft,
    required ProofreadResult result,
    required bool usedForcedAlignment,
    required bool hasSecondaryTranscript,
    bool autoFellBackToAsr = false,
    bool hasReference = false,
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
      explanations: [
        if (autoFellBackToAsr)
          const LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode.automaticFallbackToAsr,
          ),
        if (hasReference)
          const LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode.referenceIgnoredByAsr,
          ),
        LyricProofreadV2Explanation(
          hasSecondaryTranscript
              ? LyricProofreadV2ExplanationCode.secondaryTranscriptEvidence
              : LyricProofreadV2ExplanationCode.missingSecondaryTranscript,
        ),
        const LyricProofreadV2Explanation(
          LyricProofreadV2ExplanationCode.asrFirstConservativeTiming,
        ),
        if (alignmentOutcome != null && result.alignmentDiagnostics == null)
          LyricProofreadV2Explanation(
            alignmentOutcome.alignmentAvailable
                ? LyricProofreadV2ExplanationCode
                      .forcedAlignmentDiagnosticsMissing
                : LyricProofreadV2ExplanationCode.forcedAlignmentUnavailable,
          ),
        if (alignmentOutcome != null &&
            alignmentOutcome.alignmentAvailable &&
            result.lines.any((line) => line.tokens.isNotEmpty))
          const LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode.forcedAlignmentEvidenceAvailable,
          ),
      ],
    );
  }

  /// Structured strategy and verdict counts for the dialog header.
  LyricProofreadV2ReviewSummary summary({
    required LyricSourceStrategy effectiveStrategy,
    required List<LyricProofreadV2ReviewItem> items,
    required List<LyricProofreadV2DroppedItem> droppedItems,
    double? referenceCoverage,
  }) {
    int count(LyricProofreadReviewVerdict verdict) =>
        items.where((item) => item.verdict == verdict).length;
    return LyricProofreadV2ReviewSummary(
      effectiveStrategy: effectiveStrategy,
      greenCount: count(LyricProofreadReviewVerdict.green),
      amberCount: count(LyricProofreadReviewVerdict.amber),
      lockedCount: count(LyricProofreadReviewVerdict.locked),
      droppedCount: droppedItems.length,
      referenceCoverage: referenceCoverage,
    );
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
