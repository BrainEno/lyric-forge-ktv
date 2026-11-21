import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_project_transcription_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_run_progress.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_separation_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_resource_coordinator.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/project_vocal_separator.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_vocal_check.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/vocal_activity_lyric_gate.dart';

const _config = TranscriptionConfig(
  mode: TranscriptionMode.whisperOnly,
  whisperExecutable: 'whisper',
  modelPath: 'model',
);

ResolvedTranscriptionProfile _profile(TranscriptionConfig config) =>
    ResolvedTranscriptionProfile(
      profile: TranscriptionProfilePreference.custom,
      label: 'test',
      description: 'test',
      hardware: const TranscriptionHardwareInfo(
        operatingSystem: 'windows',
        architecture: 'x86_64',
      ),
      config: config,
    );

void main() {
  test('recognises the separated vocal and links it to the project', () async {
    final fixture = await _Fixture.create();
    final stem = await fixture.writeStem('run-1');
    fixture.separator.result = (project) => ProjectVocalSeparation(
      VocalSeparationOutcome.separated(
        vocalPath: stem.path,
        provider: 'dml',
        elapsed: const Duration(seconds: 40),
        separatorRevision: 'htdemucs-ft-vocals-onnx-v1',
      ),
      updatedAudio: project.audioAsset!.copyWith(
        vocalPath: stem.path,
        metadata: {
          ...project.audioAsset!.metadata,
          VocalStemMarker.metadataKey: fixture.marker(stem.path).toJson(),
        },
      ),
    );
    final progress = <TranscriptionProgress>[];
    final workflow = fixture.workflow();
    final subscription = workflow.progressStream.listen(progress.add);
    addTearDown(subscription.cancel);

    await workflow.transcribeProject('p');

    expect(fixture.service.lastRequest?.inputAudioPath, stem.path);
    final saved = fixture.repository.project;
    expect(saved.status, ProjectStatus.editing);
    expect(saved.audioAsset?.vocalPath, stem.path);
    expect(
      VocalStemMarker.fromAudioMetadata(saved.audioAsset!.metadata)?.vocalPath,
      stem.path,
    );
    expect(saved.metadata.containsKey('activeTranscriptionRunId'), isFalse);
    final transcription = saved.metadata['transcription'] as Map;
    expect(transcription['inputPath'], stem.path);
    final separation = transcription['vocalSeparation'] as Map;
    expect(separation['status'], 'separated');
    expect(separation['provider'], 'dml');
    expect(saved.lyricDocument?.lines.single.text, 'ASR draft');

    // The separator ran inside the run, with the repaired configuration.
    expect(fixture.separator.calls, 1);
    expect(fixture.separator.lastWorkDirectory, endsWith('stems'));
    expect(fixture.separator.sawTranscribingStatus, isTrue);
    expect(progress.map((p) => p.message), contains('正在分离人声 50%'));
    expect(progress.map((p) => p.message), contains('已自动分离人声（GPU，40 秒）'));
    // D-049: separation is its own step of the run, before recognition.
    final half = progress.firstWhere((p) => p.message == '正在分离人声 50%');
    expect(half.step, TranscriptionRunStep.separating);
    expect(
      half.overall,
      closeTo(
        TranscriptionRunPlan.overallAt(TranscriptionRunStep.separating, 0.5),
        1e-9,
      ),
    );
    expect(progress.last.step, TranscriptionRunStep.saving);
  });

  test('a failed separation recognises the mix and says why', () async {
    final fixture = await _Fixture.create();
    fixture.separator.result = (_) => const ProjectVocalSeparation(
      VocalSeparationOutcome.failed(
        VocalSeparationFailure.separatorFailed,
        detail: 'exit 4',
      ),
    );
    await fixture.workflow().transcribeProject('p');

    final original = fixture.repository.project.audioAsset!.originalPath;
    expect(fixture.service.lastRequest?.inputAudioPath, original);
    expect(fixture.repository.project.audioAsset?.vocalPath, isNull);
    final transcription =
        fixture.repository.project.metadata['transcription'] as Map;
    expect(
      (transcription['vocalSeparation'] as Map)['failure'],
      'separatorFailed',
    );
    expect(fixture.repository.project.status, ProjectStatus.editing);
  });

  test('a stale automatic stem is not trusted when separation fails', () async {
    final fixture = await _Fixture.create();
    final stale = await fixture.writeStem('run-0');
    fixture.linkAutomaticStem(stale.path);
    fixture.separator.result = (_) => const ProjectVocalSeparation(
      VocalSeparationOutcome.failed(VocalSeparationFailure.installFailed),
    );
    await fixture.workflow().transcribeProject('p');
    expect(
      fixture.service.lastRequest?.inputAudioPath,
      fixture.repository.project.audioAsset!.originalPath,
    );
  });

  test('a reused stem is recognised without a project write', () async {
    final fixture = await _Fixture.create();
    final stem = await fixture.writeStem('run-2');
    fixture.linkAutomaticStem(stem.path);
    fixture.separator.result = (_) => ProjectVocalSeparation(
      VocalSeparationOutcome.reused(
        vocalPath: stem.path,
        separatorRevision: 'htdemucs-ft-vocals-onnx-v1',
      ),
    );
    await fixture.workflow().transcribeProject('p');
    expect(fixture.service.lastRequest?.inputAudioPath, stem.path);
    // Start write and final commit only.
    expect(fixture.repository.writes, 2);
  });

  test('an imported vocal is still preferred when separation skips', () async {
    final fixture = await _Fixture.create();
    final imported = File('${fixture.root.path}/我的人声.wav');
    await imported.writeAsBytes([1, 2, 3]);
    fixture.repository.project = fixture.repository.project.copyWith(
      audioAsset: fixture.repository.project.audioAsset!.copyWith(
        vocalPath: imported.path,
      ),
    );
    fixture.separator.result = (_) => const ProjectVocalSeparation(
      VocalSeparationOutcome.skipped(
        VocalSeparationSkipReason.userProvidedVocal,
      ),
    );
    await fixture.workflow().transcribeProject('p');
    expect(fixture.service.lastRequest?.inputAudioPath, imported.path);
  });

  group('without a separator', () {
    test('an automatic stem is used while separation is on', () async {
      final fixture = await _Fixture.create();
      final stem = await fixture.writeStem('run-3');
      fixture.linkAutomaticStem(stem.path);
      await fixture.workflow(withSeparator: false).transcribeProject('p');
      expect(fixture.service.lastRequest?.inputAudioPath, stem.path);
      final transcription =
          fixture.repository.project.metadata['transcription'] as Map;
      expect(transcription['vocalSeparation'], isNull);
    });

    test('switching separation off returns to the mix', () async {
      final fixture = await _Fixture.create();
      final stem = await fixture.writeStem('run-4');
      fixture.linkAutomaticStem(stem.path);
      fixture.settings.config = _config.copyWith(
        vocalSeparation: VocalSeparationPreference.off,
      );
      await fixture.workflow(withSeparator: false).transcribeProject('p');
      expect(
        fixture.service.lastRequest?.inputAudioPath,
        fixture.repository.project.audioAsset!.originalPath,
      );
    });

    test('without a separator the run never reports separating', () async {
      final fixture = await _Fixture.create();
      final workflow = fixture.workflow(withSeparator: false);
      final progress = <TranscriptionProgress>[];
      final subscription = workflow.progressStream.listen(progress.add);
      addTearDown(subscription.cancel);

      await workflow.transcribeProject('p');

      expect(
        progress.map((p) => p.step),
        isNot(contains(TranscriptionRunStep.separating)),
      );
      expect(progress.map((p) => p.message), contains('正在启动识别引擎'));
    });
  });

  test(
    'cancelling during separation stops it and restores the project',
    () async {
      final fixture = await _Fixture.create();
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.separator.onSeparate = () async {
        entered.complete();
        await release.future;
      };
      fixture.separator.onCancel = () async {
        if (!release.isCompleted) release.complete();
      };
      fixture.separator.result = (_) => const ProjectVocalSeparation(
        VocalSeparationOutcome.skipped(VocalSeparationSkipReason.disabled),
      );
      final workflow = fixture.workflow();
      final run = workflow.transcribeProject('p');
      await entered.future;
      await workflow.cancel();

      await expectLater(
        run,
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.kind,
            'kind',
            TranscriptionFailureKind.cancelled,
          ),
        ),
      );
      expect(fixture.separator.cancels, 1);
      expect(fixture.service.lastRequest, isNull);
      expect(fixture.service.cancelCalls, 0);
      expect(fixture.repository.project.status, ProjectStatus.editing);
      expect(
        fixture.repository.project.metadata.containsKey(
          'activeTranscriptionRunId',
        ),
        isFalse,
      );
      expect(workflow.isRunning, isFalse);
    },
  );

  group('vocal check (D-044)', () {
    ProjectVocalSeparation separated(
      _Fixture fixture,
      ProjectManifest project,
      String vocalPath,
    ) => ProjectVocalSeparation(
      VocalSeparationOutcome.separated(
        vocalPath: vocalPath,
        provider: 'dml',
        elapsed: const Duration(seconds: 30),
        separatorRevision: 'htdemucs-ft-vocals-onnx-v1',
      ),
      updatedAudio: project.audioAsset!.copyWith(
        vocalPath: vocalPath,
        metadata: {
          ...project.audioAsset!.metadata,
          VocalStemMarker.metadataKey: fixture.marker(vocalPath).toJson(),
        },
      ),
    );

    test('checks a draft recognised from the separated vocal', () async {
      final fixture = await _Fixture.create();
      final stem = await fixture.writeStem('run-6');
      fixture.separator.result = (project) =>
          separated(fixture, project, stem.path);
      final check = _VocalCheck();
      await fixture.workflow(vocalCheck: check).transcribeProject('p');

      expect(check.calls, 1);
      // Recognition's own 16 kHz copy first, the stem as a fallback.
      expect(check.lastPaths, ['normalized.wav', stem.path]);
      final saved = fixture.repository.project;
      expect(saved.lyricDocument?.lines.single.text, 'checked draft');
      final transcription = saved.metadata['transcription'] as Map;
      final report = transcription['vocalCheck'] as Map;
      // Whatever the check reports is stored as is.
      expect(report['applied'], isFalse);
      expect(report['skipReason'], 'noLines');
      // The editable-draft markers are merged on top of the checked draft.
      expect(saved.lyricDocument?.metadata['checkedBy'], 'fake');
      expect(saved.lyricDocument?.metadata['editableDraft'], isTrue);
    });

    test('a reused automatic stem is checked as well', () async {
      final fixture = await _Fixture.create();
      final stem = await fixture.writeStem('run-7');
      fixture.linkAutomaticStem(stem.path);
      fixture.separator.result = (_) => ProjectVocalSeparation(
        VocalSeparationOutcome.reused(
          vocalPath: stem.path,
          separatorRevision: 'htdemucs-ft-vocals-onnx-v1',
        ),
      );
      final check = _VocalCheck();
      await fixture.workflow(vocalCheck: check).transcribeProject('p');
      expect(check.calls, 1);
    });

    test('an imported vocal is checked as well', () async {
      final fixture = await _Fixture.create();
      final imported = File('${fixture.root.path}/我的人声.wav');
      await imported.writeAsBytes([1, 2, 3]);
      fixture.repository.project = fixture.repository.project.copyWith(
        audioAsset: fixture.repository.project.audioAsset!.copyWith(
          vocalPath: imported.path,
        ),
      );
      fixture.separator.result = (_) => const ProjectVocalSeparation(
        VocalSeparationOutcome.skipped(
          VocalSeparationSkipReason.userProvidedVocal,
        ),
      );
      final check = _VocalCheck();
      await fixture.workflow(vocalCheck: check).transcribeProject('p');
      expect(check.calls, 1);
      expect(check.lastPaths?.last, imported.path);
    });

    test('a draft recognised from the mix is not checked', () async {
      final fixture = await _Fixture.create();
      fixture.separator.result = (_) => const ProjectVocalSeparation(
        VocalSeparationOutcome.failed(VocalSeparationFailure.separatorFailed),
      );
      final check = _VocalCheck();
      await fixture.workflow(vocalCheck: check).transcribeProject('p');

      expect(check.calls, 0);
      final saved = fixture.repository.project;
      expect(saved.lyricDocument?.lines.single.text, 'ASR draft');
      final report =
          (saved.metadata['transcription'] as Map)['vocalCheck'] as Map;
      expect(report['applied'], isFalse);
      expect(report['skipReason'], 'notVocalInput');
    });

    test('without a configured check nothing is recorded', () async {
      final fixture = await _Fixture.create();
      final stem = await fixture.writeStem('run-8');
      fixture.separator.result = (project) =>
          separated(fixture, project, stem.path);
      await fixture.workflow().transcribeProject('p');
      final transcription =
          fixture.repository.project.metadata['transcription'] as Map;
      expect(transcription.containsKey('vocalCheck'), isTrue);
      expect(transcription['vocalCheck'], isNull);
      expect(
        fixture.repository.project.lyricDocument?.lines.single.text,
        'ASR draft',
      );
    });

    test('a throwing check keeps the recognised draft', () async {
      final fixture = await _Fixture.create();
      final stem = await fixture.writeStem('run-9');
      fixture.separator.result = (project) =>
          separated(fixture, project, stem.path);
      final check = _VocalCheck()..error = StateError('broken');
      await fixture.workflow(vocalCheck: check).transcribeProject('p');

      final saved = fixture.repository.project;
      expect(saved.status, ProjectStatus.editing);
      expect(saved.lyricDocument?.lines.single.text, 'ASR draft');
      final report =
          (saved.metadata['transcription'] as Map)['vocalCheck'] as Map;
      expect(report['skipReason'], 'failed');
      expect(report['error'], contains('broken'));
    });

    test('cancelling during the check commits nothing', () async {
      final fixture = await _Fixture.create();
      final stem = await fixture.writeStem('run-10');
      fixture.separator.result = (project) =>
          separated(fixture, project, stem.path);
      final entered = Completer<void>();
      final release = Completer<void>();
      final check = _VocalCheck()
        ..onCheck = () async {
          entered.complete();
          await release.future;
        };
      final workflow = fixture.workflow(vocalCheck: check);
      final run = workflow.transcribeProject('p');
      await entered.future;
      final cancelling = workflow.cancel();
      release.complete();
      await cancelling;

      await expectLater(
        run,
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.kind,
            'kind',
            TranscriptionFailureKind.cancelled,
          ),
        ),
      );
      expect(fixture.repository.project.lyricDocument, isNull);
      expect(fixture.repository.project.status, ProjectStatus.editing);
    });
  });

  test('a project edit during separation aborts before recognition', () async {
    final fixture = await _Fixture.create();
    final stem = await fixture.writeStem('run-5');
    fixture.separator.onSeparate = () async {
      // The user renames the song while the separator runs.
      final current = fixture.repository.project;
      fixture.repository.project = current.copyWith(
        name: 'Renamed',
        revision: current.revision + 1,
      );
    };
    fixture.separator.result = (project) => ProjectVocalSeparation(
      VocalSeparationOutcome.separated(
        vocalPath: stem.path,
        provider: 'cpu',
        elapsed: const Duration(seconds: 90),
        separatorRevision: 'htdemucs-ft-vocals-onnx-v1',
      ),
      updatedAudio: project.audioAsset!.copyWith(vocalPath: stem.path),
    );
    await expectLater(
      fixture.workflow().transcribeProject('p'),
      throwsA(isA<TranscriptionException>()),
    );
    expect(fixture.service.lastRequest, isNull);
    expect(fixture.repository.project.name, 'Renamed');
    expect(fixture.repository.project.audioAsset?.vocalPath, isNull);
  });
}

