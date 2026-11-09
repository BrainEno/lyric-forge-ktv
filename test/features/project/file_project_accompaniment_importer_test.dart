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
    root = await Directory.systemTemp.createTemp('accompaniment-test-');
    managed = Directory('${root.path}${Platform.pathSeparator}managed');
    source = File('${root.path}${Platform.pathSeparator}伴奏.wav');
    await source.writeAsBytes([1, 2, 3]);
    repository = FileProjectRepository(rootDirectory: root);
    final created = await repository.createProject(name: 'Song');
    project = await repository.updateProject(created.copyWith(
      audioAsset: const AudioAsset(originalPath: '/song.wav', format: 'wav'),
      lyricDocument: const LyricDocument(language: 'zh', lines: [
        LyricLine(text: '保留歌词', startTime: Duration.zero, endTime: Duration(seconds: 1)),
      ]),
    ));
  });

  tearDown(() async => root.delete(recursive: true));

  FileProjectAccompanimentImporter importer(Future<String?> Function() pick, {ProjectRepository? projects}) =>
      FileProjectAccompanimentImporter(projectRepository: projects ?? repository, storageDirectory: managed, pickPath: pick);

  test('copies and persists a selected backing track without changing the source or lyrics', () async {
    final updated = (await importer(() async => source.path).importFor(project))!;
    final copied = File(updated.audioAsset!.instrumentalPath!);
    expect(copied.path, isNot(source.path));
    expect(await copied.readAsBytes(), [1, 2, 3]);
    expect(await source.readAsBytes(), [1, 2, 3]);
    expect(updated.lyricDocument!.lines.single.text, '保留歌词');
    expect(availableKtvBackingModes(updated.audioAsset), contains(KtvBackingMode.instrumental));
    final reopened = FileProjectRepository(rootDirectory: root);
    expect((await reopened.getProjectById(project.id))!.audioAsset!.instrumentalPath, copied.path);
  });

  test('replacement retains the old track and associates a new managed copy', () async {
    final first = (await importer(() async => source.path).importFor(project))!;
    final old = File(first.audioAsset!.instrumentalPath!);
    final replacement = File('${root.path}${Platform.pathSeparator}new.mp3');
    await replacement.writeAsBytes([4, 5]);
    final updated = (await importer(() async => replacement.path).importFor(first))!;
    expect(await old.readAsBytes(), [1, 2, 3]);
    expect(await File(updated.audioAsset!.instrumentalPath!).readAsBytes(), [4, 5]);
    expect(updated.audioAsset!.instrumentalPath, isNot(old.path));
    expect(await replacement.readAsBytes(), [4, 5]);
  });

  test('cancel, unsupported and missing inputs do not change the project', () async {
    expect(await importer(() async => null).importFor(project), isNull);
    final unsupported = File('${root.path}${Platform.pathSeparator}bad.txt');
    await unsupported.writeAsString('data');
    await expectLater(importer(() async => unsupported.path).importFor(project), throwsFormatException);
    await expectLater(importer(() async => '${root.path}/missing.wav').importFor(project), throwsA(isA<FileSystemException>()));
    final empty = File('${root.path}${Platform.pathSeparator}empty.wav');
    await empty.writeAsBytes([]);
    await expectLater(importer(() async => empty.path).importFor(project), throwsA(isA<FileSystemException>()));
    expect((await repository.getProjectById(project.id))!.revision, project.revision);
    expect(await managed.exists(), isFalse);
  });

  test('stale project cannot replace newer lyrics or accompaniment', () async {
    final latest = await repository.updateProject(project.copyWith(name: 'Edited elsewhere'));
    await expectLater(importer(() async => source.path).importFor(project), throwsA(isA<ProjectUpdateConflictException>()));
    final stored = (await repository.getProjectById(project.id))!;
    expect(stored.name, latest.name);
    expect(stored.lyricDocument!.lines.single.text, '保留歌词');
    expect(stored.audioAsset!.instrumentalPath, isNull);
    expect(await source.readAsBytes(), [1, 2, 3]);
  });

  test('copy is retained after save failure because repository may reference it', () async {
    final failing = _FailingRepository();
    await expectLater(importer(() async => source.path, projects: failing).importFor(project), throwsStateError);
    final path = failing.received!.audioAsset!.instrumentalPath!;
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('project without audio does not open a picker', () async {
    var picked = false;
    final blank = ProjectManifest(id: 'blank', name: 'Blank', createdAt: DateTime(2026), updatedAt: DateTime(2026));
    await expectLater(importer(() async { picked = true; return source.path; }).importFor(blank), throwsStateError);
    expect(picked, isFalse);
  });
}

class _FailingRepository extends Fake implements ProjectRepository {
  ProjectManifest? received;

  @override
  Future<ProjectManifest> updateProjectIfUnchanged(ProjectManifest project, {required int expectedRevision}) async {
    received = project;
    throw StateError('write failed after in-memory update');
  }
}
