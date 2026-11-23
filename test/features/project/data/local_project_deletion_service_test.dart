import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/services/local_project_deletion_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/services/project_deletion_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_queue_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/batch_transcription_queue.dart';

ProjectManifest _project(String id, {String? audio, String? directory}) =>
    ProjectManifest(
      id: id,
      name: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      projectDirectory: directory,
      audioAsset: audio == null
          ? null
          : AudioAsset(originalPath: audio, format: 'mp3'),
    );

TranscriptionQueueItem _item(
  String id,
  String? projectId,
  TranscriptionQueueItemStatus status,
) => TranscriptionQueueItem(
  id: id,
  sourcePath: '/music/$id.mp3',
  projectName: id,
  projectId: projectId,
  status: status,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  late Directory root;
  late Directory projectsRoot;
  late _Projects projects;
  late _Queue queue;
  late _Playback playback;
  late LocalProjectDeletionService service;

  String path(List<String> parts) =>
      [root.path, ...parts].join(Platform.pathSeparator);

  Future<Directory> folderOf(String id, {int bytes = 10}) async {
    final folder = Directory(path(['Projects', id, 'transcription']));
    await folder.create(recursive: true);
    await File(
      '${folder.path}${Platform.pathSeparator}draft.json',
    ).writeAsBytes(List.filled(bytes, 1));
    return folder.parent;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('project-delete-');
    projectsRoot = Directory(path(['Projects']));
    projects = _Projects();
    queue = _Queue();
    playback = _Playback();
    service = LocalProjectDeletionService(
      projectRepository: projects,
      playbackSession: playback,
      transcriptionQueue: queue,
      projectsRoot: () async => projectsRoot,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('deletes the project, its folder and its queue entries', () async {
    final dup = _project('dup', audio: '/music/song.mp3');
    final keep = _project('keep', audio: '/music/song.mp3');
    projects.add([dup, keep]);
    final folder = await folderOf('dup', bytes: 2048);
    final takes = Directory('${folder.path}${Platform.pathSeparator}recordings');
    await Directory('${takes.path}${Platform.pathSeparator}take-1').create(
      recursive: true,
    );
    queue.items = [
      _item('done', 'dup', TranscriptionQueueItemStatus.completed),
      _item('failed', 'dup', TranscriptionQueueItemStatus.failed),
      _item('other', 'keep', TranscriptionQueueItemStatus.completed),
    ];

    final check = await service.check(dup);
    expect(check.canDelete, isTrue);
    expect(check.hasFiles, isTrue);
    expect(check.removableBytes, 2048);
    expect(check.recordings, 1);

    final result = await service.delete(dup);
    expect(result.removedFiles, isTrue);
    expect(await projects.getProjectById('dup'), isNull);
    expect(await projects.getProjectById('keep'), isNotNull);
    expect(await folder.exists(), isFalse);
    expect(queue.removed, ['done', 'failed']);
  });

  test('can keep the folder', () async {
    final project = _project('p');
    projects.add([project]);
    final folder = await folderOf('p');

    final result = await service.delete(project, removeFiles: false);
    expect(result.removedFiles, isFalse);
    expect(await projects.getProjectById('p'), isNull);
    expect(await folder.exists(), isTrue);
  });

  test('a project being recognised or played is not deleted', () async {
    final project = _project('p');
    projects.add([project]);
    queue.items = [_item('run', 'p', TranscriptionQueueItemStatus.running)];

    expect((await service.check(project)).blocker, contains('批量识别'));
    await expectLater(
      service.delete(project),
      throwsA(isA<ProjectDeletionBlockedException>()),
    );
    expect(await projects.getProjectById('p'), isNotNull);

    queue.items = [];
    playback.state = PlaybackSessionState(
      queue: [
        PlaybackItem(
          id: 'song',
          title: 'p',
          projectId: 'p',
          audioAsset: const AudioAsset(originalPath: '/a.mp3', format: 'mp3'),
        ),
      ],
      currentIndex: 0,
    );
    expect((await service.check(project)).blocker, contains('正在播放'));
    playback.state = const PlaybackSessionState();
    expect((await service.check(project)).canDelete, isTrue);
  });

  test('a folder the user chose, or another project uses, is kept', () async {
    final chosen = _project('chosen', directory: path(['mine']));
    projects.add([chosen]);
    await folderOf('chosen');
    expect((await service.check(chosen)).hasFiles, isFalse);

    final shared = _project('shared');
    final folder = await folderOf('shared');
    final user = _project(
      'user',
      audio: '${folder.path}${Platform.pathSeparator}vocals.wav',
    );
    projects.add([shared, user]);
    expect(await service.removableFolder(shared), isNull);
    final result = await service.delete(shared);
    expect(result.removedFiles, isFalse);
    expect(await folder.exists(), isTrue);
  });

  test('no folder: nothing to remove, the project still goes', () async {
    final project = _project('bare');
    projects.add([project]);
    final check = await service.check(project);
    expect(check.hasFiles, isFalse);
    expect(check.removableBytes, 0);
    expect((await service.delete(project)).removedFiles, isFalse);
    expect(await projects.getAllProjects(), isEmpty);
  });
}

class _Projects extends Fake implements ProjectRepository {
  final Map<String, ProjectManifest> _byId = {};

  void add(List<ProjectManifest> projects) {
    for (final project in projects) {
      _byId[project.id] = project;
    }
  }

  @override
  Future<List<ProjectManifest>> getAllProjects() async => _byId.values.toList();

  @override
  Future<ProjectManifest?> getProjectById(String id) async => _byId[id];

  @override
  Future<void> deleteProject(String id) async {
    _byId.remove(id);
  }
}

class _Queue extends Fake implements BatchTranscriptionQueue {
  List<TranscriptionQueueItem> items = [];
  final removed = <String>[];

  @override
  TranscriptionQueueSnapshot get current => TranscriptionQueueSnapshot(
    items: items,
    isPaused: false,
    isProcessing: false,
  );

  @override
  Future<void> remove(String itemId) async {
    removed.add(itemId);
    items = items.where((item) => item.id != itemId).toList();
  }
}

class _Playback extends Fake implements PlaybackSessionService {
  PlaybackSessionState state = const PlaybackSessionState();

  @override
  PlaybackSessionState get currentState => state;
}
