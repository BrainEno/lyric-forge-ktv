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

const _config = TranscriptionConfig(
  mode: TranscriptionMode.whisperOnly,
  whisperExecutable: 'whisper',
  modelPath: 'model',
);
const _profile = ResolvedTranscriptionProfile(
  profile: TranscriptionProfilePreference.custom,
  label: 'test',
  description: 'test',
  hardware: TranscriptionHardwareInfo(
    operatingSystem: 'linux',
    architecture: 'x86_64',
  ),
  config: _config,
);

void main() {
  for (final hasLyrics in [false, true]) {
    test(
      'typed cancellation restores project with lyrics=$hasLyrics',
      () async {
        final root = await Directory.systemTemp.createTemp('workflow-cancel-');
        addTearDown(() => root.delete(recursive: true));
        final audio = File('${root.path}/song.wav');
        await audio.writeAsBytes([1]);
        final lyrics = hasLyrics
            ? LyricDocument(
                language: 'en',
                lines: [
                  LyricLine(
                    text: 'user edited',
                    startTime: Duration.zero,
                    endTime: const Duration(seconds: 1),
                  ),
                ],
                metadata: const {'edited': true},
              )
            : null;
        final now = DateTime.now();
        final repository = _Repository(
          ProjectManifest(
            id: 'p',
            name: 'Song',
            createdAt: now,
            updatedAt: now,
            status: hasLyrics ? ProjectStatus.editing : ProjectStatus.draft,
            currentStage: hasLyrics
                ? ProcessingStage.lyricsEdited
                : ProcessingStage.audioImported,
            audioAsset: AudioAsset(originalPath: audio.path, format: 'wav'),
            projectDirectory: root.path,
            lyricDocument: lyrics,
            metadata: const {'unrelated': 'preserved'},
          ),
        );
        const error = TranscriptionException.cancelled(
          'stopped for any reason',
        );
        final workflow = _workflow(repository, error);
        await expectLater(
          workflow.transcribeProject('p'),
          throwsA(same(error)),
        );
        expect(repository.statuses, [
          ProjectStatus.transcribing,
          hasLyrics ? ProjectStatus.editing : ProjectStatus.draft,
        ]);
        expect(repository.project.lyricDocument?.toJson(), lyrics?.toJson());
        expect(
          repository.project.currentStage,
          hasLyrics
              ? ProcessingStage.lyricsEdited
              : ProcessingStage.audioImported,
        );
        expect(repository.project.metadata, {'unrelated': 'preserved'});
        if (hasLyrics) {
          final backups = Directory('${root.path}/transcription/backups');
          expect(await backups.list().length, 1);
        }
      },
    );
  }

  test('unknown error with cancellation text remains a failure', () async {
    final root = await Directory.systemTemp.createTemp('workflow-unknown-');
    addTearDown(() => root.delete(recursive: true));
    final audio = File('${root.path}/song.wav');
    await audio.writeAsBytes([1]);
    final now = DateTime.now();
    final repository = _Repository(
      ProjectManifest(
        id: 'p',
        name: 'Song',
        createdAt: now,
        updatedAt: now,
        audioAsset: AudioAsset(originalPath: audio.path, format: 'wav'),
        projectDirectory: root.path,
      ),
    );
    const error = TranscriptionException('歌词识别已取消');
    await expectLater(
      _workflow(repository, error).transcribeProject('p'),
      throwsA(same(error)),
    );
    expect(repository.project.status, ProjectStatus.error);
    expect(
      (repository.project.metadata['transcriptionError'] as Map)['kind'],
      'unknown',
    );
  });
}

LocalProjectTranscriptionWorkflow _workflow(
  _Repository repository,
  TranscriptionException error,
) => LocalProjectTranscriptionWorkflow(
  projectRepository: repository,
  transcriptionService: _Service(error),
  settingsStore: _Settings(),
  profileResolver: _Resolver(),
  runtimeManager: _Runtime(),
  mediaMetadataRepository: _UnusedMetadata(),
  playbackSession: _UnusedPlayback(),
  pathCanonicalizer: _UnusedCanonicalizer(),
);

class _Repository implements ProjectRepository {
  ProjectManifest project;
  final statuses = <ProjectStatus>[];
  _Repository(this.project);
  @override
  Future<ProjectManifest?> getProjectById(String id) async => project;
  @override
  Future<ProjectManifest> updateProject(ProjectManifest value) async {
    project = value;
    statuses.add(value.status);
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service implements TranscriptionService {
  final TranscriptionException error;
  _Service(this.error);
  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async =>
      throw error;
  @override
  Stream<TranscriptionProgress> get progressStream => const Stream.empty();
  @override
  bool get isRunning => false;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

class _Settings implements TranscriptionSettingsStore {
  @override
  Future<TranscriptionConfig?> load() async => _config;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Resolver implements TranscriptionProfileResolver {
  @override
  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig config,
  ) async => _profile;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runtime implements AsrRuntimeManager {
  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      config;
  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async =>
      const AsrRuntimeStatus(
        profile: _profile,
        components: [],
        managedRoot: '',
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedMetadata implements LocalMediaMetadataRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPlayback implements PlaybackSessionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCanonicalizer implements AudioPathCanonicalizer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
