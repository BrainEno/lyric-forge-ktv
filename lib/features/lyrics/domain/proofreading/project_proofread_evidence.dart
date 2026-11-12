import '../../../project/domain/models/lyric_document.dart';

/// Why persisted evidence could not safely be used for this draft.
enum ProjectProofreadEvidenceStatus {
  available,

  /// The original pair is verified but cannot be compared to this draft.
  auditOnly,
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
  final LyricDocument? primary;
  final String? primaryEngine;
  final LyricDocument? secondary;
  final String? secondaryEngine;
  final DateTime? capturedAtUtc;

  const ProjectProofreadEvidenceResult.unavailable(this.status)
    : assert(status != ProjectProofreadEvidenceStatus.available),
      assert(status != ProjectProofreadEvidenceStatus.auditOnly),
      primary = null,
      primaryEngine = null,
      secondary = null,
      secondaryEngine = null,
      capturedAtUtc = null;

  const ProjectProofreadEvidenceResult.available({
    required LyricDocument this.secondary,
    required String this.secondaryEngine,
    required DateTime this.capturedAtUtc,
  }) : primary = null,
       primaryEngine = null,
       status = ProjectProofreadEvidenceStatus.available;

  /// Originals only: neither transcript can be treated as the current draft.
  const ProjectProofreadEvidenceResult.auditOnly({
    required LyricDocument this.primary,
    required String this.primaryEngine,
    required LyricDocument this.secondary,
    required String this.secondaryEngine,
    required DateTime this.capturedAtUtc,
  }) : status = ProjectProofreadEvidenceStatus.auditOnly;
}

/// The caller owns editor revision checks and explicitly chooses whether to use
/// the result. Implementations must not mutate or persist the draft.
typedef ProjectProofreadEvidenceLoader =
    Future<ProjectProofreadEvidenceResult> Function({
      required String projectId,
      required int expectedProjectRevision,
      required LyricDocument draft,
    });
