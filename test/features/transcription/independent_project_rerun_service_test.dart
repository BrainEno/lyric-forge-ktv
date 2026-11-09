import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/independent_project_rerun_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

const config = TranscriptionConfig(whisperExecutable: 'whisper', modelPath: 'model');
const manual = LyricDocument(language: 'en', lines: [LyricLine(id: 'manual', text: 'human edit', startTime: Duration.zero, endTime: Duration(seconds: 2))], metadata: {'manual': ['manual']});
const draft = LyricDocument(language: 'en', lines: [LyricLine(text: 'new interpretation', startTime: Duration.zero, endTime: Duration(seconds: 2))], metadata: {'rawJsonPath': 'temporary', 'generatedBy': 'test'});

void main() {
  late Directory root;
  late File original;
  late File vocal;
  late _Repository repository;
  late _Engine qwen;
  late _Engine whisper;
  late IndependentProjectRerunService runner;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rerun-test-');
    original = File('${root.path}/song.wav');
    vocal = File('${root.path}/vocal.wav');
    await original.writeAsBytes([1, 2, 3]);
    await vocal.writeAsBytes([4, 5, 6]);
    final now = DateTime.utc(2026);
    repository = _Repository(ProjectManifest(id: 'p', name: 'Song', createdAt: now, updatedAt: now, revision: 7, audioAsset: AudioAsset(originalPath: original.path, vocalPath: vocal.path, format: 'wav'), lyricDocument: manual, projectDirectory: root.path));
    qwen = _Engine();
    whisper = _Engine();
    runner = IndependentProjectRerunService(projects: repository, createQwen: () => qwen, createWhisper: () => whisper);
  });
  tearDown(() => root.delete(recursive: true));

  test('each selection really runs one engine in isolated storage without project writes', () async {
    for (final engine in IndependentRerunEngine.values) {
      final chosen = engine == IndependentRerunEngine.qwen ? qwen : whisper;
      final pair = await runner.run(projectId: 'p', engine: engine, config: config);
      expect(pair.engine, engine);
      expect(pair.projectRevision, 7);
      expect(pair.inputAudioPath, vocal.path);
      expect(pair.inputAudioSha256, sha256.convert([4, 5, 6]).toString());
      expect(pair.original.lines.single.text, 'human edit');
      expect(pair.candidate.lines.single.text, 'new interpretation');
      expect(pair.candidate.metadata, isNot(contains('rawJsonPath')));
      pair.original.lines.clear();
      expect(pair.original.lines.single.text, 'human edit');
      expect(chosen.requests.single.normalizedInputAudioPath, isNull);
      expect(chosen.requests.single.inputAudioPath, vocal.path);
      expect(await Directory(chosen.requests.single.outputDirectory).exists(), isFalse);
      expect(chosen.disposed, isTrue);
    }
    expect(qwen.requests.length, 1);
    expect(whisper.requests.length, 1);
    expect(repository.writes, 0);
    expect(repository.project.lyricDocument!.toJson(), manual.toJson());
    expect(await root.list().length, 2);
  });

  test('concurrent project edit invalidates candidate without touching edited lyrics', () async {
    qwen.callback = (_) async {
      repository.project = repository.project.copyWith(revision: 8, lyricDocument: draft);
    };
    await expectLater(runner.run(projectId: 'p', engine: IndependentRerunEngine.qwen, config: config), throwsA(isA<TranscriptionException>().having((e) => e.kind, 'kind', TranscriptionFailureKind.input)));
    expect(repository.project.lyricDocument!.toJson(), draft.toJson());
    expect(repository.writes, 0);
    expect(await Directory(qwen.requests.single.outputDirectory).exists(), isFalse);
  });

  test('audio mutation and preferred-input changes invalidate candidate', () async {
    qwen.callback = (_) async { await vocal.writeAsBytes([9, 9, 9]); };
    await expectLater(runner.run(projectId: 'p', engine: IndependentRerunEngine.qwen, config: config), throwsA(isA<TranscriptionException>()));
    await vocal.writeAsBytes([4, 5, 6]);
    qwen.callback = (_) async { await vocal.delete(); };
    await expectLater(runner.run(projectId: 'p', engine: IndependentRerunEngine.qwen, config: config), throwsA(isA<TranscriptionException>()));
    expect(repository.writes, 0);
  });

  test('new higher priority input invalidates candidate even if old file remains', () async {
    await vocal.delete();
    qwen.callback = (_) async { await vocal.writeAsBytes([4, 5, 6]); };
    await expectLater(runner.run(projectId: 'p', engine: IndependentRerunEngine.qwen, config: config), throwsA(isA<TranscriptionException>()));
    expect(qwen.requests.single.inputAudioPath, original.path);
  });

  test('cancellation and overlapping calls do not return or save results', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    qwen.callback = (_) async { started.complete(); await release.future; };
    final running = runner.run(projectId: 'p', engine: IndependentRerunEngine.qwen, config: config);
    final assertion = expectLater(running, throwsA(isA<TranscriptionException>().having((e) => e.kind, 'kind', TranscriptionFailureKind.cancelled)));
    await started.future;
    await expectLater(runner.run(projectId: 'p', engine: IndependentRerunEngine.whisper, config: config), throwsA(isA<TranscriptionException>().having((e) => e.kind, 'kind', TranscriptionFailureKind.busy)));
    await runner.cancel();
    expect(qwen.cancelled, isTrue);
    release.complete();
    await assertion;
    expect(repository.writes, 0);
    expect(whisper.requests, isEmpty);
    expect(await Directory(qwen.requests.single.outputDirectory).exists(), isFalse);
    expect(runner.isRunning, isFalse);
  });

  test('failure cleans the isolated workspace without saving', () async {
    qwen.callback = (_) async { throw const TranscriptionException.environment('failed'); };
    await expectLater(runner.run(projectId: 'p', engine: IndependentRerunEngine.qwen, config: config), throwsA(isA<TranscriptionException>().having((e) => e.kind, 'kind', TranscriptionFailureKind.environment)));
    expect(await Directory(qwen.requests.single.outputDirectory).exists(), isFalse);
    expect(qwen.disposed, isTrue);
    expect(repository.writes, 0);
    expect(repository.project.lyricDocument!.toJson(), manual.toJson());
  });

  test('a busy preexisting adapter is not cancelled or disposed', () async {
    qwen.busy = true;
    await expectLater(runner.run(projectId: 'p', engine: IndependentRerunEngine.qwen, config: config), throwsA(isA<TranscriptionException>().having((e) => e.kind, 'kind', TranscriptionFailureKind.busy)));
    expect(qwen.cancelled, isFalse);
    expect(qwen.disposed, isFalse);
    expect(qwen.requests, isEmpty);
  });
}

