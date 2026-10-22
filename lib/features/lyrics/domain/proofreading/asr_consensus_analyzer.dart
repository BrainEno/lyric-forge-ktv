import '../../../project/domain/models/lyric_document.dart';
import '../services/lyric_alignment_service.dart';

enum AsrConsensusStatus { agreement, disagreement, primaryOnly }

enum AsrConsensusReason {
  textMismatch,
  lowPrimaryConfidence,
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

  int get agreementCount =>
      rows.where((row) => row.status == AsrConsensusStatus.agreement).length;
}

/// Compares two already-transcribed documents without changing their text or timing.
///
/// A row can collect several secondary segments when one engine split a phrase
/// differently. This is evidence for review, not a command to replace the row.
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
  }) : assert(overlapPadding >= Duration.zero),
       assert(agreementSimilarityThreshold >= 0 &&
           agreementSimilarityThreshold <= 1),
       assert(reviewConfidenceThreshold >= 0 && reviewConfidenceThreshold <= 100),
       assert(maxComparedRunes > 0);

  AsrConsensusResult analyze({
    required LyricDocument primary,
    required LyricDocument secondary,
  }) {
    final secondaryUsed = <int>{};
    final rows = <AsrConsensusRow>[];

    for (var primaryIndex = 0;
        primaryIndex < primary.lines.length;
        primaryIndex++) {
      final primaryLine = primary.lines[primaryIndex];
      final overlaps = <int>[];
      for (var secondaryIndex = 0;
          secondaryIndex < secondary.lines.length;
          secondaryIndex++) {
        if (_overlaps(primaryLine, secondary.lines[secondaryIndex])) {
          overlaps.add(secondaryIndex);
          secondaryUsed.add(secondaryIndex);
        }
      }

      final reasons = <AsrConsensusReason>{};
      if (primaryLine.confidence < reviewConfidenceThreshold) {
        reasons.add(AsrConsensusReason.lowPrimaryConfidence);
      }
      if (overlaps.isEmpty) {
        reasons.add(AsrConsensusReason.noSecondaryOverlap);
        rows.add(AsrConsensusRow(
          primaryIndex: primaryIndex,
          primaryLine: primaryLine,
          secondaryLineIndices: const [],
          secondaryText: null,
          secondaryConfidence: null,
          textSimilarity: null,
          status: AsrConsensusStatus.primaryOnly,
          reasons: reasons,
        ));
        continue;
      }

      final secondaryLines = [
        for (final index in overlaps) secondary.lines[index],
      ];
      final alternativeText = _joinText(secondaryLines);
      final alternativeConfidence = (secondaryLines.fold<int>(
                0,
                (sum, line) => sum + line.confidence,
              ) /
              secondaryLines.length)
          .round()
          .clamp(0, 100)
          .toInt();

      double? similarity;
      if (_exceedsComparisonBudget(primaryLine.text, alternativeText)) {
        reasons.add(AsrConsensusReason.comparisonLimitExceeded);
      } else {
        similarity = LyricAlignmentService.lineSimilarity(
          primaryLine.text,
          alternativeText,
        );
        if (similarity < agreementSimilarityThreshold) {
          reasons.add(AsrConsensusReason.textMismatch);
        }
      }
      if (alternativeConfidence < reviewConfidenceThreshold) {
        reasons.add(AsrConsensusReason.lowPrimaryConfidence);
      }

      final status = reasons.isEmpty
          ? AsrConsensusStatus.agreement
          : AsrConsensusStatus.disagreement;
      rows.add(AsrConsensusRow(
        primaryIndex: primaryIndex,
        primaryLine: primaryLine,
        secondaryLineIndices: overlaps,
        secondaryText: alternativeText,
        secondaryConfidence: alternativeConfidence,
        textSimilarity: similarity,
        status: status,
        reasons: reasons,
      ));
    }

    return AsrConsensusResult(
      rows: rows,
      secondaryOnlyLines: [
        for (var index = 0; index < secondary.lines.length; index++)
          if (!secondaryUsed.contains(index))
            AsrConsensusSecondaryOnlyLine(
              lineIndex: index,
              line: secondary.lines[index],
            ),
      ],
    );
  }

  bool _overlaps(LyricLine primary, LyricLine secondary) {
    final start = primary.startTime - overlapPadding;
    final end = primary.endTime + overlapPadding;
    final overlapStart =
        secondary.startTime > start ? secondary.startTime : start;
    final overlapEnd = secondary.endTime < end ? secondary.endTime : end;
    return overlapEnd > overlapStart;
  }

  bool _exceedsComparisonBudget(String primary, String secondary) =>
      primary.runes.length > maxComparedRunes ||
      secondary.runes.length > maxComparedRunes;

  String _joinText(List<LyricLine> lines) {
    final parts = lines
        .map((line) => line.text.trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '';
    final joined = parts.join();
    final hasCjk = joined.runes.any(_isCjkRune);
    return parts.join(hasCjk ? '' : ' ');
  }

  bool _isCjkRune(int rune) =>
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0xAC00 && rune <= 0xD7AF);
}
