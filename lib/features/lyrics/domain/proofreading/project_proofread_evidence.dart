import '../../../project/domain/models/lyric_document.dart';

/// Why persisted evidence could not safely be used for this draft.
enum ProjectProofreadEvidenceStatus {
  available,
  projectChanged,
  missingEvidence,
  invalidEvidence,
  unverifiedAudio,
  audioUnavailable,
  audioChanged,
  audioSelectionChanged,
  draftChanged,
  unsupportedOffsets,
}

/// A point-in-time assessment, not a guarantee of recognition accuracy.
class ProjectProofreadEvidenceResult {
  final ProjectProofreadEvidenceStatus status;
  final LyricDocument? secondary;
  final String? secondaryEngine;
  final DateTime? capturedAtUtc;

  const ProjectProofreadEvidenceResult.unavailable(this.status)
    : assert(status != ProjectProofreadEvidenceStatus.available),
      secondary = null,
      secondaryEngine = null,
      capturedAtUtc = null;

  const ProjectProofreadEvidenceResult.available({
    required LyricDocument this.secondary,
    required String this.secondaryEngine,
    required DateTime this.capturedAtUtc,
  }) : status = ProjectProofreadEvidenceStatus.available;
}

/// The caller owns editor revision checks and explicitly chooses whether to use
/// the result. Implementations must not mutate or persist the draft.
typedef ProjectProofreadEvidenceLoader = Future<ProjectProofreadEvidenceResult> Function({
  required String projectId,
  required int expectedProjectRevision,
  required LyricDocument draft,
});
