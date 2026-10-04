import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
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
    await queue.dispose();
  });

  test('environment setup errors pause the queue without failing later songs',
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
      rootDirectory: Directory('${root.path}${Platform.pathSeparator}projects'),
    );
    final queue = FileBatchTranscriptionQueue(
      projectRepository: repository,
      workflow: _FakeWorkflow(repository),
      rootDirectory: Directory('${root.path}${Platform.pathSeparator}queue'),
    );

    await queue.initialize();
    await queue.enqueuePaths(<String>[blocked.path, later.path]);
    await _waitUntil(() => queue.current.isPaused && !queue.current.isProcessing);

    expect(queue.current.failedCount, 0);
    expect(queue.current.completedCount, 0);
    expect(queue.current.items[0].status, TranscriptionQueueItemStatus.queued);
    expect(queue.current.items[1].status, TranscriptionQueueItemStatus.queued);
    expect(queue.current.items[0].message, contains('识别环境'));
    await queue.dispose();
  });

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
    ).writeAsString(jsonEncode({
      'version': 1,
      'paused': true,
      'items': <Map<String, dynamic>>[item.toJson()],
    }));

    final repository = FileProjectRepository(rootDirectory: projectRoot);
    final queue = FileBatchTranscriptionQueue(
      projectRepository: repository,
      workflow: _FakeWorkflow(repository),
      rootDirectory: queueRoot,
    );
    await queue.initialize();

    expect(queue.current.isPaused, isTrue);
    expect(
      queue.current.items.single.status,
      TranscriptionQueueItemStatus.queued,
    );
    expect(queue.current.items.single.message, contains('已恢复'));
    await queue.dispose();
  });
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
  final StreamController<TranscriptionProgress> _controller =
      StreamController<TranscriptionProgress>.broadcast();
  bool _running = false;

  _FakeWorkflow(this.repository);

  @override
  Stream<TranscriptionProgress> get progressStream => _controller.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> transcribeProject(String projectId) async {
    _running = true;
    try {
      final project = await repository.getProjectById(projectId);
      if (project == null) throw const TranscriptionException('missing project');
      _controller.add(const TranscriptionProgress(
        stage: TranscriptionStage.transcribing,
        progress: 0.5,
        message: 'fake progress',
      ));
      if (project.name == 'fail') {
        throw const TranscriptionException('mock song failure');
      }
      if (project.name == 'blocked') {
        throw const TranscriptionException(
          '本机识别环境尚未准备完成，请先运行自动安装向导',
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
