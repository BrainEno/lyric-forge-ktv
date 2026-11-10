import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/file_batch_transcription_queue.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_queue_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/project_transcription_workflow.dart';

void main() {
  test('one failed song does not block the next queue item', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-queue-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final audioA = File('${root.path}${Platform.pathSeparator}fail.mp3');
    final audioB = File('${root.path}${Platform.pathSeparator}ok.mp3');
    await audioA.writeAsBytes(<int>[1]);
    await audioB.writeAsBytes(<int>[2]);

    final projectRoot = Directory(
      '${root.path}${Platform.pathSeparator}projects',
    );
    final queueRoot = Directory('${root.path}${Platform.pathSeparator}queue');
    final repository = FileProjectRepository(rootDirectory: projectRoot);
    final workflow = _FakeWorkflow(repository);
    final queue = FileBatchTranscriptionQueue(
      projectRepository: repository,
      workflow: workflow,
      rootDirectory: queueRoot,
    );

    await queue.initialize();
    expect(await queue.enqueuePaths(<String>[audioA.path, audioB.path]), 2);
    await _waitUntil(() {
      final state = queue.current;
      return state.failedCount == 1 && state.completedCount == 1;
    });

    expect(queue.current.items[0].status, TranscriptionQueueItemStatus.failed);
    expect(
      queue.current.items[1].status,
      TranscriptionQueueItemStatus.completed,
    );
    expect(queue.current.pauseReason, isNull);
    await queue.dispose();
  });

  test(
    'typed cancellation pauses the queue without recording failure',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lyricforge-queue-cancel-',
      );
      addTearDown(() => root.delete(recursive: true));
      final audio = File('${root.path}${Platform.pathSeparator}cancel.mp3');
      await audio.writeAsBytes([1]);
      final repository = FileProjectRepository(
        rootDirectory: Directory('${root.path}/projects'),
      );
      final queue = FileBatchTranscriptionQueue(
        projectRepository: repository,
        workflow: _FakeWorkflow(repository),
        rootDirectory: Directory('${root.path}/queue'),
      );
      addTearDown(queue.dispose);
      await queue.initialize();
      await queue.enqueuePaths([audio.path]);
      await _waitUntil(
        () => queue.current.isPaused && !queue.current.isProcessing,
      );
      expect(queue.current.pauseReason, TranscriptionQueuePauseReason.manual);
      expect(
        queue.current.items.single.status,
        TranscriptionQueueItemStatus.paused,
      );
      expect(queue.current.items.single.error, isNull);
      expect(queue.current.failedCount, 0);
    },
  );

  test(
    'typed environment errors protectively pause without relying on copy',
    () async {
      final root = await Directory.systemTemp.createTemp('lyricforge-blocked-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final blocked = File('${root.path}${Platform.pathSeparator}blocked.mp3');
      final later = File('${root.path}${Platform.pathSeparator}later.mp3');
      await blocked.writeAsBytes(<int>[1]);
      await later.writeAsBytes(<int>[2]);

      final repository = FileProjectRepository(
        rootDirectory: Directory(
          '${root.path}${Platform.pathSeparator}projects',
        ),
      );
      final queue = FileBatchTranscriptionQueue(
        projectRepository: repository,
        workflow: _FakeWorkflow(repository),
        rootDirectory: Directory('${root.path}${Platform.pathSeparator}queue'),
      );

      await queue.initialize();
      await queue.enqueuePaths(<String>[blocked.path, later.path]);
      await _waitUntil(
        () => queue.current.isPaused && !queue.current.isProcessing,
      );

      expect(queue.current.failedCount, 0);
      expect(queue.current.completedCount, 0);
      expect(
        queue.current.items[0].status,
        TranscriptionQueueItemStatus.queued,
      );
      expect(
        queue.current.items[1].status,
        TranscriptionQueueItemStatus.queued,
      );
      expect(
        queue.current.pauseReason,
        TranscriptionQueuePauseReason.environment,
      );
      expect(queue.current.isEnvironmentBlocked, isTrue);
      expect(queue.current.pauseMessage, contains('GPU driver unavailable'));
      expect(queue.current.items[0].message, contains('保护性暂停'));
      await queue.dispose();
    },
  );

  test('busy pauses the queue, persists, and retries only on request', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-busy-');
    addTearDown(() => root.delete(recursive: true));
    final audioA = File('${root.path}/busy.mp3');
    final audioB = File('${root.path}/later.mp3');
    await audioA.writeAsBytes([1]);
    await audioB.writeAsBytes([2]);
    final repository = FileProjectRepository(rootDirectory: Directory('${root.path}/projects'));
    final queueRoot = Directory('${root.path}/queue');
    final workflow = _FakeWorkflow(repository, busy: true);
    final first = FileBatchTranscriptionQueue(projectRepository: repository,
        workflow: workflow, rootDirectory: queueRoot);
    await first.initialize();
    await first.enqueuePaths([audioA.path, audioB.path]);
    await _waitUntil(() => first.current.isResourceBusy && !first.current.isProcessing);
    expect(workflow.calls, 1);
    expect(first.current.failedCount, 0);
    expect(first.current.completedCount, 0);
    expect(first.current.queuedCount, 2);
    expect(first.current.isEnvironmentBlocked, isFalse);
    expect(first.current.pauseMessage, contains('模型'));
    final projectId = first.current.items.first.projectId;
    expect(projectId, isNotNull);
    await first.dispose();

    final retryWorkflow = _FakeWorkflow(repository, busy: true);
    final second = FileBatchTranscriptionQueue(projectRepository: repository,
        workflow: retryWorkflow, rootDirectory: queueRoot);
    await second.initialize();
    expect(second.current.isResourceBusy, isTrue);
    expect(second.current.items.first.projectId, projectId);
    expect(retryWorkflow.calls, 0);
    await second.resume();
    await _waitUntil(() => second.current.isResourceBusy && !second.current.isProcessing);
    expect(retryWorkflow.calls, 1);
    expect(second.current.queuedCount, 2);
    retryWorkflow.busy = false;
    await second.resume();
    await _waitUntil(() => second.current.completedCount == 2 && !second.current.isProcessing);
    expect(second.current.pauseReason, isNull);
    expect(second.current.pauseMessage, isNull);
    expect(second.current.failedCount, 0);
    expect(second.current.items.first.projectId, projectId);
    expect(await repository.getAllProjects(), hasLength(2));
    await second.dispose();
  });

  test('manual pause wins when a busy failure arrives later', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-busy-manual-');
    addTearDown(() => root.delete(recursive: true));
    final audio = File('${root.path}/song.mp3');
    await audio.writeAsBytes([1]);
    final repository = FileProjectRepository(rootDirectory: Directory('${root.path}/projects'));
    final entered = Completer<void>();
    final release = Completer<void>();
    final workflow = _FakeWorkflow(repository, busy: true);
    workflow.beforeBusy = () async { entered.complete(); await release.future; };
    final queue = FileBatchTranscriptionQueue(projectRepository: repository,
        workflow: workflow, rootDirectory: Directory('${root.path}/queue'));
    await queue.initialize();
    await queue.enqueuePaths([audio.path]);
    await entered.future;
    await queue.pause();
    release.complete();
    await _waitUntil(() => !queue.current.isProcessing);
    expect(queue.current.pauseReason, TranscriptionQueuePauseReason.manual);
    expect(queue.current.items.single.status, TranscriptionQueueItemStatus.paused);
    expect(queue.current.failedCount, 0);
    await queue.dispose();
  });

  test(
    'environment pause reason survives restart and clears only on resume',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lyricforge-env-restart-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final audio = File('${root.path}${Platform.pathSeparator}blocked.mp3');
      await audio.writeAsBytes(<int>[1]);
      final projectRoot = Directory(
        '${root.path}${Platform.pathSeparator}projects',
      );
      final queueRoot = Directory('${root.path}${Platform.pathSeparator}queue');
      final repository = FileProjectRepository(rootDirectory: projectRoot);

      final first = FileBatchTranscriptionQueue(
        projectRepository: repository,
        workflow: _FakeWorkflow(repository),
        rootDirectory: queueRoot,
      );
      await first.initialize();
      await first.enqueuePaths([audio.path]);
      await _waitUntil(() => first.current.isEnvironmentBlocked);
      final savedMessage = first.current.pauseMessage;
      await first.dispose();

      final second = FileBatchTranscriptionQueue(
        projectRepository: repository,
        workflow: _FakeWorkflow(repository, blockEnvironment: false),
        rootDirectory: queueRoot,
      );
      await second.initialize();
      expect(second.current.isEnvironmentBlocked, isTrue);
      expect(second.current.pauseMessage, savedMessage);

      await second.resume();
      expect(second.current.pauseReason, isNull);
      expect(second.current.pauseMessage, isNull);
      await _waitUntil(() => second.current.completedCount == 1);
      await second.dispose();
    },
  );

  test('running item is restored as queued after restart', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-recover-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final projectRoot = Directory(
      '${root.path}${Platform.pathSeparator}projects',
    );
    final queueRoot = Directory('${root.path}${Platform.pathSeparator}queue');
    await queueRoot.create(recursive: true);
    final now = DateTime.now();
    final item = TranscriptionQueueItem(
      id: '1',
      sourcePath: '${root.path}${Platform.pathSeparator}song.mp3',
      projectName: 'song',
      status: TranscriptionQueueItemStatus.running,
      progress: 0.4,
      message: '处理中',
      createdAt: now,
      updatedAt: now,
    );
    await File(
      '${queueRoot.path}${Platform.pathSeparator}transcription_queue.json',
    ).writeAsString(
      jsonEncode({
        'version': 1,
        'paused': true,
        'items': <Map<String, dynamic>>[item.toJson()],
      }),
    );

    final repository = FileProjectRepository(rootDirectory: projectRoot);
    final queue = FileBatchTranscriptionQueue(
      projectRepository: repository,
      workflow: _FakeWorkflow(repository),
      rootDirectory: queueRoot,
    );
    await queue.initialize();

    expect(queue.current.isPaused, isTrue);
    expect(queue.current.pauseReason, TranscriptionQueuePauseReason.manual);
    expect(
      queue.current.items.single.status,
      TranscriptionQueueItemStatus.queued,
    );
    expect(queue.current.items.single.message, contains('已恢复'));
    await queue.dispose();
  });

  test(
    'existing batch-marked project is reused when projectId write was lost',
    () async {
      final root = await Directory.systemTemp.createTemp('lyricforge-link-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final audio = File('${root.path}${Platform.pathSeparator}song.mp3');
      await audio.writeAsBytes(<int>[1]);
      final projectRoot = Directory(
        '${root.path}${Platform.pathSeparator}projects',
      );
      final queueRoot = Directory('${root.path}${Platform.pathSeparator}queue');
      await queueRoot.create(recursive: true);

      final repository = FileProjectRepository(rootDirectory: projectRoot);
      var project = await repository.createProject(name: 'song');
      project = await repository.updateProject(
        project.copyWith(
          currentStage: ProcessingStage.audioImported,
          audioAsset: AudioAsset(originalPath: audio.path, format: 'mp3'),
          metadata: const {'batchQueueItemId': 'recover-link'},
        ),
      );

      final now = DateTime.now();
      final item = TranscriptionQueueItem(
        id: 'recover-link',
        sourcePath: audio.path,
        projectName: 'song',
        status: TranscriptionQueueItemStatus.queued,
        createdAt: now,
        updatedAt: now,
      );
      await File(
        '${queueRoot.path}${Platform.pathSeparator}transcription_queue.json',
      ).writeAsString(
        jsonEncode({
          'version': 1,
          'paused': true,
          'items': <Map<String, dynamic>>[item.toJson()],
        }),
      );

      final queue = FileBatchTranscriptionQueue(
        projectRepository: repository,
        workflow: _FakeWorkflow(repository),
        rootDirectory: queueRoot,
      );
      await queue.initialize();
      await queue.resume();
      await _waitUntil(() => queue.current.completedCount == 1);

      final projects = await repository.getAllProjects();
      expect(projects, hasLength(1));
      expect(queue.current.items.single.projectId, project.id);
      await queue.dispose();
    },
  );
}

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for queue state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _FakeWorkflow implements ProjectTranscriptionWorkflow {
  final ProjectRepository repository;
  final bool blockEnvironment;
  bool busy;
  int calls = 0;
  Future<void> Function()? beforeBusy;
  final StreamController<TranscriptionProgress> _controller =
      StreamController<TranscriptionProgress>.broadcast();
  bool _running = false;

  _FakeWorkflow(this.repository, {this.blockEnvironment = true, this.busy = false});

  @override
  Stream<TranscriptionProgress> get progressStream => _controller.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> transcribeProject(String projectId) async {
    _running = true;
    calls++;
    try {
      if (busy) {
        await beforeBusy?.call();
        throw const TranscriptionException.busy('模型正在使用');
      }
      final project = await repository.getProjectById(projectId);
      if (project == null) {
        throw const TranscriptionException.input('missing project');
      }
      _controller.add(
        const TranscriptionProgress(
          stage: TranscriptionStage.transcribing,
          progress: 0.5,
          message: 'fake progress',
        ),
      );
      if (project.name == 'cancel') {
        throw const TranscriptionException.cancelled('stopped');
      }
      if (project.name == 'fail') {
        throw const TranscriptionException.input('mock song failure');
      }
      if (project.name == 'blocked' && blockEnvironment) {
        // Deliberately avoid every legacy Chinese keyword. This proves queue
        // protection follows the structured failure kind, not display copy.
        throw const TranscriptionException.environment(
          'GPU driver unavailable',
        );
      }
      await repository.updateProject(
        project.copyWith(
          status: ProjectStatus.editing,
          currentStage: ProcessingStage.transcriptionComplete,
          lyricDocument: const LyricDocument(
            language: 'en',
            lines: <LyricLine>[
              LyricLine(
                text: 'done',
                startTime: Duration.zero,
                endTime: Duration(seconds: 1),
              ),
            ],
          ),
        ),
      );
    } finally {
      _running = false;
    }
  }

  @override
  Future<void> cancel() async {
    _running = false;
  }
}
