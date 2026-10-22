import '../../../project/domain/models/lyric_document.dart';
import '../services/lyric_alignment_service.dart';
import 'asr_consensus_analyzer.dart';

enum AsrHallucinationReason { lowConfidence, noSecondaryOverlap }

class AsrHallucinationCandidate {
  final int primaryIndex;
  final LyricLine line;
  final Set<AsrHallucinationReason> reasons;

  AsrHallucinationCandidate({
    required this.primaryIndex,
    required this.line,
    required Set<AsrHallucinationReason> reasons,
  }) : reasons = Set.unmodifiable(reasons);
}

/// Holds conservative suspicion candidates for manual review; nothing is deleted.
class AsrHallucinationFilterResult {
  final List<AsrHallucinationCandidate> candidates;

  AsrHallucinationFilterResult({
    required List<AsrHallucinationCandidate> candidates,
  }) : candidates = List.unmodifiable(candidates);
}

/// Marks only low-confidence primary lines with no time-overlapping secondary
/// evidence. Nearby unmatched secondary lines suppress a candidate because
/// transcript timing/segmentation may differ. This filter never edits lyrics.
class AsrHallucinationCandidateFilter {
  final int lowConfidenceThreshold;
  final Duration nearbySecondaryTolerance;

  const AsrHallucinationCandidateFilter({
    this.lowConfidenceThreshold = 60,
    this.nearbySecondaryTolerance = const Duration(milliseconds: 1500),
  }) : assert(lowConfidenceThreshold >= 0 && lowConfidenceThreshold <= 100),
       assert(nearbySecondaryTolerance >= Duration.zero);

  AsrHallucinationFilterResult analyze(AsrConsensusResult evidence) {
    final candidates = <AsrHallucinationCandidate>[];
    for (final row in evidence.rows) {
      final line = row.primaryLine;
      if (row.status != AsrConsensusStatus.primaryOnly ||
          !row.reasons.contains(AsrConsensusReason.noSecondaryOverlap) ||
          row.secondaryLineIndices.isNotEmpty ||
          row.secondaryText != null ||
          line.confidence >= lowConfidenceThreshold ||
          LyricAlignmentService.normalizeLine(line.text).isEmpty ||
          _hasNearbySecondaryEvidence(line, evidence.secondaryOnlyLines)) {
        continue;
      }

      candidates.add(
        AsrHallucinationCandidate(
          primaryIndex: row.primaryIndex,
          line: line,
          reasons: const {
            AsrHallucinationReason.lowConfidence,
            AsrHallucinationReason.noSecondaryOverlap,
          },
        ),
      );
    }
    return AsrHallucinationFilterResult(candidates: candidates);
  }

  bool _hasNearbySecondaryEvidence(
    LyricLine primary,
    List<AsrConsensusSecondaryOnlyLine> secondaryOnlyLines,
  ) {
    for (final secondary in secondaryOnlyLines) {
      if (_intervalGap(primary, secondary.line) <= nearbySecondaryTolerance) {
        return true;
      }
    }
    return false;
  }

  Duration _intervalGap(LyricLine first, LyricLine second) {
    if (first.endTime < second.startTime) {
      return second.startTime - first.endTime;
    }
    if (second.endTime < first.startTime) {
      return first.startTime - second.endTime;
    }
    return Duration.zero;
  }
}
