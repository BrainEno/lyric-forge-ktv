import '../../../project/domain/models/lyric_document.dart';
import '../services/lyric_alignment_service.dart';

enum AsrConsensusStatus { agreement, disagreement, primaryOnly }

enum AsrConsensusReason {
  textMismatch,
  lowPrimaryConfidence,
  lowSecondaryConfidence,
  noSecondaryOverlap,
  comparisonLimitExceeded,
}

class AsrConsensusRow {
  final int primaryIndex;
  final LyricLine primaryLine;
  final List<int> secondaryLineIndices;
  final String? secondaryText;
  final int? secondaryConfidence;
  final double? textSimilarity;
  final AsrConsensusStatus status;
  final Set<AsrConsensusReason> reasons;

  AsrConsensusRow({
    required this.primaryIndex,
    required this.primaryLine,
    required List<int> secondaryLineIndices,
    required this.secondaryText,
    required this.secondaryConfidence,
    required this.textSimilarity,
    required this.status,
    required Set<AsrConsensusReason> reasons,
  }) : secondaryLineIndices = List.unmodifiable(secondaryLineIndices),
       reasons = Set.unmodifiable(reasons);
}

class AsrConsensusSecondaryOnlyLine {
  final int lineIndex;
  final LyricLine line;
  const AsrConsensusSecondaryOnlyLine({
    required this.lineIndex,
    required this.line,
  });
}

class AsrConsensusResult {
  final List<AsrConsensusRow> rows;
  final List<AsrConsensusSecondaryOnlyLine> secondaryOnlyLines;

  AsrConsensusResult({
    required List<AsrConsensusRow> rows,
    required List<AsrConsensusSecondaryOnlyLine> secondaryOnlyLines,
  }) : rows = List.unmodifiable(rows),
       secondaryOnlyLines = List.unmodifiable(secondaryOnlyLines);

  bool get hasDisagreements =>
      rows.any((row) => row.status == AsrConsensusStatus.disagreement);
}

/// Compares two transcripts without changing lyric text or timing.
/// Secondary segments may be joined as evidence when one engine split a phrase.
class AsrConsensusAnalyzer {
  final Duration overlapPadding;
  final double agreementSimilarityThreshold;
  final int reviewConfidenceThreshold;
  final int maxComparedRunes;

  const AsrConsensusAnalyzer({
    this.overlapPadding = const Duration(milliseconds: 450),
    this.agreementSimilarityThreshold = 0.80,
    this.reviewConfidenceThreshold = 60,
    this.maxComparedRunes = 512,
  }) : assert(
         agreementSimilarityThreshold >= 0 && agreementSimilarityThreshold <= 1,
       ),
       assert(
         reviewConfidenceThreshold >= 0 && reviewConfidenceThreshold <= 100,
       ),
       assert(maxComparedRunes > 0);

  AsrConsensusResult analyze({
    required LyricDocument primary,
    required LyricDocument secondary,
  }) {
    if (overlapPadding.isNegative) {
      throw ArgumentError.value(
        overlapPadding,
        'overlapPadding',
        'Must be non-negative.',
      );
    }
    final usedSecondary = <int>{};
    final rows = <AsrConsensusRow>[];
    for (var pi = 0; pi < primary.lines.length; pi++) {
      final line = primary.lines[pi];
      final indices = <int>[
        for (var si = 0; si < secondary.lines.length; si++)
          if (_overlaps(line, secondary.lines[si])) si,
      ];
      usedSecondary.addAll(indices);
      final reasons = <AsrConsensusReason>{};
      if (line.isLowConfidence(reviewConfidenceThreshold)) {
        reasons.add(AsrConsensusReason.lowPrimaryConfidence);
      }
      if (indices.isEmpty) {
        reasons.add(AsrConsensusReason.noSecondaryOverlap);
        rows.add(
          AsrConsensusRow(
            primaryIndex: pi,
            primaryLine: line,
            secondaryLineIndices: const [],
            secondaryText: null,
            secondaryConfidence: null,
            textSimilarity: null,
            status: AsrConsensusStatus.primaryOnly,
            reasons: reasons,
          ),
        );
        continue;
      }

      final alternatives = [for (final i in indices) secondary.lines[i]];
      final text = _joinText(alternatives);
      // Averaging placeholder scores would invent a confidence the engine never
      // produced, so only scored alternatives contribute; none means unknown.
      final scoredAlternatives = alternatives
          .where((line) => line.hasConfidenceScore)
          .toList(growable: false);
      final confidence = scoredAlternatives.isEmpty
          ? null
          : (scoredAlternatives.fold<int>(
                      0,
                      (sum, row) => sum + row.confidence,
                    ) /
                    scoredAlternatives.length)
                .round()
                .clamp(0, 100)
                .toInt();
      double? similarity;
      if (_exceedsBudget(line.text, text)) {
        reasons.add(AsrConsensusReason.comparisonLimitExceeded);
      } else {
        similarity = LyricAlignmentService.lineSimilarity(line.text, text);
        if (similarity < agreementSimilarityThreshold) {
          reasons.add(AsrConsensusReason.textMismatch);
        }
      }
      if (confidence != null && confidence < reviewConfidenceThreshold) {
        reasons.add(AsrConsensusReason.lowSecondaryConfidence);
      }
      rows.add(
        AsrConsensusRow(
          primaryIndex: pi,
          primaryLine: line,
          secondaryLineIndices: indices,
          secondaryText: text,
          secondaryConfidence: confidence,
          textSimilarity: similarity,
          status: reasons.isEmpty
              ? AsrConsensusStatus.agreement
              : AsrConsensusStatus.disagreement,
          reasons: reasons,
        ),
      );
    }

    return AsrConsensusResult(
      rows: rows,
      secondaryOnlyLines: [
        for (var i = 0; i < secondary.lines.length; i++)
          if (!usedSecondary.contains(i))
            AsrConsensusSecondaryOnlyLine(
              lineIndex: i,
              line: secondary.lines[i],
            ),
      ],
    );
  }

  bool _overlaps(LyricLine primary, LyricLine secondary) {
    final start = primary.startTime - overlapPadding;
    final end = primary.endTime + overlapPadding;
    return (secondary.endTime < end ? secondary.endTime : end) >
        (secondary.startTime > start ? secondary.startTime : start);
  }

  bool _exceedsBudget(String a, String b) =>
      a.runes.length > maxComparedRunes || b.runes.length > maxComparedRunes;

  String _joinText(List<LyricLine> lines) {
    final parts = lines
        .map((line) => line.text.trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '';
    final cjk = parts.join().runes.any(
      (rune) =>
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3040 && rune <= 0x30FF) ||
          (rune >= 0xAC00 && rune <= 0xD7AF),
    );
    return parts.join(cjk ? '' : ' ');
  }
}
