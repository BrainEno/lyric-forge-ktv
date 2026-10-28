import '../services/lyric_alignment_service.dart';
import 'asr_consensus_analyzer.dart';

enum AsrRepetitionSide { primary, secondary }

/// A manual-review proposal backed by a repeated span present in only one ASR.
class AsrRepetitionSuggestion {
  final int primaryIndex;
  final AsrRepetitionSide suspectSide;
  final String originalText;
  final String suggestedText;

  /// The repeated phrase normalized by lyric alignment, not display-ready text.
  final String repeatedUnitNormalized;

  const AsrRepetitionSuggestion({
    required this.primaryIndex,
    required this.suspectSide,
    required this.originalText,
    required this.suggestedText,
    required this.repeatedUnitNormalized,
  });
}

class AsrRepetitionResult {
  final List<AsrRepetitionSuggestion> suggestions;

  AsrRepetitionResult({required List<AsrRepetitionSuggestion> suggestions})
    : suggestions = List.unmodifiable(suggestions);

}

/// Returns conservative dual-ASR de-duplication candidates for manual review.
/// It never changes transcript text or timestamps.
class AsrRepetitionAnalyzer {
  final int reviewConfidenceThreshold;
  final int minimumRepeatedRunes;
  final int maxComparedRunes;

  const AsrRepetitionAnalyzer({
    this.reviewConfidenceThreshold = 75,
    this.minimumRepeatedRunes = 3,
    this.maxComparedRunes = 512,
  }) : assert(reviewConfidenceThreshold >= 0 && reviewConfidenceThreshold <= 100),
       assert(minimumRepeatedRunes > 0),
       assert(maxComparedRunes > 0);

  AsrRepetitionResult analyze(AsrConsensusResult evidence) {
    final suggestions = <AsrRepetitionSuggestion>[];
    for (final row in evidence.rows) {
      final alternative = row.secondaryText;
      final alternativeConfidence = row.secondaryConfidence;
      if (alternative == null ||
          alternativeConfidence == null ||
          row.primaryLine.confidence < reviewConfidenceThreshold ||
          alternativeConfidence < reviewConfidenceThreshold) {
        continue;
      }
      if (row.primaryLine.text.runes.length > maxComparedRunes ||
          alternative.runes.length > maxComparedRunes) {
        continue;
      }

      final primaryNormalized =
          LyricAlignmentService.normalizeLine(row.primaryLine.text);
      final secondaryNormalized = LyricAlignmentService.normalizeLine(alternative);
      if (primaryNormalized.isEmpty ||
          secondaryNormalized.isEmpty ||
          primaryNormalized == secondaryNormalized) {
        continue;
      }

      final primaryCollapse = _findExactCollapse(
        primaryNormalized,
        secondaryNormalized,
      );
      final secondaryCollapse = _findExactCollapse(
        secondaryNormalized,
        primaryNormalized,
      );

      // Never guess when both transcripts admit de-duplication.
      if ((primaryCollapse == null) == (secondaryCollapse == null)) continue;

      if (primaryCollapse != null) {
        suggestions.add(
          AsrRepetitionSuggestion(
            primaryIndex: row.primaryIndex,
            suspectSide: AsrRepetitionSide.primary,
            originalText: row.primaryLine.text,
            suggestedText: alternative,
            repeatedUnitNormalized: primaryCollapse,
          ),
        );
      } else {
        suggestions.add(
          AsrRepetitionSuggestion(
            primaryIndex: row.primaryIndex,
            suspectSide: AsrRepetitionSide.secondary,
            originalText: alternative,
            suggestedText: row.primaryLine.text,
            repeatedUnitNormalized: secondaryCollapse!,
          ),
        );
      }
    }
    return AsrRepetitionResult(suggestions: suggestions);
  }

  String? _findExactCollapse(String source, String target) {
    final runes = source.runes.toList(growable: false);
    final targetRunes = target.runes.toList(growable: false);
    final length = runes.length - targetRunes.length;
    if (length < minimumRepeatedRunes || 2 * length > runes.length) {
      return null;
    }

    // The length difference fixes the repeated unit length.
    for (var start = 0; start + 2 * length <= runes.length; start++) {
      var repeated = true;
      for (var i = 0; i < length; i++) {
        if (runes[start + i] != runes[start + length + i]) {
          repeated = false;
          break;
        }
      }
      if (!repeated) continue;

      var targetIndex = 0;
      var matchesTarget = true;
      for (var i = 0; i < runes.length; i++) {
        if (i >= start + length && i < start + 2 * length) continue;
        if (runes[i] != targetRunes[targetIndex++]) {
          matchesTarget = false;
          break;
        }
      }
      if (matchesTarget) {
        return String.fromCharCodes(runes.skip(start).take(length));
      }
    }
    return null;
  }
}
