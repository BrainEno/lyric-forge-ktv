/// Point-in-time evidence for the specific file sent to the aligner.
/// It is not a file lock, model verification, or authorization to overwrite.
class ReferenceAlignmentAudioSnapshot {
  final String projectId;
  final int projectRevision;
  final String audioPath;
  final String audioSha256;

  const ReferenceAlignmentAudioSnapshot({
    required this.projectId,
    required this.projectRevision,
    required this.audioPath,
    required this.audioSha256,
  });
}

enum ReferenceAlignmentAudioStatus {
  matches,
  projectChanged,
  audioSelectionChanged,
  audioChanged,
  audioUnavailable,
}

class ReferenceAlignmentAudioCheck {
  final ReferenceAlignmentAudioStatus status;
  final ReferenceAlignmentAudioSnapshot? snapshot;

  const ReferenceAlignmentAudioCheck({required this.status, this.snapshot});
}

/// Capture before alignment, then verify after alignment and before applying.
abstract class ReferenceAlignmentAudioGuard {
  Future<ReferenceAlignmentAudioCheck> capture({
    required String projectId,
    required int projectRevision,
    required String audioPath,
  });

  Future<ReferenceAlignmentAudioCheck> verify(ReferenceAlignmentAudioSnapshot snapshot);
}
