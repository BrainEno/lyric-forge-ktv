import '../../../project/domain/models/lyric_document.dart';
import '../models/reference_lyric_input.dart';
import '../services/lyric_alignment_service.dart';
import '../services/lyric_manual_edit_marker_service.dart';
import '../services/reference_alignment_applier.dart';
import '../services/reference_alignment_provenance_builder.dart';
import '../services/reference_alignment_restore_service.dart';

/// Why an otherwise timed reference cannot replace the complete timeline.
/// Untimed references and usable timelines both return null for compatibility
/// with the existing review UI, which separately checks whether input is timed.
enum ReferenceTimingUnavailableReason {
  partiallyTimed,
  structuralMismatch,
  protectedLines,
}

/// A review-only alignment against a particular editor snapshot. The caller
/// must verify the editor revision before previewing or committing the result.
class ReferenceAlignmentPlan {
  final LyricDocument draft;
  final ReferenceLyricInput input;
  final LyricAlignmentResult alignment;
  final Set<int> protectedLineIndices;
  final Duration? audioDuration;
  final double minimumSimilarity;
  final ReferenceTimingUnavailableReason? timingUnavailableReason;

  ReferenceAlignmentPlan._({
    required this.draft,
    required this.input,
    required this.alignment,
    required Set<int> protectedLineIndices,
    required this.audioDuration,
    required this.minimumSimilarity,
    required this.timingUnavailableReason,
  }) : protectedLineIndices = Set.unmodifiable(protectedLineIndices);

  bool get isEmpty => alignment.entries.isEmpty;

  /// Computes a proposal only; the caller must explicitly confirm any serious
  /// introduced timeline issues before materializing and committing it.
  ReferenceAlignmentProposal apply({
    required Set<int> acceptedReferenceIndices,
    required Set<int> acceptedMissingReferenceIndices,
    required Set<int> overriddenAsrLineIndices,
    required bool applyReferenceTiming,
  }) {
    final result =
        ReferenceAlignmentApplier(minimumSimilarity: minimumSimilarity).apply(
          document: draft,
          alignment: alignment,
          applyReferenceTiming: applyReferenceTiming,
          acceptedReferenceIndices: acceptedReferenceIndices,
          acceptedMissingReferenceIndices: acceptedMissingReferenceIndices,
          protectedLineIndices: protectedLineIndices.difference(
            overriddenAsrLineIndices,
          ),
          audioDuration: audioDuration,
        );
    return ReferenceAlignmentProposal._(
      plan: this,
      result: result,
      applyReferenceTiming: applyReferenceTiming,
      acceptedReferenceCount: acceptedReferenceIndices.length,
      acceptedMissingReferenceCount: acceptedMissingReferenceIndices.length,
      overriddenManuallyEditedCount: overriddenAsrLineIndices.length,
    );
  }
}

/// An uncommitted result and the information needed for a later confirmed commit.
class ReferenceAlignmentProposal {
  final ReferenceAlignmentPlan plan;
  final ReferenceAlignmentApplyResult result;
  final bool applyReferenceTiming;
  final int acceptedReferenceCount;
  final int acceptedMissingReferenceCount;
  final int overriddenManuallyEditedCount;

  const ReferenceAlignmentProposal._({
    required this.plan,
    required this.result,
    required this.applyReferenceTiming,
    required this.acceptedReferenceCount,
    required this.acceptedMissingReferenceCount,
    required this.overriddenManuallyEditedCount,
  });

  /// Builds the document to commit only after any required user confirmation.
  /// No-op proposals are deliberately not given backup/provenance metadata.
  LyricDocument materialize({required DateTime appliedAt}) {
    if (!result.hasChanges) return plan.draft;
    final appliedDocument = applyReferenceTiming
        ? result.document.copyWith(globalOffset: Duration.zero)
        : result.document;
    final withIds = const LyricManualEditMarkerService().assignMissingLineIds(
      appliedDocument,
    );
    final backupMetadata = Map<String, dynamic>.from(plan.draft.metadata)
      ..remove(kReferenceAlignmentBackupKey);
    final backup = LyricDocument(
      language: plan.draft.language,
      lines: plan.draft.lines,
      globalOffset: plan.draft.globalOffset,
      metadata: backupMetadata,
    );
    final metadata = Map<String, dynamic>.from(plan.draft.metadata)
      ..[kReferenceAlignmentBackupKey] = <String, dynamic>{
        'createdAt': appliedAt.toIso8601String(),
        'reason': 'reference-alignment',
        'source': plan.input.sourcePath == null ? 'paste' : 'file',
        if (plan.input.sourcePath != null) 'sourcePath': plan.input.sourcePath,
        'format': plan.input.format,
        'timed': plan.input.timed,
        'referenceOffsetMs': plan.input.offset.inMilliseconds,
        'lineCount': plan.draft.lines.length,
        'document': backup.toJson(),
      }
      ..[ReferenceAlignmentProvenanceBuilder.metadataKey] =
          const ReferenceAlignmentProvenanceBuilder().build(
            appliedAt: appliedAt,
            input: plan.input,
            minimumSimilarity: plan.minimumSimilarity,
            applyReferenceTiming: applyReferenceTiming,
            acceptedReferenceCount: acceptedReferenceCount,
            acceptedMissingReferenceCount: acceptedMissingReferenceCount,
            overriddenManuallyEditedCount: overriddenManuallyEditedCount,
            result: result,
            appliedDocument: withIds,
          );
    return withIds.copyWith(metadata: metadata);
  }
}

/// Prepares and applies reference alignment without UI or persistence.
class ApplyReferenceAlignmentUseCase {
  const ApplyReferenceAlignmentUseCase();

  ReferenceAlignmentPlan prepare({
    required LyricDocument draft,
    required ReferenceLyricInput input,
    Set<int> protectedLineIndices = const {},
    Duration? audioDuration,
  }) {
    final alignment = const LyricAlignmentService().align(
      document: draft,
      referenceLines: input.lines,
    );
    ReferenceTimingUnavailableReason? reason;
    if (input.timed) {
      if (!alignment.entries.every((entry) => entry.referenceHasTimestamp)) {
        reason = ReferenceTimingUnavailableReason.partiallyTimed;
      } else if (alignment.missingReferenceIndices.isNotEmpty ||
          alignment.unmatchedAsrIndices.isNotEmpty ||
          alignment.asrLines.length != draft.lines.length) {
        reason = ReferenceTimingUnavailableReason.structuralMismatch;
      } else if (protectedLineIndices.isNotEmpty) {
        reason = ReferenceTimingUnavailableReason.protectedLines;
      }
    }
    return ReferenceAlignmentPlan._(
      draft: draft,
      input: input,
      alignment: alignment,
      protectedLineIndices: protectedLineIndices,
      audioDuration: audioDuration,
      minimumSimilarity: const ReferenceAlignmentApplier().minimumSimilarity,
      timingUnavailableReason: reason,
    );
  }
}