class _Fixture {
  _Fixture(this.root, this.repository);

  final Directory root;
  final _Repository repository;
  final service = _Service();
  final settings = _Settings();
  final separator = _Separator();

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('workflow-separation-');
    addTearDown(() => root.delete(recursive: true));
    final audio = File('${root.path}/song.wav');
    await audio.writeAsBytes([1]);
    final now = DateTime.now();
    return _Fixture(
      root,
      _Repository(
        ProjectManifest(
          id: 'p',
          name: 'Song',
          createdAt: now,
          updatedAt: now,
          status: ProjectStatus.editing,
          audioAsset: AudioAsset(originalPath: audio.path, format: 'wav'),
          projectDirectory: root.path,
        ),
      ),
    );
  }

  Future<File> writeStem(String run) async {
    final file = File('${root.path}/stems/$run/vocals.wav');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(100, 1));
    return file;
  }

  VocalStemMarker marker(String vocalPath) => VocalStemMarker(
    separatorRevision: 'htdemucs-ft-vocals-onnx-v1',
    sourceFingerprint: 'fingerprint',
    vocalPath: vocalPath,
    provider: 'dml',
    generatedAt: DateTime.utc(2026, 11, 18),
  );

  void linkAutomaticStem(String vocalPath) {
    final audio = repository.project.audioAsset!;
    repository.project = repository.project.copyWith(
      audioAsset: audio.copyWith(
        vocalPath: vocalPath,
        metadata: {
          ...audio.metadata,
          VocalStemMarker.metadataKey: marker(vocalPath).toJson(),
        },
      ),
    );
  }

  LocalProjectTranscriptionWorkflow workflow({
    bool withSeparator = true,
    TranscriptionVocalCheck? vocalCheck,
  }) {
    separator.repository = repository;
    return LocalProjectTranscriptionWorkflow(
      projectRepository: repository,
      transcriptionService: service,
      settingsStore: settings,
      profileResolver: _Resolver(),
      runtimeManager: _Runtime(),
      resources: AsrResourceCoordinator(),
      mediaMetadataRepository: _UnusedMetadata(),
      playbackSession: _UnusedPlayback(),
      pathCanonicalizer: _UnusedCanonicalizer(),
      vocalSeparator: withSeparator ? separator : null,
      vocalCheck: vocalCheck,
    );
  }
}

