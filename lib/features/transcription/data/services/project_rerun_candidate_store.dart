import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/transcription_models.dart';
import 'asr_evidence_audio_verifier.dart';
import 'independent_project_rerun_service.dart';
import 'project_transcription_input.dart';

/// A saved pair is a review artifact, not permission to replace project lyrics.
class SavedRerunCandidate {
  final String id;
  final DateTime savedAtUtc;
  final IndependentRerunCandidate pair;

  const SavedRerunCandidate({
    required this.id,
    required this.savedAtUtc,
    required this.pair,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'savedAtUtc': savedAtUtc.toIso8601String(),
    'projectId': pair.projectId,
    'projectRevision': pair.projectRevision,
    'engine': pair.engine.name,
    'inputAudioPath': pair.inputAudioPath,
    'inputAudioSha256': pair.inputAudioSha256,
    'modelReference': pair.modelReference,
    'alignerReference': pair.alignerReference,
    'requestedLanguage': pair.requestedLanguage,
    'detectedLanguage': pair.detectedLanguage,
    'original': pair.original.toJson(),
    'candidate': pair.candidate.toJson(),
  };

  static SavedRerunCandidate? tryParse(Object? raw) {
    if (raw is! Map ||
        raw['id'] is! String ||
        (raw['id'] as String).trim().isEmpty ||
        raw['savedAtUtc'] is! String ||
        raw['projectId'] is! String ||
        (raw['projectId'] as String).trim().isEmpty ||
        raw['projectRevision'] is! int ||
        (raw['projectRevision'] as int) < 0 ||
        raw['engine'] is! String ||
        !IndependentRerunEngine.values.asNameMap().containsKey(raw['engine']) ||
        raw['inputAudioPath'] is! String ||
        (raw['inputAudioPath'] as String).trim().isEmpty ||
        raw['inputAudioSha256'] is! String ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(raw['inputAudioSha256'] as String) ||
        raw['modelReference'] is! String ||
        (raw['modelReference'] as String).trim().isEmpty ||
        (raw['alignerReference'] != null &&
            raw['alignerReference'] is! String) ||
        raw['requestedLanguage'] is! String ||
        raw['detectedLanguage'] is! String)
      return null;
    final savedAt = DateTime.tryParse(raw['savedAtUtc'] as String);
    if (savedAt == null || !savedAt.isUtc) return null;
    try {
      final original = _parseDocument(raw['original']);
      final candidate = _parseDocument(raw['candidate']);
      if (original == null || candidate == null || candidate.lines.isEmpty)
        return null;
      return SavedRerunCandidate(
        id: raw['id'] as String,
        savedAtUtc: savedAt,
        pair: IndependentRerunCandidate(
          projectId: raw['projectId'] as String,
          projectRevision: raw['projectRevision'] as int,
          engine: IndependentRerunEngine.values.asNameMap()[raw['engine']]!,
          inputAudioPath: raw['inputAudioPath'] as String,
          inputAudioSha256: raw['inputAudioSha256'] as String,
          modelReference: raw['modelReference'] as String,
          alignerReference: raw['alignerReference'] as String?,
          requestedLanguage: raw['requestedLanguage'] as String,
          detectedLanguage: raw['detectedLanguage'] as String,
          original: original,
          candidate: candidate,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static LyricDocument? _parseDocument(Object? value) {
    if (value is! Map ||
        value['language'] is! String ||
        value['lines'] is! List ||
        (value['globalOffset'] != null && value['globalOffset'] is! int) ||
        value['metadata'] is! Map)
      return null;
    for (final line in value['lines'] as List) {
      if (line is! Map ||
          line['text'] is! String ||
          line['startTime'] is! int ||
          line['endTime'] is! int ||
          line['isChorus'] is! bool ||
          line['confidence'] is! int ||
          line['confidenceSource'] is! String ||
          !LyricConfidenceSource.values.asNameMap().containsKey(
            line['confidenceSource'],
          ) ||
          (line['id'] != null && line['id'] is! String))
        return null;
    }
    // Round-trip validates JSON-compatible metadata and all lyric line fields.
    final json = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
    return LyricDocument.fromJson(json);
  }
}

/// Stores a bounded list in the existing project manifest. Invalid or unknown
/// metadata fails closed; no item is ever silently replaced or evicted.
class ProjectRerunCandidateStore {
  static const metadataKey = 'independentRerunCandidates';
  static const schemaVersion = 1;
  static const maxCandidates = 5;
  static const maxRecordBytes = 512 * 1024;

  final ProjectRepository _projects;
  ProjectRerunCandidateStore(this._projects);

  /// An absent store is empty; corrupt/unknown data is an error, not empty.
  List<SavedRerunCandidate> read(ProjectManifest project) {
    if (!project.metadata.containsKey(metadataKey)) return const [];
    final raw = project.metadata[metadataKey];
    if (raw is! Map ||
        raw['schemaVersion'] != schemaVersion ||
        raw['items'] is! List) {
      throw const FormatException(
        'Invalid or unsupported rerun candidate store',
      );
    }
    final items = raw['items'] as List;
    if (items.length > maxCandidates)
      throw const FormatException('Too many rerun candidates');
    final result = <SavedRerunCandidate>[];
    final ids = <String>{};
    for (final item in items) {
      final record = SavedRerunCandidate.tryParse(item);
      if (record == null ||
          record.pair.projectId != project.id ||
          !ids.add(record.id)) {
        throw const FormatException('Invalid rerun candidate');
      }
      result.add(record);
    }
    return List.unmodifiable(result);
  }

  /// Compares the complete stored baseline, including manual-edit metadata.
  /// Revision alone is insufficient because saving the pair increments it.
  static bool matchesBaseline(ProjectManifest project, IndependentRerunCandidate pair) =>
      project.lyricDocument != null &&
      _sameJson(project.lyricDocument!.toJson(), pair.original.toJson());

  Future<SavedRerunCandidate> save(IndependentRerunCandidate pair) async {
    final project = await _projects.getProjectById(pair.projectId);
    if (project == null ||
        project.revision != pair.projectRevision ||
        !matchesBaseline(project, pair)) {
      throw const TranscriptionException.input('工程或原始歌词已变化，候选未保存');
    }
    final previous = read(project);
    if (previous.length >= maxCandidates) {
      throw const TranscriptionException.input('候选版本已达到上限，未覆盖任何版本');
    }
    final selectedPath = await resolveProjectTranscriptionInput(project);
    if (selectedPath != pair.inputAudioPath) {
      throw const TranscriptionException.input('工程选用音轨已变化，候选未保存');
    }
    try {
      if (await hashAsrAudioFile(selectedPath) != pair.inputAudioSha256) {
        throw const TranscriptionException.input('工程音频已变化，候选未保存');
      }
    } on FileSystemException {
      throw const TranscriptionException.input('工程音频无法读取，候选未保存');
    } on AsrAudioChangedDuringHashException {
      throw const TranscriptionException.input('工程音频正在变化，候选未保存');
    }
    if (await resolveProjectTranscriptionInput(project) != selectedPath) {
      throw const TranscriptionException.input('工程选用音轨已变化，候选未保存');
    }
    final record = SavedRerunCandidate(
      id: const Uuid().v4(),
      savedAtUtc: DateTime.now().toUtc(),
      pair: pair,
    );
    final encoded = jsonEncode(record.toJson());
    if (utf8.encode(encoded).length > maxRecordBytes) {
      throw const TranscriptionException.input('候选版本过大，未保存');
    }
    if (SavedRerunCandidate.tryParse(jsonDecode(encoded)) == null) {
      throw const TranscriptionException.input('候选版本格式无效，未保存');
    }
    // Keep original raw records, including unknown fields, rather than rewriting
    // them through an older decoder. CAS rejects concurrent project changes.
    final raw = project.metadata[metadataKey];
    final container = raw == null
        ? <String, dynamic>{'schemaVersion': schemaVersion}
        : Map<String, dynamic>.from(raw as Map);
    final existing = raw == null
        ? <dynamic>[]
        : List<dynamic>.of((raw as Map)['items'] as List);
    container['items'] = [...existing, jsonDecode(encoded)];
    final metadata = Map<String, dynamic>.from(project.metadata)
      ..[metadataKey] = container;
    try {
      await _projects.updateProjectIfUnchanged(
        project.copyWith(metadata: metadata),
        expectedRevision: pair.projectRevision,
      );
    } on ProjectUpdateConflictException {
      throw const TranscriptionException.input('保存期间工程已变化，候选未保存');
    }
    return record;
  }
}

bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    return a.keys.every(
      (key) => b.containsKey(key) && _sameJson(a[key], b[key]),
    );
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
