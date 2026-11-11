import '../../../project/domain/models/lyric_document.dart';
import '../models/reference_lyric_input.dart';
import 'asr_reference_correction_suggester.dart';
import 'reference_proofread_change_set.dart';
import 'reference_proofread_review_builder.dart';

/// A review-only snapshot. The editor must still check its revision before
/// applying it; this object neither persists nor modifies the current editor.
class ReferenceProofreadPlan {
  final LyricDocument draft;
  final Set<int> protectedDraftIndices;
  final List<AsrReferenceCorrectionSuggestion> suggestions;
  final List<ReferenceProofreadReviewItem> timedItems;
  final bool hasTimingEvidence;

  ReferenceProofreadPlan._({
    required this.draft,
    required Set<int> protectedDraftIndices,
    required List<AsrReferenceCorrectionSuggestion> suggestions,
    required List<ReferenceProofreadReviewItem> timedItems,
    required this.hasTimingEvidence,
  }) : protectedDraftIndices = Set.unmodifiable(protectedDraftIndices),
       suggestions = List.unmodifiable(suggestions),
       timedItems = List.unmodifiable(timedItems);

  bool get isEmpty =>
      hasTimingEvidence ? timedItems.isEmpty : suggestions.isEmpty;

  /// Applies only explicitly selected, validated proposals to the snapshot.
  ReferenceProofreadAppliedChange apply(Set<int> selectedDraftIndices) {
    const changes = ReferenceProofreadChangeSet();
    if (hasTimingEvidence) {
      return changes.apply(
        draft: draft,
        proposals: timedItems,
        selectedDraftIndices: selectedDraftIndices,
        protectedDraftIndices: protectedDraftIndices,
      );
    }
    return changes.applyTextOnly(
      draft: draft,
      suggestions: suggestions,
      selectedDraftIndices: selectedDraftIndices,
      protectedDraftIndices: protectedDraftIndices,
    );
  }
}

/// Prepares reference correction with optional independent timing evidence.
class RunReferenceProofreadUseCase {
  const RunReferenceProofreadUseCase();

  ReferenceProofreadPlan build({
    required LyricDocument draft,
    required ReferenceLyricInput reference,
    LyricDocument? timingEvidence,
    Set<int> protectedDraftIndices = const {},
    Duration? audioDuration,
  }) {
    // Capture the same protection set for proposal generation and application.
    final protected = Set<int>.unmodifiable(protectedDraftIndices);
    if (timingEvidence != null) {
      return ReferenceProofreadPlan._(
        draft: draft,
        protectedDraftIndices: protected,
        suggestions: const [],
        timedItems: const ReferenceProofreadReviewBuilder().build(
          draft: draft,
          reference: reference,
          timingEvidence: timingEvidence,
          protectedDraftIndices: protected,
          audioDuration: audioDuration,
        ),
        hasTimingEvidence: true,
      );
    }
    return ReferenceProofreadPlan._(
      draft: draft,
      protectedDraftIndices: protected,
      suggestions: const AsrReferenceCorrectionSuggester()
          .suggest(
            draft: draft,
            reference: reference,
            protectedDraftIndices: protected,
          )
          .suggestions,
      timedItems: const [],
      hasTimingEvidence: false,
    );
  }
}
