import '../../../project/domain/models/lyric_document.dart';
import 'forced_alignment_proofread_service.dart';
import 'proofread_result.dart';
import 'proofread_review_proposal.dart';
import 'proofread_strategy_selector.dart';
import 'reference_first_pipeline.dart';
import 'reference_forced_alignment_planner.dart';

/// Everything the proofread review dialog needs from one pipeline run.
///
/// Building this is pure: it reads pipeline output and the draft and produces
/// review rows plus typed explanation data. Presentation owns the wording;
/// the dialog, snackbars and undo-able commit stay in the caller.
class ProofreadReviewAssembly {
  final LyricDocument proposalDocument;
  final List<LyricProofreadReviewItem> items;
  final List<LyricProofreadDroppedItem> droppedItems;
  final List<LyricProofreadExplanation> explanations;
  final ProofreadAlignmentDiagnostics? alignmentDiagnostics;
  final ReferenceForcedAlignmentPlan? referenceAlignmentPlan;

  ProofreadReviewAssembly({
    required this.proposalDocument,
    required List<LyricProofreadReviewItem> items,
    required List<LyricProofreadDroppedItem> droppedItems,
    required List<LyricProofreadExplanation> explanations,
    this.alignmentDiagnostics,
    this.referenceAlignmentPlan,
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
class ProofreadReviewAssembler {
  const ProofreadReviewAssembler();

  ProofreadReviewAssembly referenceFirst({
    required LyricDocument draft,
    required ReferenceFirstPipelineResult result,
    required LyricSourceStrategy requestedStrategy,
    bool requestedForcedAlignment = false,
    bool hasSecondaryTranscript = false,
    ReferenceForcedAlignmentPlan? referenceAlignmentPlan,
  }) {
    final referenceTimes = {
      for (final proposal
          in referenceAlignmentPlan?.proposals ??
              const <ReferenceForcedTimingProposal>[])
        proposal.referenceIndex: proposal,
    };
    return ProofreadReviewAssembly(
      referenceAlignmentPlan: referenceAlignmentPlan,
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
            return LyricProofreadReviewItem(
              proposalIndex: index,
              sourceIndex: sourceIndex,
              proposedLine: row.line,
              originalLine: original,
              referenceTimingEvidence: referenceTimes[row.referenceIndex],
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
          LyricProofreadDroppedItem(
            sourceIndex: row.draftIndex,
            line: row.line,
          ),
      ],
      explanations: [
        if (requestedStrategy == LyricSourceStrategy.auto)
          LyricProofreadExplanation(
            LyricProofreadExplanationCode.automaticReferenceCoverage,
            referenceCoveragePercent: (result.tokenCoverage * 100).round(),
          ),
        const LyricProofreadExplanation(
          LyricProofreadExplanationCode.referenceFirstGuidance,
        ),
        if (requestedForcedAlignment && referenceAlignmentPlan == null)
          const LyricProofreadExplanation(
            LyricProofreadExplanationCode.forcedAlignmentIgnoredByReference,
          ),
        if (hasSecondaryTranscript)
          const LyricProofreadExplanation(
            LyricProofreadExplanationCode.secondaryTranscriptIgnoredByReference,
          ),
        if (result.tokenDpBudgetExceeded)
          const LyricProofreadExplanation(
            LyricProofreadExplanationCode.referenceAlignmentBudgetExceeded,
          ),
        if (result.warnings.isNotEmpty)
          LyricProofreadExplanation(
            LyricProofreadExplanationCode.referenceInputWarnings,
            referenceWarningCount: result.warnings.length,
          ),
      ],
    );
  }

  ProofreadReviewAssembly asrFirst({
    required LyricDocument draft,
    required ProofreadResult result,
    required bool usedForcedAlignment,
    required bool hasSecondaryTranscript,
    bool autoFellBackToAsr = false,
    bool hasReference = false,
    ForcedAlignmentProofreadOutcome? alignmentOutcome,
  }) {
    return ProofreadReviewAssembly(
      proposalDocument: result.proposedDocument,
      alignmentDiagnostics: result.alignmentDiagnostics,
      items: [
        for (var index = 0; index < result.lines.length; index++)
          () {
            final row = result.lines[index];
            return LyricProofreadReviewItem(
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
                      ? LyricProofreadAlignmentHint.wordTimingMissing
                      : LyricProofreadAlignmentHint.wordTimingAvailable,
              },
              alignmentTokens: row.tokens,
            );
          }(),
      ],
      droppedItems: [
        for (final row in result.droppedLines)
          LyricProofreadDroppedItem(
            sourceIndex: row.sourceIndex,
            line: row.line,
          ),
      ],
      explanations: [
        if (autoFellBackToAsr)
          const LyricProofreadExplanation(
            LyricProofreadExplanationCode.automaticFallbackToAsr,
          ),
        if (hasReference)
          const LyricProofreadExplanation(
            LyricProofreadExplanationCode.referenceIgnoredByAsr,
          ),
        LyricProofreadExplanation(
          hasSecondaryTranscript
              ? LyricProofreadExplanationCode.secondaryTranscriptEvidence
              : LyricProofreadExplanationCode.missingSecondaryTranscript,
        ),
        const LyricProofreadExplanation(
          LyricProofreadExplanationCode.asrFirstConservativeTiming,
        ),
        if (alignmentOutcome != null && result.alignmentDiagnostics == null)
          LyricProofreadExplanation(
            alignmentOutcome.alignmentAvailable
                ? LyricProofreadExplanationCode
                      .forcedAlignmentDiagnosticsMissing
                : LyricProofreadExplanationCode.forcedAlignmentUnavailable,
          ),
        if (alignmentOutcome != null &&
            alignmentOutcome.alignmentAvailable &&
            result.lines.any((line) => line.tokens.isNotEmpty))
          const LyricProofreadExplanation(
            LyricProofreadExplanationCode.forcedAlignmentEvidenceAvailable,
          ),
      ],
    );
  }

  /// Structured strategy and verdict counts for the dialog header.
  LyricProofreadReviewSummary summary({
    required LyricSourceStrategy effectiveStrategy,
    required List<LyricProofreadReviewItem> items,
    required List<LyricProofreadDroppedItem> droppedItems,
    double? referenceCoverage,
  }) {
    int count(LyricProofreadReviewVerdict verdict) =>
        items.where((item) => item.verdict == verdict).length;
    return LyricProofreadReviewSummary(
      effectiveStrategy: effectiveStrategy,
      greenCount: count(LyricProofreadReviewVerdict.green),
      amberCount: count(LyricProofreadReviewVerdict.amber),
      lockedCount: count(LyricProofreadReviewVerdict.locked),
      droppedCount: droppedItems.length,
      referenceCoverage: referenceCoverage,
    );
  }

  static LyricProofreadReferenceReason referenceReasonCode(
    ReferenceFirstReason reason,
  ) {
    return switch (reason) {
      ReferenceFirstReason.lowConfidenceAlignment =>
        LyricProofreadReferenceReason.lowConfidenceAlignment,
      ReferenceFirstReason.ambiguousAlignment =>
        LyricProofreadReferenceReason.ambiguousAlignment,
      ReferenceFirstReason.structuralMismatch =>
        LyricProofreadReferenceReason.structuralMismatch,
      ReferenceFirstReason.referenceTimestamp =>
        LyricProofreadReferenceReason.referenceTimestamp,
      ReferenceFirstReason.mappedAsrTiming =>
        LyricProofreadReferenceReason.mappedAsrTiming,
      ReferenceFirstReason.interpolatedTiming =>
        LyricProofreadReferenceReason.interpolatedTiming,
      ReferenceFirstReason.estimatedTailTiming =>
        LyricProofreadReferenceReason.estimatedTailTiming,
      ReferenceFirstReason.timelineAdjusted =>
        LyricProofreadReferenceReason.timelineAdjusted,
      ReferenceFirstReason.protectedLine =>
        LyricProofreadReferenceReason.protectedLine,
      ReferenceFirstReason.referenceImportWarning =>
        LyricProofreadReferenceReason.referenceImportWarning,
    };
  }
}
