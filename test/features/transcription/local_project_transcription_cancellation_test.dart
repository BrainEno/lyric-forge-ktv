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
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_resource_coordinator.dart';
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
  test('transcription request prefers an existing imported vocal stem', () async {
    final repository = await _createRepository();
    final vocal = File('${repository.project.projectDirectory}/人声.wav');
    await vocal.writeAsBytes([1, 2, 3]);
    repository.project = repository.project.copyWith(
      audioAsset: repository.project.audioAsset!.copyWith(vocalPath: vocal.path),
    );
    final service = _Service(null, null);
    await _workflow(repository, null, service: service).transcribeProject('p');
    expect(service.lastRequest?.inputAudioPath, vocal.path);
  });

  test('missing vocal stem falls back to the original audio', () async {
    final repository = await _createRepository();
    final original = repository.project.audioAsset!.originalPath;
    repository.project = repository.project.copyWith(
      audioAsset: repository.project.audioAsset!.copyWith(vocalPath: '${repository.project.projectDirectory}/missing.wav'),
    );
    final service = _Service(null, null);
    await _workflow(repository, null, service: service).transcribeProject('p');
    expect(service.lastRequest?.inputAudioPath, original);
  });

  test(
    'shared lease excludes other workflows and releases on preparation cancellation',
    () async {
      final repository = await _createRepository();
      final resources = AsrResourceCoordinator();
      final entered = Completer<void>();
      final release = Completer<void>();
      final first = _workflow(
        repository,
        null,
        resources: resources,
        onSettingsLoad: () async {
          entered.complete();
          await release.future;
        },
      );
      final secondService = _Service(null, null);
      final second = _workflow(
        repository,
        null,
        resources: resources,
        service: secondService,
      );
      final operation = first.transcribeProject('p');
      final cancelled = expectLater(
        operation,
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.kind,
            'kind',
            TranscriptionFailureKind.cancelled,
          ),
        ),
      );
      await entered.future;
      expect(first.isRunning, isTrue);
      expect(resources.activeUse, AsrResourceUse.transcription);
      await expectLater(
        second.transcribeProject('p'),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.kind,
            'kind',
            TranscriptionFailureKind.busy,
          ),
        ),
      );
      await second.cancel();
      expect(secondService.cancelCalls, 0);
      await first.cancel();
      expect(resources.activeUse, AsrResourceUse.transcription);
      release.complete();
      await cancelled;
      expect(first.isRunning, isFalse);
      expect(resources.activeUse, isNull);
      expect(repository.statuses, isEmpty);
      expect(repository.project.lyricDocument!.lines.single.text, 'original');
      await second.transcribeProject('p');
      expect(resources.activeUse, isNull);
    },
  );

  test(
    'cancellation during start write restores the project before release',
    () async {
      final repository = await _createRepository();
      final resources = AsrResourceCoordinator();
      final entered = Completer<void>();
      final release = Completer<void>();
      repository.beforeConditionalWrite = (_, value) async {
        if (value.status == ProjectStatus.transcribing) {
          entered.complete();
          await release.future;
        }
      };
      final service = _Service(null, null);
      final workflow = _workflow(
        repository,
        null,
        resources: resources,
        service: service,
      );
      final operation = workflow.transcribeProject('p');
      final cancelled = expectLater(
        operation,
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.kind,
            'kind',
            TranscriptionFailureKind.cancelled,
          ),
        ),
      );
      await entered.future;
      await workflow.cancel();
      release.complete();
      await cancelled;
      expect(repository.project.status, ProjectStatus.editing);
      expect(
        repository.project.metadata.containsKey('activeTranscriptionRunId'),
        isFalse,
      );
      expect(repository.project.lyricDocument!.lines.single.text, 'original');
      expect(service.cancelCalls, 0);
      expect(resources.activeUse, isNull);
    },
  );

  test(
    'lease waits for in-flight engine cancellation before another run',
    () async {
      final repository = await _createRepository();
      final resources = AsrResourceCoordinator();
      final entered = Completer<void>();
      final inferenceDone = Completer<void>();
      final cancelDone = Completer<void>();
      final service = _Service(null, () async {
        entered.complete();
        await inferenceDone.future;
      });
      service.onCancel = () async {
        await cancelDone.future;
      };
      final workflow = _workflow(
        repository,
        null,
        resources: resources,
        service: service,
      );
      final operation = workflow.transcribeProject('p');
      final cancelled = expectLater(
        operation,
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.kind,
            'kind',
            TranscriptionFailureKind.cancelled,
          ),
        ),
      );
      await entered.future;
      final other = _workflow(
        repository,
        null,
        resources: resources,
        service: service,
      );
      await other.cancel();
      expect(service.cancelCalls, 0);
      await expectLater(
        other.transcribeProject('p'),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.kind,
            'kind',
            TranscriptionFailureKind.busy,
          ),
        ),
      );
      await other.cancel();
      expect(service.cancelCalls, 0);
      final cancel = workflow.cancel();
      expect(service.cancelCalls, 1);
      inferenceDone.complete();
      await Future<void>.delayed(Duration.zero);
      expect(resources.activeUse, AsrResourceUse.transcription);
      expect(resources.tryAcquire(AsrResourceUse.independentRerun), isNull);
      cancelDone.complete();
      await cancel;
      await cancelled;
      expect(resources.activeUse, isNull);
      expect(repository.project.lyricDocument!.lines.single.text, 'original');
      expect(
        repository.project.metadata.containsKey('activeTranscriptionRunId'),
        isFalse,
      );
    },
  );

  test('saving is non-cancellable and holds lease until completion', () async {
    final repository = await _createRepository();
    final resources = AsrResourceCoordinator();
    final entered = Completer<void>();
    final release = Completer<void>();
    repository.beforeConditionalWrite = (_, value) async {
      if (value.currentStage == ProcessingStage.transcriptionComplete) {
        entered.complete();
        await release.future;
      }
    };
    final service = _Service(null, null);
    final workflow = _workflow(
      repository,
      null,
      resources: resources,
      service: service,
    );
    final operation = workflow.transcribeProject('p');
    await entered.future;
    await workflow.cancel();
    expect(service.cancelCalls, 0);
    expect(resources.activeUse, AsrResourceUse.transcription);
    release.complete();
    await operation;
    expect(resources.activeUse, isNull);
    expect(repository.project.lyricDocument!.lines.single.text, 'ASR draft');
  });

  for (final originalStatus in [
    ProjectStatus.draft,
    ProjectStatus.editing,
    ProjectStatus.ready,
  ]) {
    test('typed cancellation restores $originalStatus', () async {
      final hasLyrics = originalStatus != ProjectStatus.draft;
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
                  id: 'edited-line',
                  startTime: Duration.zero,
                  endTime: const Duration(seconds: 1),
                ),
              ],
              metadata: const {
                'manuallyEditedLineIds': ['edited-line'],
                'timingProvenance': {'edited-line': 'manual'},
              },
            )
          : null;
      final now = DateTime.now();
      final repository = _Repository(
        ProjectManifest(
          id: 'p',
          name: 'Song',
          createdAt: now,
          updatedAt: now,
          status: originalStatus,
          currentStage: hasLyrics
              ? ProcessingStage.lyricsEdited
              : ProcessingStage.audioImported,
          audioAsset: AudioAsset(originalPath: audio.path, format: 'wav'),
          projectDirectory: root.path,
          lyricDocument: lyrics,
          metadata: const {'unrelated': 'preserved'},
        ),
      );
      const error = TranscriptionException.cancelled('stopped for any reason');
      final workflow = _workflow(repository, error);
      await expectLater(workflow.transcribeProject('p'), throwsA(same(error)));
      expect(repository.statuses, [ProjectStatus.transcribing, originalStatus]);
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
    });
  }

  test('ready cancellation preserves newer lyrics and project data', () async {
    final root = await Directory.systemTemp.createTemp(
      'workflow-ready-cancel-',
    );
    addTearDown(() => root.delete(recursive: true));
    final audio = File('${root.path}/song.wav');
    await audio.writeAsBytes([1]);
    final now = DateTime.now();
    const originalLyrics = LyricDocument(
      language: 'en',
      lines: [
        LyricLine(
          text: 'original',
          id: 'line',
          startTime: Duration.zero,
          endTime: Duration(seconds: 1),
        ),
      ],
    );
    const latestLyrics = LyricDocument(
      language: 'en',
      lines: [
        LyricLine(
          text: 'new manual edit',
          id: 'line',
          startTime: Duration.zero,
          endTime: Duration(seconds: 1),
        ),
      ],
      metadata: {
        'manuallyEditedLineIds': ['line'],
      },
    );
    final repository = _Repository(
      ProjectManifest(
        id: 'p',
        name: 'Song',
        createdAt: now,
        updatedAt: now,
        status: ProjectStatus.ready,
        currentStage: ProcessingStage.exported,
        audioAsset: AudioAsset(originalPath: audio.path, format: 'wav'),
        projectDirectory: root.path,
        lyricDocument: originalLyrics,
        metadata: const {'unrelated': 'original'},
      ),
    );
    const error = TranscriptionException.cancelled('stop');
    final workflow = _workflow(
      repository,
      error,
      onTranscribe: () async {
        await repository.updateProject(
          repository.project.copyWith(
            lyricDocument: latestLyrics,
            currentStage: ProcessingStage.lyricsEdited,
            metadata: {...repository.project.metadata, 'unrelated': 'newer'},
          ),
        );
      },
    );
    await expectLater(workflow.transcribeProject('p'), throwsA(same(error)));
    expect(repository.project.status, ProjectStatus.ready);
    expect(repository.project.lyricDocument?.toJson(), latestLyrics.toJson());
    expect(repository.project.currentStage, ProcessingStage.lyricsEdited);
    expect(repository.project.metadata, {'unrelated': 'newer'});
  });

  test(
    'successful recognition commits the draft and clears its run marker',
    () async {
      final repository = await _createRepository();
      await _workflow(repository, null).transcribeProject('p');
      expect(repository.project.lyricDocument!.lines.single.text, 'ASR draft');
      expect(repository.project.status, ProjectStatus.editing);
      expect(
        repository.project.currentStage,
        ProcessingStage.transcriptionComplete,
      );
      expect(
        repository.project.metadata.containsKey('activeTranscriptionRunId'),
        isFalse,
      );
    },
  );

  test('project edit during preparation prevents stale start write', () async {
    final repository = await _createRepository();
    var called = false;
    final workflow = _workflow(
      repository,
      null,
      onSettingsLoad: () async {
        await repository.updateProject(
          repository.project.copyWith(
            name: 'Renamed during setup',
            lyricDocument: _manualLyrics,
          ),
        );
      },
      onTranscribe: () async {
        called = true;
      },
    );
    await expectLater(
      workflow.transcribeProject('p'),
      throwsA(
        isA<TranscriptionException>().having(
          (e) => e.message,
          'message',
          contains('准备期间'),
        ),
      ),
    );
    expect(called, isFalse);
    expect(repository.project.name, 'Renamed during setup');
    expect(repository.project.lyricDocument!.toJson(), _manualLyrics.toJson());
    expect(
      repository.project.metadata.containsKey('activeTranscriptionRunId'),
      isFalse,
    );
  });

  test('manual edit during recognition is not replaced by the draft', () async {
    final repository = await _createRepository();
    final workflow = _workflow(
      repository,
      null,
      onTranscribe: () async {
        await repository.updateProject(
          repository.project.copyWith(
            lyricDocument: _manualLyrics,
            currentStage: ProcessingStage.lyricsEdited,
            metadata: {...repository.project.metadata, 'unrelated': 'new'},
          ),
        );
      },
    );
    await expectLater(
      workflow.transcribeProject('p'),
      throwsA(
        isA<TranscriptionException>().having(
          (e) => e.message,
          'message',
          contains('未覆盖最新歌词'),
        ),
      ),
    );
    expect(repository.project.lyricDocument!.toJson(), _manualLyrics.toJson());
    expect(repository.project.currentStage, ProcessingStage.lyricsEdited);
    expect(repository.project.status, ProjectStatus.editing);
    expect(repository.project.metadata['unrelated'], 'new');
    expect(
      repository.project.metadata.containsKey('activeTranscriptionRunId'),
      isFalse,
    );
  });

  test(
    'conditional result save rejects a concurrent edit after the read',
    () async {
      final repository = await _createRepository();
      var injected = false;
      repository.beforeConditionalWrite = (repo, candidate) async {
        if (!injected &&
            candidate.lyricDocument?.lines.first.text == 'ASR draft') {
          injected = true;
          await repo.updateProject(
            repo.project.copyWith(lyricDocument: _manualLyrics),
          );
        }
      };
      await expectLater(
        _workflow(repository, null).transcribeProject('p'),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('未覆盖最新歌词'),
          ),
        ),
      );
      expect(injected, isTrue);
      expect(
        repository.project.lyricDocument!.toJson(),
        _manualLyrics.toJson(),
      );
      expect(
        repository.project.metadata.containsKey('activeTranscriptionRunId'),
        isFalse,
      );
    },
  );

  test('conflict cleanup never overwrites another concurrent edit', () async {
    final repository = await _createRepository();
    var injected = false;
    repository.beforeConditionalWrite = (repo, candidate) async {
      if (!injected &&
          candidate.status == ProjectStatus.editing &&
          candidate.lyricDocument?.lines.first.text == 'new manual edit') {
        injected = true;
        await repo.updateProject(
          repo.project.copyWith(name: 'latest concurrent name'),
        );
      }
    };
    final workflow = _workflow(
      repository,
      null,
      onTranscribe: () async {
        await repository.updateProject(
          repository.project.copyWith(lyricDocument: _manualLyrics),
        );
      },
    );
    await expectLater(
      workflow.transcribeProject('p'),
      throwsA(isA<TranscriptionException>()),
    );
    expect(injected, isTrue);
    expect(repository.project.name, 'latest concurrent name');
    expect(repository.project.lyricDocument!.toJson(), _manualLyrics.toJson());
  });

  test('conflict cleanup does not touch a different run owner', () async {
    final repository = await _createRepository();
    final workflow = _workflow(
      repository,
      null,
      onTranscribe: () async {
        await repository.updateProject(
          repository.project.copyWith(
            lyricDocument: _manualLyrics,
            metadata: {
              ...repository.project.metadata,
              'activeTranscriptionRunId': 'other-run',
            },
          ),
        );
      },
    );
    await expectLater(
      workflow.transcribeProject('p'),
      throwsA(isA<TranscriptionException>()),
    );
    expect(repository.project.lyricDocument!.toJson(), _manualLyrics.toJson());
    expect(
      repository.project.metadata['activeTranscriptionRunId'],
      'other-run',
    );
    expect(repository.project.status, ProjectStatus.transcribing);
  });

  test('missing run marker prevents unsafe cleanup', () async {
    final repository = await _createRepository();
    final workflow = _workflow(
      repository,
      null,
      onTranscribe: () async {
        await repository.updateProject(
          repository.project.copyWith(
            lyricDocument: _manualLyrics,
            metadata: const {'unrelated': 'newer'},
          ),
        );
      },
    );
    await expectLater(
      workflow.transcribeProject('p'),
      throwsA(isA<TranscriptionException>()),
    );
    expect(repository.project.lyricDocument!.toJson(), _manualLyrics.toJson());
    expect(repository.project.metadata, {'unrelated': 'newer'});
    expect(repository.project.status, ProjectStatus.transcribing);
  });

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