class _VocalCheck implements TranscriptionVocalCheck {
  int calls = 0;
  List<String>? lastPaths;
  Object? error;
  Future<void> Function()? onCheck;

  @override
  Future<VocalCheckResult> check(
    LyricDocument draft, {
    required List<String> audioPaths,
  }) async {
    calls++;
    lastPaths = audioPaths;
    await onCheck?.call();
    final failure = error;
    if (failure != null) throw failure;
    return VocalCheckResult(
      draft.copyWith(
        lines: const [
          LyricLine(
            text: 'checked draft',
            startTime: Duration(milliseconds: 100),
            endTime: Duration(milliseconds: 900),
          ),
        ],
        metadata: {...draft.metadata, 'checkedBy': 'fake'},
      ),
      const VocalCheckReport.skipped(VocalCheckSkipReason.noLines),
    );
  }
}

class _Separator implements ProjectVocalSeparator {
  ProjectVocalSeparation Function(ProjectManifest project) result = (_) =>
      const ProjectVocalSeparation(
        VocalSeparationOutcome.skipped(VocalSeparationSkipReason.disabled),
      );
  Future<void> Function()? onSeparate;
  Future<void> Function()? onCancel;
  _Repository? repository;
  int calls = 0;
  int cancels = 0;
  String? lastWorkDirectory;
  bool sawTranscribingStatus = false;

