import '../../../project/domain/models/lyric_document.dart';
import 'proofread_result.dart';

/// How a single review row should be treated when the user confirms.
///
/// `locked` rows are applied without an explicit tick because the pipeline
/// decided the row must not be silently rewritten; `green`/`amber` rows only
/// apply when the dialog reports them as accepted.
enum LyricProofreadReviewVerdict { locked, green, amber }

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
  final String reasonLabel;
  final List<TimedLyricToken> alignmentTokens;

  const LyricProofreadV2ReviewItem({
    required this.proposalIndex,
    required this.sourceIndex,
    required this.proposedLine,
    required this.originalLine,
    required this.verdict,
    required this.reasonLabel,
    this.alignmentTokens = const [],
  });

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
  final String reasonLabel;

  const LyricProofreadV2DroppedItem({
    required this.sourceIndex,
    required this.line,
    required this.reasonLabel,
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
