import '../../../project/domain/models/lyric_document.dart';
import 'asr_reference_correction_suggester.dart';
import 'reference_proofread_review_builder.dart';

/// A display-ready, line-level before/after diff for explicit user review.
class ReferenceProofreadDiffRow {
  final int draftIndex;
  final String beforeText;
  final String afterText;
  final Duration beforeStart;
  final Duration beforeEnd;
  final Duration? afterStart;
  final Duration? afterEnd;
  final bool canApply;
  final String? blockedReason;

  const ReferenceProofreadDiffRow({
    required this.draftIndex,
    required this.beforeText,
    required this.afterText,
    required this.beforeStart,
    required this.beforeEnd,
    required this.afterStart,
    required this.afterEnd,
    required this.canApply,
    required this.blockedReason,
  });
}

/// The immutable result of a successful explicit apply, including its undo
/// snapshot. This domain object does not persist or mutate the editor state.
class ReferenceProofreadAppliedChange {
  final LyricDocument before;
  final LyricDocument after;
  final List<int> changedDraftIndices;

  ReferenceProofreadAppliedChange({
    required this.before,
    required this.after,
    required List<int> changedDraftIndices,
  }) : changedDraftIndices = List.unmodifiable(changedDraftIndices);

  /// Restore the exact pre-apply document, including metadata and offset.
  LyricDocument undo() => before;

  /// Reapply the exact committed result after an undo.
  LyricDocument redo() => after;
}

/// Builds line-level diffs and atomically applies only validated proposals.
class ReferenceProofreadChangeSet {
  const ReferenceProofreadChangeSet();

  List<ReferenceProofreadDiffRow> diff(
    LyricDocument draft,
    List<ReferenceProofreadReviewItem> proposals, {
    Set<int> protectedDraftIndices = const {},
  }) {
    return List.unmodifiable([
      for (final proposal in proposals)
        _diffRow(draft, proposal, protectedDraftIndices),
    ]);
  }

  /// Returns a new document or throws without changing [draft].
  ///
  /// All selected proposals are validated before any output lines are built.
  /// Duplicate indices, stale source text, protected lines, incomplete timing,
  /// and resulting overlaps reject the entire batch.
  ReferenceProofreadAppliedChange apply({
    required LyricDocument draft,
    required List<ReferenceProofreadReviewItem> proposals,
    required Set<int> selectedDraftIndices,
    Set<int> protectedDraftIndices = const {},
  }) {
    if (selectedDraftIndices.isEmpty) {
      throw ArgumentError.value(selectedDraftIndices, 'selectedDraftIndices',
          'Select at least one proposal.');
    }

    final byIndex = <int, ReferenceProofreadReviewItem>{};
    for (final proposal in proposals) {
      final index = proposal.correction.draftIndex;
      if (byIndex.containsKey(index)) {
        throw StateError('Duplicate proposal for draft line $index.');
      }
      byIndex[index] = proposal;
    }

    final selected = <int, ReferenceProofreadReviewItem>{};
    for (final index in selectedDraftIndices) {
      if (index < 0 || index >= draft.lines.length) {
        throw RangeError.index(index, draft.lines, 'selectedDraftIndices');
      }
      if (protectedDraftIndices.contains(index)) {
        throw StateError('Draft line $index is protected.');
      }
      final proposal = byIndex[index];
      if (proposal == null) {
        throw StateError('No review proposal exists for draft line $index.');
      }
      if (!proposal.canOfferCompleteProposal) {
        throw StateError('Draft line $index requires manual review.');
      }
      if (draft.lines[index].text != proposal.correction.currentText) {
        throw StateError('Draft line $index changed since review.');
      }
      if (proposal.retiming.draftIndex != index ||
          proposal.retiming.proposedText != proposal.correction.suggestedText ||
          proposal.retiming.options.length != 1) {
        throw StateError('Draft line $index has an inconsistent timing proposal.');
      }
      selected[index] = proposal;
    }

    final updatedLines = List.of(draft.lines);
    for (final entry in selected.entries) {
      final index = entry.key;
      final proposal = entry.value;
      final timing = proposal.retiming.options.single;
      updatedLines[index] = draft.lines[index].copyWith(
        text: proposal.correction.suggestedText,
        startTime: timing.startTime,
        endTime: timing.endTime,
      );
    }

    // Validate changed intervals and their boundaries. Unrelated pre-existing
    // timeline defects must not block a text correction elsewhere in the song.
    for (final index in selected.keys) {
      final line = updatedLines[index];
      if (line.startTime.isNegative || line.endTime <= line.startTime) {
        throw StateError('Resulting timing is invalid at draft line $index.');
      }
    }
    for (var i = 1; i < updatedLines.length; i++) {
      if (!selected.containsKey(i) && !selected.containsKey(i - 1)) continue;
      if (updatedLines[i].startTime < updatedLines[i - 1].endTime) {
        throw StateError('Resulting lines overlap at draft line $i.');
      }
    }

    final after = draft.copyWith(lines: List.unmodifiable(updatedLines));
    return ReferenceProofreadAppliedChange(
      before: draft,
      after: after,
      changedDraftIndices: selected.keys.toList()..sort(),
    );
  }

