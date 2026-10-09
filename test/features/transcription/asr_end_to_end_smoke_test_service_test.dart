import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/memory_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_asr_end_to_end_smoke_test_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/project_transcription_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

void main() {
  group('LocalAsrEndToEndSmokeTestService', () {
    late Directory temp;
    late File audio;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('lyricforge-asr-smoke-');
      audio = File('${temp.path}${Platform.pathSeparator}real-song.wav');
      await audio.writeAsBytes(const [82, 73, 70, 70, 0, 0, 0, 0]);
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('prepares missing environment then persists a verified lyric project',
        () async {
      final repository = MemoryProjectRepository();
      final settings = _FakeSettingsStore();
      final runtime = _FakeRuntimeManager(ready: false);
      final workflow = _FakeWorkflow(
        repository: repository,
        produceLyrics: true,
      );
      final service = LocalAsrEndToEndSmokeTestService(
        projectRepository: repository,
        workflow: workflow,
        settingsStore: settings,
        runtimeManager: runtime,
      );

      final result = await service.run(audio.path);

      expect(runtime.installCalls, 1);
      expect(settings.saved, isNotNull);
      expect(workflow.transcribeCalls, 1);
      expect(result.environmentInstalled, isTrue);
      expect(result.lyricLineCount, 1);
      expect(result.projectName, 'real-song · ASR 自检');

      final project = await repository.getProjectById(result.projectId);
      expect(project, isNotNull);
      expect(project!.audioAsset!.originalPath, audio.absolute.path);
      expect(project.currentStage, ProcessingStage.transcriptionComplete);
      expect(project.status, ProjectStatus.editing);
      expect(project.hasLyrics, isTrue);
      expect(project.metadata['transcription'], isA<Map>());
      expect(
        (project.metadata['asrSmokeTest'] as Map)['status'],
        'passed',
      );
    });

    test('reuses a ready environment without reinstalling', () async {
      final repository = MemoryProjectRepository();
      final settings = _FakeSettingsStore(config: _configuredConfig);
      final runtime = _FakeRuntimeManager(ready: true);
      final workflow = _FakeWorkflow(
        repository: repository,
        produceLyrics: true,
      );
      final service = LocalAsrEndToEndSmokeTestService(
        projectRepository: repository,
        workflow: workflow,
        settingsStore: settings,
        runtimeManager: runtime,
      );

      final result = await service.run(audio.path);

      expect(runtime.installCalls, 0);
      expect(result.environmentInstalled, isFalse);
      expect(settings.saveCalls, 1);
    });

    test('fails closed when production workflow leaves no editable lyrics',
        () async {
      final repository = MemoryProjectRepository();
      final settings = _FakeSettingsStore(config: _configuredConfig);
      final runtime = _FakeRuntimeManager(ready: true);
      final workflow = _FakeWorkflow(
        repository: repository,
        produceLyrics: false,
      );
      final service = LocalAsrEndToEndSmokeTestService(
        projectRepository: repository,
        workflow: workflow,
        settingsStore: settings,
        runtimeManager: runtime,
      );

      await expectLater(
        service.run(audio.path),
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.message,
            'message',
            contains('没有生成可校对的完整歌词工程'),
          ),
        ),
      );

      final projects = await repository.getAllProjects();
      expect(projects, hasLength(1));
      expect(
        (projects.single.metadata['asrSmokeTest'] as Map)['status'],
        'failed',
      );
    });
  });
}

const _configuredConfig = TranscriptionConfig(
  mode: TranscriptionMode.highestQuality,
  profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
  qwenExecutable: 'C:/runtime/qwen3-asr.exe',
  whisperExecutable: 'C:/runtime/whisper-cli.exe',
  modelPath: 'C:/models/ggml-large-v3.bin',
  ffmpegExecutable: 'C:/runtime/ffmpeg.exe',
);

class _FakeSettingsStore implements TranscriptionSettingsStore {
  TranscriptionConfig? config;
  TranscriptionConfig? saved;
  int saveCalls = 0;

  _FakeSettingsStore({this.config});

  @override
  Future<TranscriptionConfig?> load() async => config;

  @override
  Future<void> save(TranscriptionConfig config) async {
    this.config = config;
    saved = config;
    saveCalls++;
  }

  @override
  Future<void> clear() async {
    config = null;
  }
}

class _FakeRuntimeManager implements AsrRuntimeManager {
  bool ready;
  int installCalls = 0;
  final StreamController<AsrRuntimeInstallProgress> _progress =
      StreamController<AsrRuntimeInstallProgress>.broadcast();

  _FakeRuntimeManager({required this.ready});

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => _progress.stream;

  @override
  bool get isInstalling => false;

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      _configuredConfig.copyWith(mode: config.mode);

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    return AsrRuntimeStatus(
      profile: ResolvedTranscriptionProfile(
        profile: TranscriptionProfilePreference.rtx5080HighQuality,
        label: 'RTX 5080 test profile',
        description: 'test',
        hardware: const TranscriptionHardwareInfo(
          operatingSystem: 'windows',
          architecture: 'x86_64',
          gpuName: 'NVIDIA GeForce RTX 5080',
        ),
        config: config,
      ),
      components: [
        AsrRuntimeComponentStatus(
          component: AsrRuntimeComponent.qwenRuntime,
          state: ready
              ? AsrRuntimeComponentState.ready
              : AsrRuntimeComponentState.missing,
          label: 'runtime',
          detail: ready ? 'ready' : 'missing',
        ),
      ],
      managedRoot: 'C:/managed',
    );
  }

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async {
    installCalls++;
    _progress.add(
      const AsrRuntimeInstallProgress(
        progress: 0.5,
        message: 'installing',
      ),
    );
    ready = true;
    return _configuredConfig.copyWith(mode: config.mode);
  }

  @override
  Future<void> cancel() async {}
}

class _FakeWorkflow implements ProjectTranscriptionWorkflow {
  final ProjectRepository repository;
  final bool produceLyrics;
  final StreamController<TranscriptionProgress> _progress =
      StreamController<TranscriptionProgress>.broadcast();

  bool _running = false;
  int transcribeCalls = 0;

  _FakeWorkflow({
    required this.repository,
    required this.produceLyrics,
  });

  @override
  Stream<TranscriptionProgress> get progressStream => _progress.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> transcribeProject(String projectId) async {
    transcribeCalls++;
    _running = true;
    try {
      _progress.add(
        const TranscriptionProgress(
          stage: TranscriptionStage.transcribing,
          progress: 0.7,
          message: 'transcribing',
        ),
      );
      final project = await repository.getProjectById(projectId);
      if (project == null) throw StateError('missing project');
      await repository.updateProject(
        project.copyWith(
          status: ProjectStatus.editing,
          currentStage: ProcessingStage.transcriptionComplete,
          lyricDocument: LyricDocument(
            language: 'en',
            lines: produceLyrics
                ? const [
                    LyricLine(
                      text: 'hello world',
                      startTime: Duration.zero,
                      endTime: Duration(seconds: 1),
                    ),
                  ]
                : const [],
          ),
          metadata: {
            ...project.metadata,
            'transcription': const {
              'backend': 'fake-production-workflow',
            },
          },
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
