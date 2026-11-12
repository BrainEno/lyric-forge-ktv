import 'dart:io';

import '../../../lyrics/domain/proofreading/reference_alignment_audio_guard.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import 'asr_evidence_audio_verifier.dart';

/// Checks the same vocal-or-original selection used by V2's alignment runner.
/// Hashing and revision rechecks are observations, not locks or CAS writes.
class ProjectReferenceAlignmentAudioGuard
    implements ReferenceAlignmentAudioGuard {
  final ProjectRepository projects;
  final Future<String> Function(String) hashAudio;

  ProjectReferenceAlignmentAudioGuard({
    required this.projects,
    Future<String> Function(String)? hashAudio,
  }) : hashAudio = hashAudio ?? hashAsrAudioFile;

  @override
  Future<ReferenceAlignmentAudioCheck> capture({
    required String projectId,
    required int projectRevision,
    required String audioPath,
  }) async {
    final initial = await _checkProject(projectId, projectRevision, audioPath);
    if (initial != ReferenceAlignmentAudioStatus.matches)
      return ReferenceAlignmentAudioCheck(status: initial);
    String hash;
    try {
      hash = await hashAudio(audioPath);
    } on AsrAudioChangedDuringHashException {
      return const ReferenceAlignmentAudioCheck(
        status: ReferenceAlignmentAudioStatus.audioChanged,
      );
    } on FileSystemException {
      return const ReferenceAlignmentAudioCheck(
        status: ReferenceAlignmentAudioStatus.audioUnavailable,
      );
    }
    final after = await _checkProject(projectId, projectRevision, audioPath);
    if (after != ReferenceAlignmentAudioStatus.matches)
      return ReferenceAlignmentAudioCheck(status: after);
    return ReferenceAlignmentAudioCheck(
      status: ReferenceAlignmentAudioStatus.matches,
      snapshot: ReferenceAlignmentAudioSnapshot(
        projectId: projectId,
        projectRevision: projectRevision,
        audioPath: audioPath,
        audioSha256: hash,
      ),
    );
  }

  @override
  Future<ReferenceAlignmentAudioCheck> verify(
    ReferenceAlignmentAudioSnapshot snapshot,
  ) async {
    final result = await capture(
      projectId: snapshot.projectId,
      projectRevision: snapshot.projectRevision,
      audioPath: snapshot.audioPath,
    );
    if (result.status != ReferenceAlignmentAudioStatus.matches) return result;
    if (result.snapshot!.audioSha256 != snapshot.audioSha256) {
      return const ReferenceAlignmentAudioCheck(
        status: ReferenceAlignmentAudioStatus.audioChanged,
      );
    }
    return ReferenceAlignmentAudioCheck(
      status: ReferenceAlignmentAudioStatus.matches,
      snapshot: snapshot,
    );
  }

  Future<ReferenceAlignmentAudioStatus> _checkProject(
    String id,
    int revision,
    String audioPath,
  ) async {
    final project = await projects.getProjectById(id);
    if (project == null || project.revision != revision)
      return ReferenceAlignmentAudioStatus.projectChanged;
    final selected = _alignmentPath(project);
    if (selected == null || selected.trim().isEmpty)
      return ReferenceAlignmentAudioStatus.audioUnavailable;
    if (selected != audioPath)
      return ReferenceAlignmentAudioStatus.audioSelectionChanged;
    return ReferenceAlignmentAudioStatus.matches;
  }

  String? _alignmentPath(ProjectManifest project) {
    final audio = project.audioAsset;
    return audio == null ? null : (audio.vocalPath ?? audio.originalPath);
  }
}