class _Repository implements ProjectRepository {
  ProjectManifest project;
  int writes = 0;
  _Repository(this.project);
  @override
  Future<ProjectManifest?> getProjectById(String id) async => id == project.id ? project : null;
  @override
  Future<ProjectManifest> updateProject(ProjectManifest project) async { writes++; throw StateError('unexpected write'); }
  @override
  Future<ProjectManifest> updateProjectIfUnchanged(ProjectManifest project, {required int expectedRevision}) async { writes++; throw StateError('unexpected write'); }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements TranscriptionService {
  final requests = <TranscriptionRequest>[];
  Future<void> Function(TranscriptionRequest)? callback;
  bool cancelled = false;
  bool disposed = false;
  bool busy = false;
  @override
  bool get isRunning => busy;
  @override
  Stream<TranscriptionProgress> get progressStream => const Stream.empty();
  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    requests.add(request);
    await File('${request.outputDirectory}/raw.json').writeAsString('temporary');
    if (callback != null) await callback!(request);
    return const TranscriptionResult(lyrics: draft, normalizedAudioPath: 'unused', rawJsonPath: 'unused', detectedLanguage: 'en');
  }
  @override
  Future<void> cancel() async { cancelled = true; }
  @override
  Future<void> dispose() async { disposed = true; }
}
