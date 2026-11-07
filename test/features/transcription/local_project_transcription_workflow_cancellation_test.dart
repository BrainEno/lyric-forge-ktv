import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_project_transcription_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

void main() {
  test(
    'cancellation preserves existing lyrics and restores editing state',
    () async {
      const lyrics = LyricDocument(
        language: 'en',
        lines: [
          LyricLine(
            text: 'existing lyric',
            startTime: Duration(seconds: 1),
            endTime: Duration(seconds: 2),
          ),
        ],
      );
      final harness = await _createHarness(
        lyrics: lyrics,
        status: ProjectStatus.ready,
        stage: ProcessingStage.transcriptionComplete,
        failure: const TranscriptionException.cancelled(
          'Stopped by a cancellation source with unrelated wording.',
        ),
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.workflow.transcribeProject(harness.projectId),
        throwsA(
          isA<TranscriptionException>()
              .having((error) => error.isCancelled, 'isCancelled', isTrue)
              .having(
                (error) => error.message,
                'message',
                'Stopped by a cancellation source with unrelated wording.',
              ),
        ),
      );

      final project = harness.repository.project;
      expect(project.status, ProjectStatus.editing);
      expect(project.currentStage, ProcessingStage.transcriptionComplete);
      expect(project.lyricDocument?.toJson(), lyrics.toJson());
      expect(project.metadata.containsKey('transcriptionError'), isFalse);
      expect(harness.transcription.calls, 1);
    },
  );

  test(
    'cancellation without lyrics restores the draft recognition state',
    () async {
      final harness = await _createHarness(
        status: ProjectStatus.draft,
        stage: ProcessingStage.audioImported,
        failure: const TranscriptionException.cancelled(
          'cancel request message can change',
        ),
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.workflow.transcribeProject(harness.projectId),
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.isCancelled,
            'isCancelled',
            isTrue,
          ),
        ),
      );

      final project = harness.repository.project;
      expect(project.status, ProjectStatus.draft);
      expect(project.currentStage, ProcessingStage.audioImported);
      expect(project.lyricDocument, isNull);
      expect(project.metadata.containsKey('transcriptionError'), isFalse);
    },
  );

  test(
    'cancellation-like text with unknown kind is an ordinary failure',
    () async {
      const lyrics = LyricDocument(
        language: 'en',
        lines: [
          LyricLine(
            text: 'keep this lyric',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
          ),
        ],
      );
      final harness = await _createHarness(
        lyrics: lyrics,
        status: ProjectStatus.editing,
        stage: ProcessingStage.lyricsEdited,
        failure: const TranscriptionException('歌词识别已取消'),
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.workflow.transcribeProject(harness.projectId),
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.isCancelled,
            'isCancelled',
            isFalse,
          ),
        ),
      );

      final project = harness.repository.project;
      expect(project.status, ProjectStatus.error);
      expect(project.currentStage, ProcessingStage.lyricsEdited);
      expect(project.lyricDocument?.toJson(), lyrics.toJson());
      expect(
        (project.metadata['transcriptionError'] as Map)['kind'],
        TranscriptionFailureKind.unknown.name,
      );
      expect(
        (project.metadata['transcriptionError'] as Map)['message'],
        '歌词识别已取消',
      );
    },
  );
}

