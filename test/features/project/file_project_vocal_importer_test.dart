import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_backing_mode.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/data/services/file_project_accompaniment_importer.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

void main() {
  late Directory root;
  late Directory managed;
  late File source;
  late FileProjectRepository repository;
  late ProjectManifest project;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vocal-import-');
    managed = Directory('${root.path}${Platform.pathSeparator}managed');
    source = File('${root.path}${Platform.pathSeparator}人声 sample.WAV');
    await source.writeAsBytes([2, 3, 4]);
    repository = FileProjectRepository(rootDirectory: root);
    final created = await repository.createProject(name: 'Song');
    project = await repository.updateProject(created.copyWith(
      audioAsset: const AudioAsset(originalPath: '/song.wav', instrumentalPath: '/backing.wav', format: 'wav'),
      lyricDocument: const LyricDocument(language: 'zh', lines: [
        LyricLine(text: '保留歌词', startTime: Duration.zero, endTime: Duration(seconds: 1)),
      ]),
    ));
  });

  tearDown(() async => root.delete(recursive: true));

  FileProjectAccompanimentImporter importer(Future<String?> Function() pick, {ProjectRepository? projects}) =>
      FileProjectAccompanimentImporter(projectRepository: projects ?? repository, storageDirectory: managed, pickPath: pick);

  test('copies vocal to managed storage, persists it and keeps other project data', () async {
    final updated = (await importer(() async => source.path).importVocalFor(project))!;
    final copied = File(updated.audioAsset!.vocalPath!);
    expect(copied.path, isNot(source.path));
    expect(copied.path, endsWith('.wav'));
    expect(await copied.readAsBytes(), [2, 3, 4]);
    expect(await source.readAsBytes(), [2, 3, 4]);
    expect(updated.audioAsset!.instrumentalPath, '/backing.wav');
    expect(updated.audioAsset!.originalPath, '/song.wav');
    expect(updated.lyricDocument!.lines.single.text, '保留歌词');
    expect(updated.revision, greaterThan(project.revision));
    expect(availableKtvBackingModes(updated.audioAsset), contains(KtvBackingMode.instrumental));
    final reopened = FileProjectRepository(rootDirectory: root);
    expect((await reopened.getProjectById(project.id))!.audioAsset!.vocalPath, copied.path);
  });

  test('replacing a vocal preserves original selection and old managed copy', () async {
    final first = (await importer(() async => source.path).importVocalFor(project))!;
    final old = File(first.audioAsset!.vocalPath!);
    final replacement = File('${root.path}${Platform.pathSeparator}new.mp3');
    await replacement.writeAsBytes([9, 8]);
    final second = (await importer(() async => replacement.path).importVocalFor(first))!;
    expect(second.audioAsset!.vocalPath, isNot(old.path));
    expect(await old.readAsBytes(), [2, 3, 4]);
    expect(await File(second.audioAsset!.vocalPath!).readAsBytes(), [9, 8]);
    expect(await replacement.readAsBytes(), [9, 8]);
    expect(second.audioAsset!.instrumentalPath, first.audioAsset!.instrumentalPath);
  });

  test('cancel does not create storage or mutate project', () async {
    expect(await importer(() async => null).importVocalFor(project), isNull);
    expect(await managed.exists(), isFalse);
    expect((await repository.getProjectById(project.id))!.revision, project.revision);
  });

  test('rejects unsupported, missing and empty files without saving', () async {
    final unsupported = File('${root.path}/file.txt');
    await unsupported.writeAsString('not audio');
    final empty = File('${root.path}/empty.wav');
    await empty.writeAsBytes([]);
    await expectLater(importer(() async => unsupported.path).importVocalFor(project), throwsFormatException);
    await expectLater(importer(() async => '${root.path}/missing.wav').importVocalFor(project), throwsA(isA<FileSystemException>()));
    await expectLater(importer(() async => empty.path).importVocalFor(project), throwsA(isA<FileSystemException>()));
    expect(await managed.exists(), isFalse);
    expect((await repository.getProjectById(project.id))!.revision, project.revision);
  });

  test('stale import does not overwrite concurrently changed lyrics or track', () async {
    final current = await repository.updateProject(project.copyWith(name: 'new title', audioAsset: project.audioAsset!.copyWith(vocalPath: '/other/vocal.wav')));
    await expectLater(importer(() async => source.path).importVocalFor(project), throwsA(isA<ProjectUpdateConflictException>()));
    final saved = (await repository.getProjectById(project.id))!;
    expect(saved.revision, current.revision);
    expect(saved.name, 'new title');
    expect(saved.audioAsset!.vocalPath, '/other/vocal.wav');
    expect(saved.lyricDocument!.lines.single.text, '保留歌词');
    expect(await source.readAsBytes(), [2, 3, 4]);
  });

  test('save failure retains copied file in case in-memory snapshot refers to it', () async {
    final failing = _FailingRepository();
    await expectLater(importer(() async => source.path, projects: failing).importVocalFor(project), throwsStateError);
    expect(await File(failing.received!.audioAsset!.vocalPath!).readAsBytes(), [2, 3, 4]);
    expect(failing.expectedRevision, project.revision);
  });

  test('missing project audio does not open picker', () async {
    var picked = false;
    final blank = ProjectManifest(id: 'blank', name: 'Blank', createdAt: DateTime(2026), updatedAt: DateTime(2026));
    await expectLater(importer(() async { picked = true; return source.path; }).importVocalFor(blank), throwsStateError);
    expect(picked, isFalse);
  });

  test('consecutive accompaniment and vocal imports keep both sources', () async {
    final initial = project.copyWith(audioAsset: const AudioAsset(originalPath: '/song.wav', format: 'wav'));
    final stored = await repository.updateProject(initial);
    final first = (await importer(() async => source.path).importFor(stored))!;
    final second = (await importer(() async => source.path).importVocalFor(first))!;
    expect(second.audioAsset!.instrumentalPath, isNotNull);
    expect(second.audioAsset!.vocalPath, isNotNull);
    expect(second.audioAsset!.instrumentalPath, isNot(second.audioAsset!.vocalPath));
    expect(await File(second.audioAsset!.instrumentalPath!).readAsBytes(), [2, 3, 4]);
    expect(await File(second.audioAsset!.vocalPath!).readAsBytes(), [2, 3, 4]);
  });
}

class _FailingRepository extends Fake implements ProjectRepository {
  ProjectManifest? received;
  int? expectedRevision;
  @override
  Future<ProjectManifest> updateProjectIfUnchanged(ProjectManifest project, {required int expectedRevision}) async {
    received = project;
    this.expectedRevision = expectedRevision;
    throw StateError('write failed after in-memory update');
  }
}
