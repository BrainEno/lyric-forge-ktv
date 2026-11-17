import '../../../project/domain/models/lyric_document.dart';
import '../services/lyric_review_decision_service.dart';
import 'lyric_review_queue.dart';
import 'secondary_only_suggestion.dart';

/// What the editor can honestly say about a recognised draft right after
/// recognition: who produced it, how many rows the engines disagreed on, how
/// many rows only the second engine heard, and how much is left to review.
///
/// Every count is nullable. Null means "this run did not collect it" (an old
/// project, a single-engine run, a degraded run) and the UI must say so; it is
/// never turned into a zero or a percentage. Nothing here is a probability.
class RecognitionReviewSummary {
  /// Metadata key the Whisper adapter writes its decoding profile under.
  static const String whisperDecodingKey = 'whisperDecoding';

  /// Engine identity of the row text (for example `qwen3-asr-1.7b`).
  final String? primaryEngine;

  /// Engine identity of the second opinion, when one ran.
  final String? secondaryEngine;

  /// `highestQuality` when two engines were requested.
  final String? qualityMode;

  /// True when a requested second engine did not contribute.
  final bool degraded;

  /// Whisper decoding profile the run actually used, e.g.
  /// `whisper-lyrics-v2`, and the one that was requested.
  final String? whisperEffectiveProfile;
  final String? whisperRequestedProfile;

  /// Why the requested Whisper profile was not fully applied, when it wasn't.
  final String? whisperFallbackReason;

  final int totalLines;

  /// Rows that still carry a disagreement between the two engines.
  final int? disagreementLines;

  /// "建议补入" rows still showing the second engine's exact text and timing.
  final int? secondaryOnlySuggestions;

  /// Of [secondaryOnlySuggestions], how many nobody has decided on yet.
  final int? pendingSecondaryOnlySuggestions;

  /// Second-engine rows that only re-segmented words already on screen and
  /// were therefore not inserted twice.
  final int? segmentationOnlySecondary;

  /// The editor's review queue size ("待复核").
  final int pendingReview;

  final int reviewedLines;

  const RecognitionReviewSummary({
    required this.primaryEngine,
    required this.secondaryEngine,
    required this.qualityMode,
    required this.degraded,
    required this.whisperEffectiveProfile,
    required this.whisperRequestedProfile,
    required this.whisperFallbackReason,
    required this.totalLines,
    required this.disagreementLines,
    required this.secondaryOnlySuggestions,
    required this.pendingSecondaryOnlySuggestions,
    required this.segmentationOnlySecondary,
    required this.pendingReview,
    required this.reviewedLines,
  });

  /// Whether this document carries any recognition metadata at all. Imported
  /// or hand-typed lyrics have none, and get no recognition summary.
  bool get hasRecognitionData =>
      primaryEngine != null ||
      qualityMode != null ||
      whisperEffectiveProfile != null;

  bool get ranTwoEngines => secondaryEngine != null && !degraded;

  bool get whisperProfileDegraded =>
      whisperRequestedProfile != null &&
      whisperEffectiveProfile != null &&
      whisperRequestedProfile != whisperEffectiveProfile;

  factory RecognitionReviewSummary.fromDocument(
    LyricDocument document,
    LyricReviewQueue queue, {
    LyricReviewDecisionService decisionService =
        const LyricReviewDecisionService(),
  }) {
    final metadata = document.metadata;
    final reviewed = decisionService.reviewedIndices(document);

    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;

    final whisper = metadata[whisperDecodingKey];
    final whisperMap = whisper is Map ? whisper : const {};

    int? disagreements;
    final rawCandidates = metadata['fallbackCandidates'];
    if (rawCandidates is List) {
      final indices = <int>{};
      for (final entry in rawCandidates) {
        if (entry is! Map) continue;
        final index = entry['lineIndex'];
        if (index is! int || index < 0 || index >= document.lines.length) {
          continue;
        }
        final alternative =
            text(entry['alternativeText']) ?? text(entry['whisperText']);
        final primary = text(entry['primaryText']) ?? text(entry['qwenText']);
        if (alternative == null) continue;
        if (primary != null && primary == alternative) continue;
        indices.add(index);
      }
      disagreements = indices.length;
    }

    int? suggestions;
    int? pendingSuggestions;
    if (metadata.containsKey(SecondaryOnlySuggestion.metadataKey)) {
      final resolved = SecondaryOnlySuggestion.resolve(document);
      suggestions = resolved.length;
      pendingSuggestions = resolved.keys
          .where((index) => !reviewed.contains(index))
          .length;
    }

    final segmentation = metadata['segmentationOnlySecondaryCount'];

    return RecognitionReviewSummary(
      primaryEngine:
          text(metadata['primaryEngine']) ?? text(metadata['generatedBy']),
      secondaryEngine: metadata['fallbackStatus'] == 'completed'
          ? text(metadata['fallbackEngine'])
          : null,
      qualityMode: text(metadata['qualityMode']),
      degraded: metadata['degraded'] == true,
      whisperEffectiveProfile: text(whisperMap['effectiveProfile']),
      whisperRequestedProfile: text(whisperMap['requestedProfile']),
      whisperFallbackReason: text(whisperMap['fallbackReason']),
      totalLines: document.lines.length,
      disagreementLines: disagreements,
      secondaryOnlySuggestions: suggestions,
      pendingSecondaryOnlySuggestions: pendingSuggestions,
      segmentationOnlySecondary: segmentation is int && segmentation >= 0
          ? segmentation
          : null,
      pendingReview: queue.needsReviewCount,
      reviewedLines: reviewed.length,
    );
  }
}
