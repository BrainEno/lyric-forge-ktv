import '../../../project/domain/models/lyric_document.dart';
import '../models/timing_provenance.dart';
import 'proofread_review_proposal.dart';
import 'proofread_strategy_selector.dart';

/// Reasons an explicitly selected reference interval cannot be safely applied.
enum ReferenceTimingApplyFailure {
  wrongStrategy,
  unknownSelection,
  duplicateProposal,
  missingEvidence,
  protectedLine,
  unacceptedInsertion,
  textMismatch,
  offsetChanged,
  negativeStoredTime,
  ambiguousLineIdentity,
  invalidInterval,
}

class ReferenceTimingApplyException implements Exception {
  final ReferenceTimingApplyFailure reason;
  const ReferenceTimingApplyException(this.reason);
}

/// Applies explicit, individually checked timing choices to a composed draft.
///
/// [outputIndexByProposal] is built by the composer while constructing the
/// document, after restorations and ID assignment. It must never be inferred by
/// text or timing: repeated lines, dropped rows and null IDs make that unsafe.
/// The caller must verify audio/project freshness and obtain user confirmation
/// for newly introduced timeline conflicts. This class does not persist data.
class ReferenceAlignmentTimingApplier {
  const ReferenceAlignmentTimingApplier();

  LyricDocument apply({
    required LyricDocument before,
    required LyricDocument composed,
    required List<LyricProofreadV2ReviewItem> items,
    required LyricProofreadV2Selection selection,
    required LyricSourceStrategy effectiveStrategy,
    required Map<int, int> outputIndexByProposal,
  }) {
    final selected = selection.acceptedReferenceTimingIndices;
    if (selected.isEmpty) return composed;
    if (effectiveStrategy != LyricSourceStrategy.referenceFirst) {
      throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.wrongStrategy);
    }
    // Existing reference composition can reset the offset. Mixing that with
    // selected absolute aligner times could silently move untouched lines.
    if ((before.globalOffset ?? Duration.zero) != (composed.globalOffset ?? Duration.zero)) {
      throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.offsetChanged);
    }
    final byProposal = <int, LyricProofreadV2ReviewItem>{};
    for (final item in items) {
      if (byProposal.containsKey(item.proposalIndex)) {
        throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.duplicateProposal);
      }
      byProposal[item.proposalIndex] = item;
    }
    final ids = composed.lines.map((line) => line.id).toList();
    if (ids.any((id) => id == null || id.isEmpty) || ids.toSet().length != ids.length) {
      throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.ambiguousLineIdentity);
    }
    final output = List<LyricLine>.from(composed.lines);
    final offset = composed.globalOffset ?? Duration.zero;
    final rawProvenance = composed.metadata[kLyricTimingProvenanceKey];
    final provenance = <String, dynamic>{
      if (rawProvenance is Map)
        for (final entry in rawProvenance.entries)
          if (entry.key is String) entry.key as String: entry.value,
    };
    final usedOutput = <int>{};
    for (final index in selected) {
      final item = byProposal[index];
      if (item == null) {
        throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.unknownSelection);
      }
      if (item.verdict == LyricProofreadReviewVerdict.locked) {
        throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.protectedLine);
      }
      final evidence = item.referenceTimingEvidence;
      if (evidence == null) {
        throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.missingEvidence);
      }
      if (item.sourceIndex == null && !selection.acceptedProposalIndices.contains(index)) {
        throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.unacceptedInsertion);
      }
      final at = outputIndexByProposal[index];
      if (at == null || at < 0 || at >= output.length || !usedOutput.add(at)) {
        throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.ambiguousLineIdentity);
      }
      final current = output[at];
      if (current.text != evidence.referenceText) {
        throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.textMismatch);
      }
      final start = evidence.start - offset;
      final end = evidence.end - offset;
      if (evidence.start.isNegative || evidence.end <= evidence.start) {
        throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.invalidInterval);
      }
      if (start.isNegative) {
        throw const ReferenceTimingApplyException(ReferenceTimingApplyFailure.negativeStoredTime);
      }
      if (current.startTime == start && current.endTime == end) continue;
      output[at] = current.copyWith(startTime: start, endTime: end);
      provenance[current.id!] = LyricTimingProvenance.forcedAlignmentReference.name;
    }
    return composed.copyWith(
      lines: output,
      metadata: {...composed.metadata, kLyricTimingProvenanceKey: provenance},
    );
  }
}
