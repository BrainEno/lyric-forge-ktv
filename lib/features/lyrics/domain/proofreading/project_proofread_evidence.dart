import '../../../project/domain/models/lyric_document.dart';

/// Why persisted evidence could not safely be used for this draft.
enum ProjectProofreadEvidenceStatus {
  available,

  /// The original pair is verified but cannot be compared to this draft.
  auditOnly,

  /// Complete original chunk pairs may be inspected but never applied.
  chunkAuditOnly,
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
  final List<ProjectProofreadChunk> chunks;

  const ProjectProofreadEvidenceResult.unavailable(this.status)
    : assert(status != ProjectProofreadEvidenceStatus.available),
      assert(status != ProjectProofreadEvidenceStatus.auditOnly),
      assert(status != ProjectProofreadEvidenceStatus.chunkAuditOnly),
      primary = null,
      primaryEngine = null,
      secondary = null,
      secondaryEngine = null,
      capturedAtUtc = null,
      chunks = const [];

  const ProjectProofreadEvidenceResult.available({
    required LyricDocument this.secondary,
    required String this.secondaryEngine,
    required DateTime this.capturedAtUtc,
  }) : primary = null,
       primaryEngine = null,
       chunks = const [],
       status = ProjectProofreadEvidenceStatus.available;

  /// Originals only: neither transcript can be treated as the current draft.
  const ProjectProofreadEvidenceResult.auditOnly({
    required LyricDocument this.primary,
    required String this.primaryEngine,
    required LyricDocument this.secondary,
    required String this.secondaryEngine,
    required DateTime this.capturedAtUtc,
  }) : chunks = const [],
       status = ProjectProofreadEvidenceStatus.auditOnly;

  /// Chunk originals are never a second transcript for the editable draft.
  ProjectProofreadEvidenceResult.chunkAudit(List<ProjectProofreadChunk> chunks)
    : assert(chunks.isNotEmpty),
      chunks = List.unmodifiable(chunks),
      primary = null,
      primaryEngine = null,
      secondary = null,
      secondaryEngine = null,
      capturedAtUtc = null,
      status = ProjectProofreadEvidenceStatus.chunkAuditOnly;
}

/// One independently recognized chunk; transcript times are absolute in the
/// full source audio, while line indices belong only to their original engine.
/// Overlap segments are not deduplicated or mapped to editable lyric rows.
class ProjectProofreadChunk {
  final int index;
  final Duration start;
  final Duration end;
  final LyricDocument primary;
  final String primaryEngine;
  final LyricDocument secondary;
  final String secondaryEngine;
  final DateTime capturedAtUtc;

  const ProjectProofreadChunk({
    required this.index,
    required this.start,
    required this.end,
    required this.primary,
    required this.primaryEngine,
    required this.secondary,
    required this.secondaryEngine,
    required this.capturedAtUtc,
  });
}

/// The caller owns editor revision checks and explicitly chooses whether to use
/// the result. Implementations must not mutate or persist the draft.
typedef ProjectProofreadEvidenceLoader =
    Future<ProjectProofreadEvidenceResult> Function({
      required String projectId,
      required int expectedProjectRevision,
      required LyricDocument draft,
    });
