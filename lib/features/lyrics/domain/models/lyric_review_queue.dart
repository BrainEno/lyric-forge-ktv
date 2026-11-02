import '../../../project/domain/models/lyric_document.dart';
import '../services/lyric_review_decision_service.dart';
import '../services/lyric_review_priority_service.dart';

/// One combined view of the lines that still need a human decision.
///
/// The editor used to compute three nearly identical numbers and show them side
/// by side: a "low confidence" count straight from the line scores, a "needs
/// review" count from an ad-hoc predicate in the screen, and a "smart review"
/// count from [LyricReviewPriorityService]. Each had its own filter, so the
/// toolbar could say `待复核 42 / 低置信度 42 / 智能复核 42` for a document
/// transcribed by an engine that never reports probabilities. Three numbers
/// that always agree teach the user that the numbers mean nothing.
///
/// This queue is the single source of truth:
///
/// * [items] is the review queue — unreviewed lines ranked by evidence, and the
///   list every counter and every filter is derived from;
/// * [lowConfidenceCount] is a **subset** of [items], so it can never exceed
///   [needsReviewCount];
/// * [unscoredLines] records lines the engine never scored, so the UI can say
///   "we do not know" instead of inventing a red badge.
class LyricReviewQueue {
  /// Ranked, unreviewed lines. Order is what the "needs review" filter shows.
  final List<LyricReviewPriority> items;

  /// Indices of [items] whose engine score is a real, low score.
  final Set<int> lowConfidenceIndices;

  /// Every line in the document, reviewed or not.
  final int totalLines;

  /// Lines whose engine returned a probability (including rule-adjusted ones).
  final int scoredLines;

  /// Lines a human has explicitly confirmed.
  final int reviewedLines;

  /// Score below which a line with a real score counts as low confidence.
  final int confidenceThreshold;

  const LyricReviewQueue({
    required this.items,
    required this.lowConfidenceIndices,
    required this.totalLines,
    required this.scoredLines,
    required this.reviewedLines,
    required this.confidenceThreshold,
  });

  static const LyricReviewQueue empty = LyricReviewQueue(
    items: <LyricReviewPriority>[],
    lowConfidenceIndices: <int>{},
    totalLines: 0,
    scoredLines: 0,
    reviewedLines: 0,
    confidenceThreshold: 70,
  );

  /// Builds the queue and every derived count in one pass, so no two surfaces
  /// can disagree about what "needs review" means.
  factory LyricReviewQueue.build(
    LyricDocument document, {
    Duration? audioDuration,
    int confidenceThreshold = 70,
    LyricReviewPriorityService priorityService =
        const LyricReviewPriorityService(),
    LyricReviewDecisionService decisionService =
        const LyricReviewDecisionService(),
  }) {
    if (document.lines.isEmpty) {
      return LyricReviewQueue.empty;
    }
    final ranked = priorityService.rank(
      document,
      audioDuration: audioDuration,
    );
    final lowConfidence = <int>{};
    for (final priority in ranked) {
      final index = priority.lineIndex;
      if (index < 0 || index >= document.lines.length) continue;
      if (document.lines[index].isLowConfidence(confidenceThreshold)) {
        lowConfidence.add(index);
      }
    }
    return LyricReviewQueue(
      items: ranked,
      lowConfidenceIndices: Set<int>.unmodifiable(lowConfidence),
      totalLines: document.lines.length,
      scoredLines: document.lines.where((line) => line.hasConfidenceScore).length,
      reviewedLines: decisionService.reviewedIndices(document).length,
      confidenceThreshold: confidenceThreshold,
    );
  }

  /// Lines the engine never scored. They are not "low confidence": their score
  /// is unknown, and the numeric placeholder exists only for stable ordering.
  int get unscoredLines => (totalLines - scoredLines).clamp(0, totalLines);

  bool get hasAnyScore => scoredLines > 0;

  bool get isEmpty => items.isEmpty;

  /// The single number the editor shows as "待复核".
  int get needsReviewCount => items.length;

  /// Lines surfaced because of a real, low engine score. Always a subset of
  /// [needsReviewCount]: a low score is itself queue evidence, so it cannot
  /// produce a line that the queue omitted.
  int get lowConfidenceCount => lowConfidenceIndices.length;

  /// Whether the "low confidence" filter has anything to offer.
  ///
  /// Hiding it entirely when nothing was scored is the point of this class: an
  /// empty "低置信度 0" reads as "the engine checked everything and found no
  /// problems", which is exactly what an unscored document cannot claim.
  bool get canFilterByConfidence => hasAnyScore;

  Set<int> get indices => <int>{for (final item in items) item.lineIndex};

  Map<int, LyricReviewPriority> get byIndex => <int, LyricReviewPriority>{
    for (final item in items) item.lineIndex: item,
  };

  bool needsReview(int lineIndex) => byIndex.containsKey(lineIndex);

  bool isLowConfidence(int lineIndex) => lowConfidenceIndices.contains(lineIndex);
}
