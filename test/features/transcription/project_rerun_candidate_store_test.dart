import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/independent_project_rerun_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_rerun_candidate_store.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

const manual = LyricDocument(language: 'en', lines: [LyricLine(id: 'manual', text: 'human edit', startTime: Duration.zero, endTime: Duration(seconds: 1))], metadata: {'manuallyEditedLineIds': ['manual']});
const draft = LyricDocument(language: 'en', lines: [LyricLine(text: 'second version', startTime: Duration.zero, endTime: Duration(seconds: 1))]);

void main() {
  late Directory root;
  late File audio;
  late FileProjectRepository repository;
  late ProjectManifest project;
  late ProjectRerunCandidateStore store;

  IndependentRerunCandidate pair(ProjectManifest p, {LyricDocument candidate = draft}) => IndependentRerunCandidate(
    projectId: p.id, projectRevision: p.revision, engine: IndependentRerunEngine.whisper,
    inputAudioPath: audio.path, inputAudioSha256: sha256.convert([1, 2, 3]).toString(),
    modelReference: 'model', alignerReference: null, requestedLanguage: 'auto', detectedLanguage: 'en',
    original: manual, candidate: candidate,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rerun-store-test-');
    audio = File('${root.path}/song.wav');
    await audio.writeAsBytes([1, 2, 3]);
    repository = FileProjectRepository(rootDirectory: root);
    final created = await repository.createProject(name: 'Song');
    project = await repository.updateProject(created.copyWith(audioAsset: AudioAsset(originalPath: audio.path, format: 'wav'), lyricDocument: manual, metadata: {'other': 'kept'}));
    store = ProjectRerunCandidateStore(repository);
  });
  tearDown(() async => root.delete(recursive: true));

  test('pair survives a repository restart without changing manual lyrics', () async {
    final saved = await store.save(pair(project));
    final reloaded = await FileProjectRepository(rootDirectory: root).getProjectById(project.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.revision, project.revision + 1);
    expect(reloaded.lyricDocument!.toJson(), manual.toJson());
    expect(reloaded.metadata['other'], 'kept');
    final records = store.read(reloaded);
    expect(records, hasLength(1));
    expect(records.single.id, saved.id);
    expect(records.single.pair.projectRevision, project.revision);
    expect(records.single.pair.original.toJson(), manual.toJson());
    expect(records.single.pair.candidate.toJson(), draft.toJson());
    records.single.pair.candidate.lines.clear();
    expect(store.read(reloaded).single.pair.candidate.lines.single.text, 'second version');
  });

  test('stale revision or changed original cannot save', () async {
    final changed = await repository.updateProject(project.copyWith(lyricDocument: draft));
    await expectLater(store.save(pair(project)), throwsA(isA<TranscriptionException>()));
    await expectLater(store.save(pair(changed)), throwsA(isA<TranscriptionException>()));
    final latest = await repository.getProjectById(project.id);
    expect(latest!.lyricDocument!.toJson(), draft.toJson());
    expect(store.read(latest), isEmpty);
  });

  test('changed bytes and changed chosen track cannot save', () async {
    await audio.writeAsBytes([3, 2, 1]);
    await expectLater(store.save(pair(project)), throwsA(isA<TranscriptionException>()));
    await audio.writeAsBytes([1, 2, 3]);
    final vocal = File('${root.path}/vocal.wav');
    final withVocal = await repository.updateProject(project.copyWith(audioAsset: project.audioAsset!.copyWith(vocalPath: vocal.path)));
    final candidate = pair(withVocal);
    await vocal.writeAsBytes([1, 2, 3]);
    await expectLater(store.save(candidate), throwsA(isA<TranscriptionException>()));
    expect(store.read((await repository.getProjectById(project.id))!), isEmpty);
  });

  test('a writer winning the CAS cannot have their edits overwritten', () async {
    final racing = _RaceRepository(repository);
    final racingStore = ProjectRerunCandidateStore(racing);
    await expectLater(racingStore.save(pair(project)), throwsA(isA<TranscriptionException>()));
    final latest = await repository.getProjectById(project.id);
    expect(latest!.lyricDocument!.toJson(), draft.toJson());
    expect(store.read(latest), isEmpty);
  });

  test('unknown and malformed stores fail closed and stay untouched', () async {
    for (final bad in [
      {'schemaVersion': 99, 'items': []},
      {'schemaVersion': 1, 'items': [{'id': 'broken'}]},
      null,
    ]) {
      final changed = await repository.updateProject((await repository.getProjectById(project.id))!.copyWith(metadata: {'other': 'kept', ProjectRerunCandidateStore.metadataKey: bad}));
      expect(() => store.read(changed), throwsFormatException);
      await expectLater(store.save(pair(changed)), throwsFormatException);
      final latest = (await repository.getProjectById(project.id))!;
      expect(latest.revision, changed.revision);
      expect(latest.metadata[ProjectRerunCandidateStore.metadataKey], bad);
    }
  });

  test('preserves unknown fields in container and existing records', () async {
    await store.save(pair(project));
    final first = (await repository.getProjectById(project.id))!;
    final container = Map<String, dynamic>.from(first.metadata[ProjectRerunCandidateStore.metadataKey] as Map);
    final items = List<dynamic>.of(container['items'] as List);
    items[0] = {...items[0] as Map<String, dynamic>, 'futureRecordField': {'keep': true}};
    container['items'] = items;
    container['futureContainerField'] = 'keep';
    final updated = await repository.updateProject(first.copyWith(metadata: {...first.metadata, ProjectRerunCandidateStore.metadataKey: container}));
    await store.save(pair(updated));
    final latest = (await repository.getProjectById(project.id))!;
    final saved = latest.metadata[ProjectRerunCandidateStore.metadataKey] as Map;
    expect(saved['futureContainerField'], 'keep');
    expect((saved['items'] as List).first['futureRecordField'], {'keep': true});
    expect(store.read(latest), hasLength(2));
  });

  test('version and size limits fail without evicting previous candidates', () async {
    var current = project;
    for (var i = 0; i < ProjectRerunCandidateStore.maxCandidates; i++) {
      await store.save(pair(current));
      current = (await repository.getProjectById(project.id))!;
    }
    final before = current.metadata[ProjectRerunCandidateStore.metadataKey];
    await expectLater(store.save(pair(current)), throwsA(isA<TranscriptionException>()));
    expect((await repository.getProjectById(project.id))!.metadata[ProjectRerunCandidateStore.metadataKey], before);
    expect(store.read(current), hasLength(ProjectRerunCandidateStore.maxCandidates));

    final empty = await repository.updateProject(current.copyWith(metadata: {'other': 'kept'}));
    final huge = LyricDocument(language: 'en', lines: [LyricLine(text: 'x' * (ProjectRerunCandidateStore.maxRecordBytes + 1), startTime: Duration.zero, endTime: const Duration(seconds: 1))]);
    await expectLater(store.save(pair(empty, candidate: huge)), throwsA(isA<TranscriptionException>()));
    expect(store.read((await repository.getProjectById(project.id))!), isEmpty);
  });
}

class _RaceRepository implements ProjectRepository {
  final ProjectRepository delegate;
  _RaceRepository(this.delegate);
  @override
  Future<ProjectManifest?> getProjectById(String id) => delegate.getProjectById(id);
  @override
  Future<ProjectManifest> updateProjectIfUnchanged(ProjectManifest project, {required int expectedRevision}) async {
    final latest = (await delegate.getProjectById(project.id))!;
    await delegate.updateProject(latest.copyWith(lyricDocument: draft));
    return delegate.updateProjectIfUnchanged(project, expectedRevision: expectedRevision);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