Future<_WorkflowHarness> _createHarness({
  LyricDocument? lyrics,
  required ProjectStatus status,
  required ProcessingStage stage,
  required TranscriptionException failure,
}) async {
  final root = await Directory.systemTemp.createTemp(
    'project-transcription-cancel-',
  );
  final audio = File('${root.path}${Platform.pathSeparator}song.wav');
  await audio.writeAsBytes(const [82, 73, 70, 70]);
  final projectDirectory = Directory(
    '${root.path}${Platform.pathSeparator}project',
  );
  await projectDirectory.create(recursive: true);

  const config = TranscriptionConfig(
    whisperExecutable: 'whisper-cli',
    modelPath: 'whisper-model.bin',
  );
  const hardware = TranscriptionHardwareInfo(
    operatingSystem: 'test',
    architecture: 'test',
  );
  const profile = ResolvedTranscriptionProfile(
    profile: TranscriptionProfilePreference.custom,
    label: 'Test profile',
    description: 'Profile for cancellation regression tests.',
    hardware: hardware,
    config: config,
  );
  const runtimeStatus = AsrRuntimeStatus(
    profile: profile,
    managedRoot: 'test-runtime',
    components: [
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
  );

  final now = DateTime.utc(2026, 11, 7);
  final repository = _FakeProjectRepository(
    ProjectManifest(
      id: 'cancel-test-project',
      name: 'Cancellation test',
      createdAt: now,
      updatedAt: now,
      status: status,
      currentStage: stage,
      audioAsset: AudioAsset(originalPath: audio.path, format: 'wav'),
      lyricDocument: lyrics,
      projectDirectory: projectDirectory.path,
      metadata: const {'existingMetadata': 'preserve'},
    ),
  );
  final transcription = _ThrowingTranscriptionService(failure);
  final workflow = LocalProjectTranscriptionWorkflow(
    projectRepository: repository,
    transcriptionService: transcription,
    settingsStore: _FakeSettingsStore(config),
    profileResolver: _FakeProfileResolver(profile),
    runtimeManager: _FakeRuntimeManager(config, runtimeStatus),
    mediaMetadataRepository: _UnusedMetadataRepository(),
    playbackSession: _UnusedPlaybackSession(),
    pathCanonicalizer: _TestPathCanonicalizer(),
  );

  return _WorkflowHarness(
    root: root,
    projectId: repository.project.id,
    repository: repository,
    transcription: transcription,
    workflow: workflow,
  );
}

class _WorkflowHarness {
  final Directory root;
  final String projectId;
  final _FakeProjectRepository repository;
  final _ThrowingTranscriptionService transcription;
  final LocalProjectTranscriptionWorkflow workflow;

  const _WorkflowHarness({
    required this.root,
    required this.projectId,
    required this.repository,
    required this.transcription,
    required this.workflow,
  });

  Future<void> dispose() async {
    await transcription.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class _FakeProjectRepository implements ProjectRepository {
  ProjectManifest project;

  _FakeProjectRepository(this.project);

  @override
  Future<ProjectManifest?> getProjectById(String id) async =>
      id == project.id ? project : null;

  @override
  Future<ProjectManifest> updateProject(ProjectManifest next) async {
    project = next.copyWith(revision: project.revision + 1);
    return project;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingTranscriptionService implements TranscriptionService {
  final TranscriptionException failure;
  final StreamController<TranscriptionProgress> _progress =
      StreamController<TranscriptionProgress>.broadcast();
  int calls = 0;

  _ThrowingTranscriptionService(this.failure);

  @override
  Stream<TranscriptionProgress> get progressStream => _progress.stream;

  @override
  bool get isRunning => false;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    calls++;
    throw failure;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _progress.close();
}

class _FakeSettingsStore implements TranscriptionSettingsStore {
  final TranscriptionConfig config;

  const _FakeSettingsStore(this.config);

  @override
  Future<TranscriptionConfig?> load() async => config;

  @override
  Future<void> clear() async {}

  @override
  Future<void> save(TranscriptionConfig config) async {}
}

class _FakeProfileResolver implements TranscriptionProfileResolver {
  final ResolvedTranscriptionProfile profile;

  const _FakeProfileResolver(this.profile);

  @override
  Future<TranscriptionHardwareInfo> detectHardware() async => profile.hardware;

  @override
  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig config,
  ) async => profile;
}

class _FakeRuntimeManager implements AsrRuntimeManager {
  final TranscriptionConfig config;
  final AsrRuntimeStatus status;

  const _FakeRuntimeManager(this.config, this.status);

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => const Stream.empty();

  @override
  bool get isInstalling => false;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async => status;

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      this.config;

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async => this.config;

  @override
  Future<void> cancel() async {}
}

class _UnusedMetadataRepository implements LocalMediaMetadataRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPlaybackSession implements PlaybackSessionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPathCanonicalizer implements AudioPathCanonicalizer {
  @override
  String canonicalize(String path) => path;
}