const _manualLyrics = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: 'new manual edit',
      id: 'edited',
      startTime: Duration.zero,
      endTime: Duration(seconds: 1),
    ),
  ],
  metadata: {
    'manuallyEditedLineIds': ['edited'],
  },
);

Future<_Repository> _createRepository() async {
  final root = await Directory.systemTemp.createTemp('workflow-conflict-');
  addTearDown(() => root.delete(recursive: true));
  final audio = File('${root.path}/song.wav');
  await audio.writeAsBytes([1]);
  final now = DateTime.now();
  return _Repository(
    ProjectManifest(
      id: 'p',
      name: 'Song',
      createdAt: now,
      updatedAt: now,
      status: ProjectStatus.editing,
      audioAsset: AudioAsset(originalPath: audio.path, format: 'wav'),
      projectDirectory: root.path,
      lyricDocument: const LyricDocument(
        language: 'en',
        lines: [
          LyricLine(
            text: 'original',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
          ),
        ],
      ),
    ),
  );
}

LocalProjectTranscriptionWorkflow _workflow(
  _Repository repository,
  TranscriptionException? error, {
  Future<void> Function()? onTranscribe,
  Future<void> Function()? onSettingsLoad,
  AsrResourceCoordinator? resources,
  _Service? service,
}) => LocalProjectTranscriptionWorkflow(
  projectRepository: repository,
  transcriptionService: service ?? _Service(error, onTranscribe),
  settingsStore: _Settings(onSettingsLoad),
  profileResolver: _Resolver(),
  runtimeManager: _Runtime(),
  resources: resources ?? AsrResourceCoordinator(),
  mediaMetadataRepository: _UnusedMetadata(),
  playbackSession: _UnusedPlayback(),
  pathCanonicalizer: _UnusedCanonicalizer(),
);

