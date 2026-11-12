import '../../../project/domain/models/lyric_document.dart';
import 'proofread_result.dart';
import 'proofread_strategy_selector.dart';
import 'reference_forced_alignment_planner.dart';

/// How a single review row should be treated when the user confirms.
///
/// `locked` rows are applied without an explicit tick because the pipeline
/// decided the row must not be silently rewritten; `green`/`amber` rows only
/// apply when the dialog reports them as accepted.
enum LyricProofreadReviewVerdict { locked, green, amber }

/// Stable, locale-neutral reason codes for reference-first review rows.
enum LyricProofreadV2ReferenceReason {
  lowConfidenceAlignment,
  ambiguousAlignment,
  structuralMismatch,
  referenceTimestamp,
  mappedAsrTiming,
  interpolatedTiming,
  estimatedTailTiming,
  timelineAdjusted,
  protectedLine,
  referenceImportWarning,
}

enum LyricProofreadV2AlignmentHint { wordTimingAvailable, wordTimingMissing }

enum LyricProofreadV2ExplanationCode {
  automaticReferenceCoverage,
  referenceFirstGuidance,
  referenceAlignmentBudgetExceeded,
  referenceInputWarnings,
  forcedAlignmentIgnoredByReference,
  secondaryTranscriptIgnoredByReference,
  referenceIgnoredByAsr,
  automaticFallbackToAsr,
  missingSecondaryTranscript,
  secondaryTranscriptEvidence,
  asrFirstConservativeTiming,
  forcedAlignmentEvidenceAvailable,
  forcedAlignmentUnavailable,
  forcedAlignmentDiagnosticsMissing,
}

/// A structured Proofread V2 explanation for presentation to render.
class LyricProofreadV2Explanation {
  final LyricProofreadV2ExplanationCode code;
  final int? referenceCoveragePercent;
  final int? referenceWarningCount;

  const LyricProofreadV2Explanation(
    this.code, {
    this.referenceCoveragePercent,
    this.referenceWarningCount,
  }) : assert(
         code != LyricProofreadV2ExplanationCode.automaticReferenceCoverage ||
             referenceCoveragePercent != null,
       ),
       assert(
         code != LyricProofreadV2ExplanationCode.referenceInputWarnings ||
             referenceWarningCount != null,
       );
}

/// Counts and strategy data for the Proofread V2 dialog header.
class LyricProofreadV2ReviewSummary {
  final LyricSourceStrategy effectiveStrategy;
  final int greenCount;
  final int amberCount;
  final int lockedCount;
  final int droppedCount;
  final double? referenceCoverage;

  const LyricProofreadV2ReviewSummary({
    required this.effectiveStrategy,
    required this.greenCount,
    required this.amberCount,
    required this.lockedCount,
    required this.droppedCount,
    required this.referenceCoverage,
  });
}

/// One row of the proofread review dialog: a proposal paired with the draft
/// line it would replace.
///
/// This is a proposal only. Nothing here changes a document until the caller
/// hands a selection back to `ProofreadV2DocumentComposer`.
class LyricProofreadV2ReviewItem {
  final int proposalIndex;
  final int? sourceIndex;
  final LyricLine proposedLine;
  final LyricLine? originalLine;
  final LyricProofreadReviewVerdict verdict;
  final Set<LyricProofreadV2ReferenceReason> referenceReasons;
  final Set<ProofreadReason> proofreadReasons;
  final Set<LyricProofreadV2AlignmentHint> alignmentHints;
  final List<TimedLyricToken> alignmentTokens;

  /// Separate, absolute-time reference evidence; never part of proposedLine.
  final ReferenceForcedTimingProposal? referenceTimingEvidence;

  LyricProofreadV2ReviewItem({
    required this.proposalIndex,
    required this.sourceIndex,
    required this.proposedLine,
    required this.originalLine,
    required this.verdict,
    Set<LyricProofreadV2ReferenceReason> referenceReasons = const {},
    Set<ProofreadReason> proofreadReasons = const {},
    Set<LyricProofreadV2AlignmentHint> alignmentHints = const {},
    this.alignmentTokens = const [],
    this.referenceTimingEvidence,
  }) : referenceReasons = Set.unmodifiable(referenceReasons),
       proofreadReasons = Set.unmodifiable(proofreadReasons),
       alignmentHints = Set.unmodifiable(alignmentHints);

  bool get hasChange {
    final original = originalLine;
    if (original == null) return true;
    return original.text != proposedLine.text ||
        original.startTime != proposedLine.startTime ||
        original.endTime != proposedLine.endTime ||
        original.isChorus != proposedLine.isChorus ||
        original.confidence != proposedLine.confidence;
  }
}

/// A draft line the pipeline wanted to remove, kept visible in the dialog so
/// the user can restore it explicitly.
class LyricProofreadV2DroppedItem {
  final int sourceIndex;
  final LyricLine line;

  const LyricProofreadV2DroppedItem({
    required this.sourceIndex,
    required this.line,
  });
}

/// What the user confirmed in the review dialog.
class LyricProofreadV2Selection {
  final Set<int> acceptedProposalIndices;
  final Set<int> restoredDraftIndices;

  LyricProofreadV2Selection({
    required Set<int> acceptedProposalIndices,
    required Set<int> restoredDraftIndices,
  }) : acceptedProposalIndices = Set.unmodifiable(acceptedProposalIndices),
       restoredDraftIndices = Set.unmodifiable(restoredDraftIndices);
}
