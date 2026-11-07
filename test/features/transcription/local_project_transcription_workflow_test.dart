import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/memory_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/file_batch_transcription_queue.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/high_quality_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_project_transcription_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_chunked_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_queue_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

void main() {
  group('LocalProjectTranscriptionWorkflow typed cancellation', () {
    late Directory temp;
    late File audioFile;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp(
        'lyricforge-workflow-cancel-',
      );
      audioFile = File('${temp.path}${Platform.pathSeparator}song.wav');
      await audioFile.writeAsBytes(List<int>.filled(128, 1));
    });

    tearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    test(
      'restores editing status and preserves existing lyrics without recording error',
      () async {
        final repository = MemoryProjectRepository();
        const existingLyrics = LyricDocument(
          language: 'zh',
          lines: [
            LyricLine(
              id: 'line-1',
              text: '原有第一句歌词',
              startTime: Duration(seconds: 1),
              endTime: Duration(seconds: 4),
              confidence: 96,
            ),
            LyricLine(
              id: 'line-2',
              text: '原有第二句歌词',
              startTime: Duration(seconds: 5),
              endTime: Duration(seconds: 8),
              confidence: 94,
            ),
          ],
          metadata: {
            'manuallyEditedLineIds': ['line-1'],
          },
        );
        var project = await repository.createProject(name: 'Existing Lyrics');
        project = await repository.updateProject(
          project.copyWith(
            status: ProjectStatus.editing,
            currentStage: ProcessingStage.lyricsEdited,
            audioAsset: AudioAsset(originalPath: audioFile.path, format: 'wav'),
            lyricDocument: existingLyrics,
            projectDirectory:
                '${temp.path}${Platform.pathSeparator}${project.id}',
            metadata: const {'userNote': 'keep'},
          ),
        );

        ProjectStatus? statusDuringRun;
        final service = _ScriptedTranscriptionService((_) async {
          final current = await repository.getProjectById(project.id);
          statusDuringRun = current?.status;
          throw const TranscriptionException.cancelled(
            'custom English cancellation message',
          );
        });
        final workflow = _buildWorkflow(
          repository: repository,
          transcriptionService: service,
        );

        await expectLater(
          workflow.transcribeProject(project.id),
          throwsA(
            isA<TranscriptionException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  TranscriptionFailureKind.cancelled,
                )
                .having((error) => error.isCancelled, 'isCancelled', isTrue)
                .having(
                  (error) => error.message,
                  'message',
                  'custom English cancellation message',
                ),
          ),
        );

        expect(statusDuringRun, ProjectStatus.transcribing);
        final restored = await repository.getProjectById(project.id);
        expect(restored, isNotNull);
        expect(restored!.status, ProjectStatus.editing);
        expect(restored.currentStage, ProcessingStage.lyricsEdited);
        expect(restored.hasLyrics, isTrue);
        expect(
          restored.lyricDocument!.lines.map((line) => line.text).toList(),
          ['原有第一句歌词', '原有第二句歌词'],
        );
        expect(restored.lyricDocument!.metadata['manuallyEditedLineIds'], [
          'line-1',
        ]);
        expect(restored.metadata['userNote'], 'keep');
        expect(restored.metadata.containsKey('transcriptionError'), isFalse);
      },
    );

    test(
      'preserves ready status when a ready project with lyrics is cancelled',
      () async {
        final repository = MemoryProjectRepository();
        var project = await repository.createProject(name: 'Ready Song');
        project = await repository.updateProject(
          project.copyWith(
            status: ProjectStatus.ready,
            currentStage: ProcessingStage.exported,
            audioAsset: AudioAsset(originalPath: audioFile.path, format: 'wav'),
            lyricDocument: const LyricDocument(
              language: 'en',
              lines: [
                LyricLine(
                  text: 'verified line',
                  startTime: Duration(seconds: 2),
                  endTime: Duration(seconds: 5),
                ),
              ],
            ),
            projectDirectory:
                '${temp.path}${Platform.pathSeparator}${project.id}',
          ),
        );

        final workflow = _buildWorkflow(
          repository: repository,
          transcriptionService: _ScriptedTranscriptionService((_) async {
            throw const TranscriptionException.cancelled('aborted by user');
          }),
        );

        await expectLater(
          workflow.transcribeProject(project.id),
          throwsA(
            isA<TranscriptionException>().having(
              (error) => error.kind,
              'kind',
              TranscriptionFailureKind.cancelled,
            ),
          ),
        );

        final restored = await repository.getProjectById(project.id);
        expect(restored!.status, ProjectStatus.ready);
        expect(restored.currentStage, ProcessingStage.exported);
        expect(restored.lyricDocument!.lines.single.text, 'verified line');
        expect(restored.metadata.containsKey('transcriptionError'), isFalse);
      },
    );

    test(
      'restores draft status across full pipeline when cancelling a project without lyrics',
      () async {
        final repository = MemoryProjectRepository();
        var project = await repository.createProject(name: 'Fresh Draft');
        project = await repository.updateProject(
          project.copyWith(
            status: ProjectStatus.draft,
            currentStage: ProcessingStage.audioImported,
            audioAsset: AudioAsset(originalPath: audioFile.path, format: 'wav'),
            projectDirectory:
                '${temp.path}${Platform.pathSeparator}${project.id}',
          ),
        );

        final enteredEngine = Completer<void>();
        final releaseEngine = Completer<void>();
        final primaryEngine = _ScriptedTranscriptionService(
          (_) async {
            if (!enteredEngine.isCompleted) enteredEngine.complete();
            await releaseEngine.future;
            throw const TranscriptionException('unreachable after cancel');
          },
          onCancel: () async {
            if (!releaseEngine.isCompleted) releaseEngine.complete();
          },
        );
        final fallbackEngine = _ScriptedTranscriptionService((_) async {
          throw const TranscriptionException('fallback must not run');
        });
        final highQuality = HighQualityTranscriptionService(
          primary: primaryEngine,
          fallback: fallbackEngine,
          sharedAudioPreparer: (_) async => audioFile.path,
        );
        final chunked = ResumableChunkedTranscriptionService(
          delegate: highQuality,
          processSupervisor: _probeDurationSupervisor('00:03:00.000'),
        );
        final workflow = _buildWorkflow(
          repository: repository,
          transcriptionService: chunked,
        );

        final running = workflow.transcribeProject(project.id);
        await enteredEngine.future.timeout(const Duration(seconds: 2));
        final inFlight = await repository.getProjectById(project.id);
        expect(inFlight!.status, ProjectStatus.transcribing);

        await workflow.cancel();

        await expectLater(
          running,
          throwsA(
            isA<TranscriptionException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  TranscriptionFailureKind.cancelled,
                )
                .having((error) => error.isCancelled, 'isCancelled', isTrue),
          ),
        );

        final restored = await repository.getProjectById(project.id);
        expect(restored, isNotNull);
        expect(restored!.status, ProjectStatus.draft);
        expect(restored.currentStage, ProcessingStage.audioImported);
        expect(restored.lyricDocument, isNull);
        expect(restored.hasLyrics, isFalse);
        expect(restored.metadata.containsKey('transcriptionError'), isFalse);
        expect(fallbackEngine.calls, 0);
        await chunked.dispose();
      },
    );

    test(
      'unknown exception with legacy cancellation message marks project error',
      () async {
        final repository = MemoryProjectRepository();
        var project = await repository.createProject(name: 'Deceptive Error');
        project = await repository.updateProject(
          project.copyWith(
            status: ProjectStatus.draft,
            currentStage: ProcessingStage.audioImported,
            audioAsset: AudioAsset(originalPath: audioFile.path, format: 'wav'),
            projectDirectory:
                '${temp.path}${Platform.pathSeparator}${project.id}',
          ),
        );

        final workflow = _buildWorkflow(
          repository: repository,
          transcriptionService: _ScriptedTranscriptionService((_) async {
            throw const TranscriptionException('歌词识别已取消');
          }),
        );

        await expectLater(
          workflow.transcribeProject(project.id),
          throwsA(
            isA<TranscriptionException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  TranscriptionFailureKind.unknown,
                )
                .having((error) => error.isCancelled, 'isCancelled', isFalse),
          ),
        );

        final failed = await repository.getProjectById(project.id);
        expect(failed, isNotNull);
        expect(failed!.status, ProjectStatus.error);
        final recordedError = failed.metadata['transcriptionError'] as Map?;
        expect(recordedError, isNotNull);
        expect(recordedError!['kind'], 'unknown');
        expect(recordedError['message'], '歌词识别已取消');
      },
    );

    test(
      'typed cancelled error mentioning model copy does not block batch queue as environment fault',
      () async {
        final repository = _DirectoryProjectRepository(temp);
        final firstAudio = File(
          '${temp.path}${Platform.pathSeparator}first.wav',
        );
        final secondAudio = File(
          '${temp.path}${Platform.pathSeparator}second.wav',
        );
        await firstAudio.writeAsBytes(List<int>.filled(64, 1));
        await secondAudio.writeAsBytes(List<int>.filled(64, 2));

        var runCount = 0;
        final workflow = _buildWorkflow(
          repository: repository,
          transcriptionService: _ScriptedTranscriptionService((request) async {
            runCount += 1;
            if (runCount == 1) {
              throw const TranscriptionException.cancelled('Qwen 模型加载阶段已取消');
            }
            return TranscriptionResult(
              lyrics: const LyricDocument(
                language: 'en',
                lines: [
                  LyricLine(
                    text: 'second song done',
                    startTime: Duration.zero,
                    endTime: Duration(seconds: 2),
                  ),
                ],
              ),
              normalizedAudioPath: request.inputAudioPath,
              rawJsonPath:
                  '${request.outputDirectory}${Platform.pathSeparator}raw.json',
              detectedLanguage: 'en',
            );
          }),
        );
        final queueRoot = Directory(
          '${temp.path}${Platform.pathSeparator}queue',
        );
        final queue = FileBatchTranscriptionQueue(
          projectRepository: repository,
          workflow: workflow,
          rootDirectory: queueRoot,
        );

        await queue.initialize();
        await queue.enqueuePaths([firstAudio.path, secondAudio.path]);
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (queue.current.completedCount < 1) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Timed out waiting for second queue item');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        expect(queue.current.isEnvironmentBlocked, isFalse);
        expect(queue.current.isPaused, isFalse);
        expect(queue.current.pauseReason, isNull);
        expect(
          queue.current.items[1].status,
          TranscriptionQueueItemStatus.completed,
        );
        final projects = await repository.getAllProjects();
        expect(projects, hasLength(2));
        final firstProject = projects.singleWhere((p) => p.name == 'first');
        expect(firstProject.status, ProjectStatus.draft);
        expect(
          firstProject.metadata.containsKey('transcriptionError'),
          isFalse,
        );
        await queue.dispose();
      },
    );
  });
}

