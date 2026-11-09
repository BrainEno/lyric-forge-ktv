import 'dart:convert';
import 'dart:io';

import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_service.dart';
import 'asr_evidence_audio_verifier.dart';
import 'project_transcription_input.dart';

enum IndependentRerunEngine { qwen, whisper }

/// An ephemeral pair for review, not a saved project version or an apply token.
/// Documents are decoded afresh so mutations by a caller do not alter snapshots.
class IndependentRerunCandidate {
  final String projectId;
  final int projectRevision;
  final IndependentRerunEngine engine;
  final String inputAudioPath;
  final String inputAudioSha256;

  /// Configuration identifiers only; they do not prove model file contents.
  final String modelReference;
  final String? alignerReference;
  final String requestedLanguage;
  final String detectedLanguage;
  final String _originalJson;
  final String _candidateJson;

  IndependentRerunCandidate({
    required this.projectId,
    required this.projectRevision,
    required this.engine,
    required this.inputAudioPath,
    required this.inputAudioSha256,
    required this.modelReference,
    required this.alignerReference,
    required this.requestedLanguage,
    required this.detectedLanguage,
    required LyricDocument original,
    required LyricDocument candidate,
  }) : _originalJson = jsonEncode(original.toJson()),
       _candidateJson = jsonEncode(candidate.toJson());

  LyricDocument get original =>
      LyricDocument.fromJson(jsonDecode(_originalJson) as Map<String, dynamic>);
  LyricDocument get candidate => LyricDocument.fromJson(
    jsonDecode(_candidateJson) as Map<String, dynamic>,
  );
}

/// Runs exactly one chosen engine, without writing the project or its lyrics.
/// Each factory must return a new exclusively owned adapter, never a shared one.
/// Configuration/runtime readiness is the caller's responsibility. This is a
/// whole-file run, not the chunked workflow; long-song completeness is unknown.
class IndependentProjectRerunService {
  final ProjectRepository _projects;
  final TranscriptionService Function() _createQwen;
  final TranscriptionService Function() _createWhisper;
  bool _running = false;
  bool _cancelled = false;
  TranscriptionService? _active;

  IndependentProjectRerunService({
    required ProjectRepository projects,
    required TranscriptionService Function() createQwen,
    required TranscriptionService Function() createWhisper,
  }) : _projects = projects,
       _createQwen = createQwen,
       _createWhisper = createWhisper;

  bool get isRunning => _running;

  Future<IndependentRerunCandidate> run({
    required String projectId,
    required IndependentRerunEngine engine,
    required TranscriptionConfig config,
  }) async {
    if (_running) throw const TranscriptionException.busy('已有独立识别任务正在运行');
    _running = true;
    _cancelled = false;
    Directory? work;
    TranscriptionService? adapter;
    try {
      final project = await _projects.getProjectById(projectId);
      _checkCancelled();
      if (project == null || project.lyricDocument == null) {
        throw const TranscriptionException.input('工程或原始歌词不存在');
      }
      // Snapshot before any more awaits; no automatic update to the project.
      final original = LyricDocument.fromJson(
        jsonDecode(jsonEncode(project.lyricDocument!.toJson()))
            as Map<String, dynamic>,
      );
      final path = await resolveProjectTranscriptionInput(project);
      _checkCancelled();
      final before = await _hash(path);
      _checkCancelled();
      work = await Directory.systemTemp.createTemp('lyricforge-asr-candidate-');
      _checkCancelled();
      adapter = switch (engine) {
        IndependentRerunEngine.qwen => _createQwen(),
        IndependentRerunEngine.whisper => _createWhisper(),
      };
      if (adapter.isRunning) {
        // Never dispose or cancel an adapter that was already in use.
        adapter = null;
        throw const TranscriptionException.busy('独立识别服务正在使用');
      }
      _active = adapter;
      final result = await adapter.transcribe(
        TranscriptionRequest(
          inputAudioPath: path,
          outputDirectory: work.path,
          config: config,
          context: [
            'Song title: ${project.name}',
            if (project.artist != null && project.artist!.trim().isNotEmpty)
              'Artist: ${project.artist!.trim()}',
            if (project.album != null && project.album!.trim().isNotEmpty)
              'Album: ${project.album!.trim()}',
          ].join('. '),
        ),
      );
      _checkCancelled();
      _active = null;
      if (result.lyrics.lines.isEmpty) {
        throw const TranscriptionException.input('独立识别没有返回歌词');
      }
      final after = await _hash(path);
      _checkCancelled();
      if (after != before)
        throw const TranscriptionException.input('识别期间音频发生变化，候选已丢弃');
      final latest = await _projects.getProjectById(projectId);
      _checkCancelled();
      if (latest == null ||
          latest.revision != project.revision ||
          await resolveProjectTranscriptionInput(latest) != path) {
        throw const TranscriptionException.input('识别期间工程或选用音轨发生变化，候选已丢弃');
      }
      _checkCancelled();
      final metadata = Map<String, dynamic>.from(result.lyrics.metadata)
        ..remove('rawJsonPath');
      return IndependentRerunCandidate(
        projectId: project.id,
        projectRevision: project.revision,
        engine: engine,
        inputAudioPath: path,
        inputAudioSha256: before,
        modelReference: engine == IndependentRerunEngine.qwen
            ? config.qwenModelPath
            : config.modelPath,
        alignerReference: engine == IndependentRerunEngine.qwen
            ? config.qwenAlignerModelPath
            : null,
        requestedLanguage: config.language,
        detectedLanguage: result.detectedLanguage,
        original: original,
        candidate: result.lyrics.copyWith(metadata: metadata),
      );
    } finally {
      _active = null;
      try {
        if (adapter != null) await adapter.dispose();
      } finally {
        try {
          if (work != null) await work.delete(recursive: true);
          _checkCancelled();
        } finally {
          _running = false;
          _cancelled = false;
        }
      }
    }
  }

  Future<void> cancel() async {
    if (!_running) return;
    _cancelled = true;
    final active = _active;
    if (active != null) await active.cancel();
  }

  void _checkCancelled() {
    if (_cancelled) throw const TranscriptionException.cancelled('独立识别已取消');
  }

  Future<String> _hash(String path) async {
    try {
      return await hashAsrAudioFile(path, onChunk: _checkCancelled);
    } on FileSystemException {
      throw const TranscriptionException.input('无法读取识别音频，候选已丢弃');
    } on AsrAudioChangedDuringHashException {
      throw const TranscriptionException.input('识别期间音频发生变化，候选已丢弃');
    }
  }
}
