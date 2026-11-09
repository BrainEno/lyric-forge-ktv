import 'dart:io';

import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/transcription_models.dart';
import 'asr_evidence_audio_verifier.dart';
import 'project_rerun_candidate_store.dart';
import 'project_transcription_input.dart';

enum RerunCandidateAudioStatus {
  matches,
  changed,
  selectionChanged,
  unavailable,
}

/// Only model configuration labels were saved; model files are not checked.
enum RerunCandidateModelStatus { unverified }

/// A point-in-time report, not authorization to apply a candidate. A model
/// reference is only a label; model contents and parameters are not verified.
class RerunCandidateAssessment {
  final SavedRerunCandidate saved;
  final int observedProjectRevision;
  final bool baselineMatches;
  final RerunCandidateAudioStatus audioStatus;
  RerunCandidateModelStatus get modelStatus =>
      RerunCandidateModelStatus.unverified;

  const RerunCandidateAssessment({
    required this.saved,
    required this.observedProjectRevision,
    required this.baselineMatches,
    required this.audioStatus,
  });
}

/// Re-reads the persisted record by ID, and fails rather than returning a
/// potentially mixed report when the project changes while audio is checked.
class ProjectRerunCandidateAssessor {
  final ProjectRepository _projects;
  final ProjectRerunCandidateStore _store;
  final Future<String> Function(String) _hashAudio;

  ProjectRerunCandidateAssessor({
    required ProjectRepository projects,
    Future<String> Function(String)? hashAudio,
  }) : _projects = projects,
       _store = ProjectRerunCandidateStore(projects),
       _hashAudio = hashAudio ?? hashAsrAudioFile;

  Future<RerunCandidateAssessment> assess({
    required String projectId,
    required String candidateId,
  }) async {
    final project = await _projects.getProjectById(projectId);
    if (project == null) {
      throw const TranscriptionException.input('工程不存在，无法检查候选版本');
    }
    SavedRerunCandidate? saved;
    for (final item in _store.read(project)) {
      if (item.id == candidateId) {
        saved = item;
        break;
      }
    }
    if (saved == null) {
      throw const TranscriptionException.input('候选版本不存在，无法检查');
    }
    final baselineMatches = ProjectRerunCandidateStore.matchesBaseline(
      project,
      saved.pair,
    );
    var audioStatus = RerunCandidateAudioStatus.unavailable;
    String? path;
    try {
      path = await resolveProjectTranscriptionInput(project);
    } on TranscriptionException catch (error) {
      if (error.kind != TranscriptionFailureKind.input) rethrow;
    }
    if (path != null) {
      if (path != saved.pair.inputAudioPath) {
        audioStatus = RerunCandidateAudioStatus.selectionChanged;
      } else {
        try {
          final digest = await _hashAudio(path);
          audioStatus = digest == saved.pair.inputAudioSha256
              ? RerunCandidateAudioStatus.matches
              : RerunCandidateAudioStatus.changed;
        } on AsrAudioChangedDuringHashException {
          audioStatus = RerunCandidateAudioStatus.changed;
        } on FileSystemException {
          audioStatus = RerunCandidateAudioStatus.unavailable;
        }
        // An alternate higher-priority stem might have appeared while reading.
        try {
          if (await resolveProjectTranscriptionInput(project) != path) {
            audioStatus = RerunCandidateAudioStatus.selectionChanged;
          }
        } on TranscriptionException catch (error) {
          if (error.kind != TranscriptionFailureKind.input) rethrow;
          audioStatus = RerunCandidateAudioStatus.unavailable;
        }
      }
    }
    final latest = await _projects.getProjectById(projectId);
    if (latest == null || latest.revision != project.revision) {
      throw const TranscriptionException.input('检查期间工程发生变化，请刷新后重试');
    }
    return RerunCandidateAssessment(
      saved: saved,
      observedProjectRevision: project.revision,
      baselineMatches: baselineMatches,
      audioStatus: audioStatus,
    );
  }
}