LocalProjectTranscriptionWorkflow _buildWorkflow({
  required ProjectRepository repository,
  required TranscriptionService transcriptionService,
}) {
  return LocalProjectTranscriptionWorkflow(
    projectRepository: repository,
    transcriptionService: transcriptionService,
    settingsStore: _FakeSettingsStore(),
    profileResolver: const _FakeProfileResolver(),
    runtimeManager: _FakeRuntimeManager(),
    mediaMetadataRepository: _FakeMetadataRepository(),
    playbackSession: _FakePlaybackSession(),
    pathCanonicalizer: const FileAudioPathCanonicalizer(),
  );
}

AsrProcessSupervisor _probeDurationSupervisor(String durationLabel) {
  return AsrProcessSupervisor(
    startProcess: (_, _) async {
      final process = _ImmediateStderrProcess(
        'Duration: $durationLabel, start: 0.000000, bitrate: 1 kb/s',
      );
      return process;
    },
    streamDrainGrace: const Duration(milliseconds: 10),
  );
}

const _configuredConfig = TranscriptionConfig(
  mode: TranscriptionMode.highestQuality,
  profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
  qwenExecutable: 'qwen3-asr',
  whisperExecutable: 'whisper-cli',
  modelPath: 'ggml-large-v3.bin',
  ffmpegExecutable: 'ffmpeg',
);

