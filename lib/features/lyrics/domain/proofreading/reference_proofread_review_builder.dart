import '../../../project/domain/models/lyric_document.dart';
import '../models/reference_lyric_input.dart';
import 'asr_reference_correction_suggester.dart';
import 'asr_retiming_planner.dart';

/// One reference correction paired with an independent, evidence-backed
/// timing plan. This object is a proposal only; it never edits the draft.
class ReferenceProofreadReviewItem {
  final AsrReferenceCorrectionSuggestion correction;
  final AsrRetimingPlan retiming;

  const ReferenceProofreadReviewItem({
    required this.correction,
    required this.retiming,
  });

  bool get requiresManualReview =>
      correction.requiresManualReview || !retiming.canOfferForReview;

  /// Suitable to show as a complete text-and-timing proposal in the UI.
  /// Applying it still requires an explicit user action and undoable commit.
  bool get canOfferCompleteProposal =>
      !correction.requiresManualReview && retiming.canOfferForReview;
}

/// Bundles existing reference correction suggestions with safe retiming plans.
///
/// A text correction is never considered complete merely because reference
/// lyrics provide timestamps: only exact nearby timing evidence from the
/// supplied ASR transcript can make a retiming plan ready for review.
class ReferenceProofreadReviewBuilder {
  final AsrReferenceCorrectionSuggester correctionSuggester;
  final AsrRetimingPlanner retimingPlanner;

  const ReferenceProofreadReviewBuilder({
    this.correctionSuggester = const AsrReferenceCorrectionSuggester(),
    this.retimingPlanner = const AsrRetimingPlanner(),
  });

  List<ReferenceProofreadReviewItem> build({
    required LyricDocument draft,
    required ReferenceLyricInput reference,
    required LyricDocument timingEvidence,
    Set<int> protectedDraftIndices = const {},
    Duration? audioDuration,
    double suggestionThreshold = 0.82,
  }) {
    final correctionResult = correctionSuggester.suggest(
      draft: draft,
      reference: reference,
      protectedDraftIndices: protectedDraftIndices,
      suggestionThreshold: suggestionThreshold,
    );

    return List.unmodifiable([
      for (final correction in correctionResult.suggestions)
        ReferenceProofreadReviewItem(
          correction: correction,
          retiming: retimingPlanner.plan(
            draft: draft,
            draftIndex: correction.draftIndex,
            proposedText: correction.suggestedText,
            timingEvidence: timingEvidence,
            protectedDraftIndices: protectedDraftIndices,
            audioDuration: audioDuration,
          ),
        ),
    ]);
  }
}
