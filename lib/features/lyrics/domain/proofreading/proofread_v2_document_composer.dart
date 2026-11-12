import '../../../project/domain/models/lyric_document.dart';
import '../services/lyric_manual_edit_marker_service.dart';
import 'proofread_review_proposal.dart';
import 'proofread_strategy_selector.dart';
import 'reference_alignment_timing_applier.dart';

/// Builds the document that the review dialog's selection describes.
///
/// The rules encoded here are the ones that used to live inside the editor
/// widget:
///
/// * a locked row always applies, an unlocked row only when the dialog reports
///   it as accepted;
/// * proposals keep their pipeline order, and draft lines the pipeline dropped
///   come back only when the user restored them — re-inserted by timestamp so
///   the review order and the timeline order can differ;
/// * a line id keeps its timing provenance only while the timing it describes
///   still belongs to that line;
/// * a reference-first run that moved any timing resets the global offset,
///   because the new timestamps are already absolute.
class ProofreadV2DocumentComposer {
  final LyricManualEditMarkerService markerService;

  const ProofreadV2DocumentComposer({
    this.markerService = const LyricManualEditMarkerService(),
  });

  LyricDocument compose({
    required LyricDocument before,
    required LyricDocument proposalDocument,
    required List<LyricProofreadV2ReviewItem> items,
    required List<LyricProofreadV2DroppedItem> droppedItems,
    required LyricProofreadV2Selection selection,
    required LyricSourceStrategy effectiveStrategy,
  }) {
    final accepted = selection.acceptedProposalIndices;
    final droppedIndices = droppedItems.map((item) => item.sourceIndex).toSet();
    final consumedDraftIndices = <int>{};
    final candidates = <({LyricLine line, int order, int? proposalIndex})>[];
    var order = 0;

    for (final item in items) {
      final shouldAccept =
          item.verdict == LyricProofreadReviewVerdict.locked ||
          accepted.contains(item.proposalIndex);
      final sourceIndex = item.sourceIndex;
      if (sourceIndex != null) {
        if (sourceIndex < 0 ||
            sourceIndex >= before.lines.length ||
            !consumedDraftIndices.add(sourceIndex)) {
          continue;
        }
        candidates.add((
          line: shouldAccept ? item.proposedLine : before.lines[sourceIndex],
          order: order++,
          proposalIndex: item.proposalIndex,
        ));
      } else if (shouldAccept) {
        candidates.add((
          line: item.proposedLine,
          order: order++,
          proposalIndex: item.proposalIndex,
        ));
      }
    }

    final restoredCandidates =
        <({LyricLine line, int order, int? proposalIndex})>[];
    for (var index = 0; index < before.lines.length; index++) {
      if (consumedDraftIndices.contains(index)) continue;
      final shouldRestore = selection.restoredDraftIndices.contains(index);
      if (shouldRestore || !droppedIndices.contains(index)) {
        restoredCandidates.add((
          line: before.lines[index],
          order: order++,
          proposalIndex: null,
        ));
      }
    }
    restoredCandidates.sort((left, right) {
      final byStart = left.line.startTime.compareTo(right.line.startTime);
      if (byStart != 0) return byStart;
      return left.order.compareTo(right.order);
    });
    for (final restored in restoredCandidates) {
      var insertion = 0;
      while (insertion < candidates.length &&
          candidates[insertion].line.startTime <= restored.line.startTime) {
        insertion++;
      }
      candidates.insert(insertion, restored);
    }
    final lines = candidates.map((candidate) => candidate.line).toList();

    final metadata = Map<String, dynamic>.from(before.metadata);
    const timingKey = 'timingProvenance';
    final originalProvenance = metadata[timingKey];
    final proposedProvenance = proposalDocument.metadata[timingKey];
    final timingProvenance = <String, dynamic>{
      if (originalProvenance is Map)
        ...Map<String, dynamic>.from(originalProvenance),
    };
    final acceptedChanges = items.where(
      (item) =>
          item.verdict == LyricProofreadReviewVerdict.locked ||
          accepted.contains(item.proposalIndex),
    );
    for (final item in acceptedChanges) {
      final id = item.proposedLine.id;
      if (id == null) continue;
      if (proposedProvenance is Map && proposedProvenance.containsKey(id)) {
        timingProvenance[id] = proposedProvenance[id];
      } else if (item.hasChange) {
        timingProvenance.remove(id);
      }
    }
    final outputIds = lines.map((line) => line.id).whereType<String>().toSet();
    timingProvenance.removeWhere((id, _) => !outputIds.contains(id));
    if (originalProvenance is Map || proposedProvenance is Map) {
      metadata[timingKey] = timingProvenance;
    }

    final timingChanged = acceptedChanges.any(
      (item) =>
          item.originalLine == null ||
          item.originalLine!.startTime != item.proposedLine.startTime ||
          item.originalLine!.endTime != item.proposedLine.endTime,
    );
    // A reset would move retained draft rows, including protected/restored
    // rows. Refuse the whole operation rather than silently changing playback.
    if (effectiveStrategy == LyricSourceStrategy.referenceFirst &&
        timingChanged &&
        (before.globalOffset ?? Duration.zero) != Duration.zero) {
      final preservedSources = candidates.any((candidate) {
        if (candidate.proposalIndex == null) return true;
        final item = items.firstWhere(
          (item) => item.proposalIndex == candidate.proposalIndex,
        );
        final source = item.sourceIndex;
        if (source == null) return false;
        if (item.verdict == LyricProofreadReviewVerdict.locked ||
            !accepted.contains(item.proposalIndex))
          return true;
        return candidate.line.startTime == before.lines[source].startTime &&
            candidate.line.endTime == before.lines[source].endTime;
      });
      if (preservedSources) {
        throw const ReferenceTimingApplyException(
          ReferenceTimingApplyFailure.offsetChanged,
        );
      }
    }
    final offset =
        effectiveStrategy == LyricSourceStrategy.referenceFirst && timingChanged
        ? Duration.zero
        : before.globalOffset;
    final candidate = LyricDocument(
      language: before.language,
      lines: lines,
      globalOffset: offset,
      metadata: metadata,
    );
    final withIds = markerService.assignMissingLineIds(candidate);
    return const ReferenceAlignmentTimingApplier().apply(
      before: before,
      composed: withIds,
      items: items,
      selection: selection,
      effectiveStrategy: effectiveStrategy,
      outputIndexByProposal: {
        for (var index = 0; index < candidates.length; index++)
          if (candidates[index].proposalIndex case final int proposalIndex)
            proposalIndex: index,
      },
    );
  }

  /// Whether [after] differs from [before] in any way a commit would record.
  bool isDifferent(LyricDocument before, LyricDocument after) {
    if (before.globalOffset != after.globalOffset) return true;
    final left = before.lines;
    final right = after.lines;
    if (left.length != right.length) return true;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.text != b.text ||
          a.startTime != b.startTime ||
          a.endTime != b.endTime ||
          a.isChorus != b.isChorus ||
          a.confidence != b.confidence) {
        return true;
      }
    }
    return false;
  }
}