class _FakeSettingsStore implements TranscriptionSettingsStore {
  @override
  Future<TranscriptionConfig?> load() async => _configuredConfig;

  @override
  Future<void> save(TranscriptionConfig config) async {}

  @override
  Future<void> clear() async {}
}

class _FakeProfileResolver implements TranscriptionProfileResolver {
  const _FakeProfileResolver();

  @override
  Future<TranscriptionHardwareInfo> detectHardware() async {
    return const TranscriptionHardwareInfo(
      operatingSystem: 'linux',
      architecture: 'x86_64',
      gpuName: 'NVIDIA GeForce RTX 5080',
    );
  }

  @override
  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig config,
  ) async {
    return ResolvedTranscriptionProfile(
      profile: TranscriptionProfilePreference.rtx5080HighQuality,
      label: 'RTX 5080 test profile',
      description: 'test',
      hardware: await detectHardware(),
      config: config,
    );
  }
}

class _FakeRuntimeManager implements AsrRuntimeManager {
  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => const Stream.empty();

  @override
  bool get isInstalling => false;

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      config;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    return AsrRuntimeStatus(
      profile: ResolvedTranscriptionProfile(
        profile: TranscriptionProfilePreference.rtx5080HighQuality,
        label: 'RTX 5080 test profile',
        description: 'test',
        hardware: const TranscriptionHardwareInfo(
          operatingSystem: 'linux',
          architecture: 'x86_64',
          gpuName: 'NVIDIA GeForce RTX 5080',
        ),
        config: config,
      ),
      components: const [
        AsrRuntimeComponentStatus(
          component: AsrRuntimeComponent.ffmpeg,
          state: AsrRuntimeComponentState.ready,
          label: 'FFmpeg',
          detail: 'ready',
        ),
        AsrRuntimeComponentStatus(
          component: AsrRuntimeComponent.whisperRuntime,
          state: AsrRuntimeComponentState.ready,
          label: 'Whisper runtime',
          detail: 'ready',
        ),
        AsrRuntimeComponentStatus(
          component: AsrRuntimeComponent.whisperModel,
          state: AsrRuntimeComponentState.ready,
          label: 'Whisper model',
          detail: 'ready',
        ),
      ],
      managedRoot: '/tmp/asr-runtime',
    );
  }

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async => config;

  @override
  Future<void> cancel() async {}
}