  /// Atomically applies selected text suggestions while preserving the draft's
  /// existing timestamps. This is not a retiming operation; timing evidence
  /// must be reviewed separately and reference timestamps are never copied.
  ReferenceProofreadAppliedChange applyTextOnly({
    required LyricDocument draft,
    required List<AsrReferenceCorrectionSuggestion> suggestions,
    required Set<int> selectedDraftIndices,
    Set<int> protectedDraftIndices = const {},
  }) {
    if (selectedDraftIndices.isEmpty) {
      throw ArgumentError.value(
        selectedDraftIndices,
        'selectedDraftIndices',
        'Select at least one proposal.',
      );
    }
    final byIndex = <int, AsrReferenceCorrectionSuggestion>{};
    for (final suggestion in suggestions) {
      if (byIndex.containsKey(suggestion.draftIndex)) {
        throw StateError(
          'Duplicate proposal for draft line ${suggestion.draftIndex}.',
        );
      }
      byIndex[suggestion.draftIndex] = suggestion;
    }

    final selected = <int, AsrReferenceCorrectionSuggestion>{};
    for (final index in selectedDraftIndices) {
      if (index < 0 || index >= draft.lines.length) {
        throw RangeError.index(index, draft.lines, 'selectedDraftIndices');
      }
      if (protectedDraftIndices.contains(index)) {
        throw StateError('Draft line $index is protected.');
      }
      final suggestion = byIndex[index];
      if (suggestion == null || suggestion.draftIndex != index) {
        throw StateError('No review proposal exists for draft line $index.');
      }
      if (suggestion.requiresManualReview) {
        throw StateError('Draft line $index requires manual review.');
      }
      if (draft.lines[index].text != suggestion.currentText) {
        throw StateError('Draft line $index changed since review.');
      }
      if (suggestion.suggestedText.trim().isEmpty) {
        throw StateError('Draft line $index has an empty correction.');
      }
      selected[index] = suggestion;
    }

    final updatedLines = List.of(draft.lines);
    for (final entry in selected.entries) {
      final index = entry.key;
      updatedLines[index] = draft.lines[index].copyWith(
        text: entry.value.suggestedText,
      );
    }
    final after = draft.copyWith(lines: List.unmodifiable(updatedLines));
    return ReferenceProofreadAppliedChange(
      before: draft,
      after: after,
      changedDraftIndices: selected.keys.toList()..sort(),
    );
  }

  ReferenceProofreadDiffRow _diffRow(
    LyricDocument draft,
    ReferenceProofreadReviewItem proposal,
    Set<int> protectedDraftIndices,
  ) {
    final correction = proposal.correction;
    final index = correction.draftIndex;
    if (index < 0 || index >= draft.lines.length) {
      return ReferenceProofreadDiffRow(
        draftIndex: index,
        beforeText: correction.currentText,
        afterText: correction.suggestedText,
        beforeStart: Duration.zero,
        beforeEnd: Duration.zero,
        afterStart: null,
        afterEnd: null,
        canApply: false,
        blockedReason: 'Draft line no longer exists.',
      );
    }
    final source = draft.lines[index];
    String? reason;
    if (protectedDraftIndices.contains(index)) {
      reason = 'Protected line.';
    } else if (source.text != correction.currentText) {
      reason = 'Draft changed since proposal was generated.';
    } else if (!proposal.canOfferCompleteProposal) {
      reason = 'Manual review required for text or timing.';
    } else if (proposal.retiming.options.length != 1) {
      reason = 'Timing proposal is not unique.';
    }

    final timing = proposal.retiming.options.length == 1
        ? proposal.retiming.options.single
        : null;
    return ReferenceProofreadDiffRow(
      draftIndex: index,
      beforeText: source.text,
      afterText: correction.suggestedText,
      beforeStart: source.startTime,
      beforeEnd: source.endTime,
      afterStart: timing?.startTime,
      afterEnd: timing?.endTime,
      canApply: reason == null,
      blockedReason: reason,
    );
  }
}