class _Repository implements ProjectRepository {
  ProjectManifest project;
  final statuses = <ProjectStatus>[];
  Future<void> Function(_Repository, ProjectManifest)? beforeConditionalWrite;
  _Repository(this.project);
  @override
  Future<ProjectManifest?> getProjectById(String id) async => project;
  @override
  Future<ProjectManifest> updateProject(ProjectManifest value) async {
    project = value.copyWith(revision: project.revision + 1);
    statuses.add(value.status);
    return project;
  }

  @override
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest value, {
    required int expectedRevision,
  }) async {
    await beforeConditionalWrite?.call(this, value);
    if (project.revision != expectedRevision) {
      throw ProjectUpdateConflictException(currentProject: project);
    }
    return updateProject(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service implements TranscriptionService {
  final TranscriptionException? error;
  final Future<void> Function()? onTranscribe;
  _Service(this.error, this.onTranscribe);
  Future<void> Function()? onCancel;
  int cancelCalls = 0;
  TranscriptionRequest? lastRequest;
  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    lastRequest = request;
    await onTranscribe?.call();
    if (error != null) throw error!;
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
  Stream<TranscriptionProgress> get progressStream => const Stream.empty();
  @override
  bool get isRunning => false;
  @override
  Future<void> cancel() async {
    cancelCalls++;
    await onCancel?.call();
  }

  @override
  Future<void> dispose() async {}
}

class _Settings implements TranscriptionSettingsStore {
  _Settings(this.onLoad);
  final Future<void> Function()? onLoad;
  @override
  Future<TranscriptionConfig?> load() async {
    await onLoad?.call();
    return _config;
  }

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