class _FakeMetadataRepository implements LocalMediaMetadataRepository {
  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async => null;

  @override
  Future<LocalMediaMetadata> save(LocalMediaMetadata metadata) async =>
      metadata;

  @override
  Future<List<LocalMediaMetadata>> getAll() async => const [];

  @override
  Future<void> removeForAudio(String sourcePath) async {}

  @override
  Future<String> importArtwork({
    required String sourcePath,
    required String imagePath,
  }) async => imagePath;

  @override
  Future<void> removeManagedArtwork(String? artworkPath) async {}
}

class _FakePlaybackSession implements PlaybackSessionService {
  @override
  PlaybackSessionState currentState = const PlaybackSessionState();

  @override
  Stream<PlaybackSessionState> get stateStream => const Stream.empty();

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  @override
  Future<void> updateItem(PlaybackItem item) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedTranscriptionService implements TranscriptionService {
  _ScriptedTranscriptionService(this._handler, {this.onCancel});

  final Future<TranscriptionResult> Function(TranscriptionRequest request)
  _handler;
  final Future<void> Function()? onCancel;
  final StreamController<TranscriptionProgress> _progress =
      StreamController<TranscriptionProgress>.broadcast();
  bool _running = false;
  int calls = 0;

  @override
  Stream<TranscriptionProgress> get progressStream => _progress.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    calls += 1;
    _running = true;
    try {
      return await _handler(request);
    } finally {
      _running = false;
    }
  }

  @override
  Future<void> cancel() async {
    final callback = onCancel;
    if (callback != null) await callback();
  }

  @override
  Future<void> dispose() => _progress.close();
}

class _ImmediateStderrProcess implements Process {
  _ImmediateStderrProcess(String stderrText) {
    Timer(const Duration(milliseconds: 1), () {
      _stderr.add(stderrText.codeUnits);
      if (!_exitCode.isCompleted) _exitCode.complete(0);
      unawaited(_stdout.close());
      unawaited(_stderr.close());
    });
  }

  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final IOSink _stdin = IOSink(_DiscardingConsumer());

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 24680;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

class _DirectoryProjectRepository implements ProjectRepository {
  _DirectoryProjectRepository(this._root);

  final Directory _root;
  final Map<String, ProjectManifest> _projects = <String, ProjectManifest>{};
  int _nextId = 1;

  @override
  Future<ProjectManifest> createProject({
    required String name,
    String? artist,
    String? album,
  }) async {
    final now = DateTime.now();
    final id = 'project-${_nextId++}';
    final project = ProjectManifest(
      id: id,
      name: name,
      artist: artist,
      album: album,
      createdAt: now,
      updatedAt: now,
      projectDirectory: '${_root.path}${Platform.pathSeparator}$id',
    );
    _projects[id] = project;
    return project;
  }

  @override
  Future<void> deleteProject(String id) async {
    _projects.remove(id);
  }

  @override
  Future<List<ProjectManifest>> getAllProjects() async =>
      _projects.values.toList(growable: false);

  @override
  Future<ProjectManifest?> getProjectById(String id) async => _projects[id];

  @override
  Future<List<ProjectManifest>> getRecentProjects({int limit = 10}) async =>
      _projects.values.take(limit).toList(growable: false);

  @override
  Future<ProjectManifest> updateProject(ProjectManifest project) async {
    final existing = _projects[project.id];
    if (existing == null) {
      throw ProjectRepositoryException('Project not found: ${project.id}');
    }
    final updated = project.copyWith(
      updatedAt: DateTime.now(),
      revision: existing.revision + 1,
    );
    _projects[project.id] = updated;
    return updated;
  }

  @override
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest project, {
    required int expectedRevision,
  }) async {
    final existing = _projects[project.id];
    if (existing == null || existing.revision != expectedRevision) {
      throw ProjectUpdateConflictException(currentProject: existing);
    }
    return updateProject(project);
  }
}

class _DiscardingConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<void> close() async {}
}