  @override
  Future<ProjectVocalSeparation> separate(
    ProjectManifest project, {
    required TranscriptionConfig config,
    required String workDirectory,
    required void Function(TranscriptionProgress progress) onProgress,
  }) async {
    calls++;
    lastWorkDirectory = workDirectory;
    sawTranscribingStatus =
        repository?.project.status == ProjectStatus.transcribing;
    onProgress(
      const TranscriptionProgress(
        stage: TranscriptionStage.preprocessing,
        progress: 0.5,
        message: '正在分离人声 50%',
      ),
    );
    await onSeparate?.call();
    return result(project);
  }

  @override
  Future<void> cancel() async {
    cancels++;
    await onCancel?.call();
  }
}

class _Repository implements ProjectRepository {
  _Repository(this.project);

  ProjectManifest project;
  int writes = 0;

  @override
  Future<ProjectManifest?> getProjectById(String id) async => project;

  @override
  Future<ProjectManifest> updateProject(ProjectManifest value) async {
    writes++;
    project = value.copyWith(revision: project.revision + 1);
    return project;
  }

  @override
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest value, {
    required int expectedRevision,
  }) async {
    if (project.revision != expectedRevision) {
      throw ProjectUpdateConflictException(currentProject: project);
    }
    return updateProject(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service implements TranscriptionService {
  final _progress = StreamController<TranscriptionProgress>.broadcast();
  TranscriptionRequest? lastRequest;
  int cancelCalls = 0;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    lastRequest = request;
    return const TranscriptionResult(
      lyrics: LyricDocument(
        language: 'en',
        lines: [
          LyricLine(
            text: 'ASR draft',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
          ),
        ],
      ),
      normalizedAudioPath: 'normalized.wav',
      rawJsonPath: 'raw.json',
      detectedLanguage: 'en',
    );
  }

  @override
  late final Stream<TranscriptionProgress> progressStream = _progress.stream;
  @override
  bool get isRunning => false;
  @override
  Future<void> cancel() async => cancelCalls++;
  @override
  Future<void> dispose() async {}
}

class _Settings implements TranscriptionSettingsStore {
  TranscriptionConfig config = _config;

  @override
  Future<TranscriptionConfig?> load() async => config;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Resolver implements TranscriptionProfileResolver {
  @override
  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig config,
  ) async => _profile(config);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runtime implements AsrRuntimeManager {
  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      config;
  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async =>
      AsrRuntimeStatus(
        profile: _profile(config),
        components: const [],
        managedRoot: '',
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedMetadata implements LocalMediaMetadataRepository {
  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async => null;
  @override
  Future<LocalMediaMetadata> save(LocalMediaMetadata metadata) async =>
      metadata;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPlayback implements PlaybackSessionService {
  @override
  PlaybackSessionState get currentState => const PlaybackSessionState();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCanonicalizer implements AudioPathCanonicalizer {
  @override
  String canonicalize(String path) => path;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
