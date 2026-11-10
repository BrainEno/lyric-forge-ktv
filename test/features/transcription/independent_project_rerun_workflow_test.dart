import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/independent_project_rerun_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/independent_project_rerun_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_rerun_candidate_store.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_resource_coordinator.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

const manual = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: 'human edit',
      startTime: Duration.zero,
      endTime: Duration(seconds: 1),
    ),
  ],
);
const draft = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: 'model output',
      startTime: Duration.zero,
      endTime: Duration(seconds: 1),
    ),
  ],
);
const config = TranscriptionConfig(
  mode: TranscriptionMode.whisperOnly,
  whisperExecutable: 'whisper',
  modelPath: 'whisper-model',
  qwenExecutable: 'qwen',
  qwenModelPath: 'qwen-model',
  qwenAlignerModelPath: 'aligner',
);

void main() {
  late Directory root;
  late FileProjectRepository disk;
  late _Repository repo;
  late ProjectManifest project;
  late _Settings settings;
  late _Profiles profiles;
  late _Runtime runtime;
  late _Engine qwen;
  late _Engine whisper;
  late AsrResourceCoordinator resources;
  late IndependentProjectRerunWorkflow workflow;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rerun-workflow-');
    final input = File('${root.path}/audio.wav');
    await input.writeAsBytes([1, 2, 3]);
    disk = FileProjectRepository(rootDirectory: root);
    final created = await disk.createProject(name: 'Song');
    project = await disk.updateProject(
      created.copyWith(
        audioAsset: AudioAsset(originalPath: input.path, format: 'wav'),
        lyricDocument: manual,
      ),
    );
    repo = _Repository(disk);
    settings = _Settings();
    profiles = _Profiles();
    runtime = _Runtime(profiles);
    qwen = _Engine();
    whisper = _Engine();
    resources = AsrResourceCoordinator();
    workflow = IndependentProjectRerunWorkflow(
      projects: repo,
      settings: settings,
      profiles: profiles,
      runtime: runtime,
      resources: resources,
      createQwen: () => qwen,
      createWhisper: () => whisper,
    );
  });
  tearDown(() async => root.delete(recursive: true));

  test('shared lease rejects work before preflight without touching owner', () async {
    for (final use in [AsrResourceUse.transcription, AsrResourceUse.alignment,
        AsrResourceUse.installation, AsrResourceUse.independentRerun]) {
      final owner = resources.tryAcquire(use)!;
      await expectLater(workflow.run(projectId: project.id, engine: IndependentRerunEngine.qwen),
          throwsA(isA<TranscriptionException>().having((e) => e.kind, 'kind', TranscriptionFailureKind.busy)));
      expect(resources.activeUse, use);
      expect(workflow.phase, IndependentRerunPhase.idle);
      expect(qwen.requests, isEmpty);
      expect(runtime.inspected, isNull);
      owner.release();
    }
    await workflow.run(projectId: project.id, engine: IndependentRerunEngine.qwen);
    expect(resources.activeUse, isNull);
  });

  test('two workflows share the lease across cancellation and adapter cleanup', () async {
    final started = Completer<void>();
    final finishInference = Completer<void>();
    final finishCancel = Completer<void>();
    final disposed = Completer<void>();
    qwen.onDispose = () { disposed.complete(); };
    qwen.onRun = () async { started.complete(); await finishInference.future; };
    qwen.onCancel = () async { await finishCancel.future; };
    final second = IndependentProjectRerunWorkflow(
      projects: repo, settings: settings, profiles: profiles, runtime: runtime,
      resources: resources, createQwen: () => _Engine(), createWhisper: () => _Engine(),
    );
    final operation = workflow.run(projectId: project.id, engine: IndependentRerunEngine.qwen);
    final cancelled = expectLater(operation, throwsA(isA<TranscriptionException>().having(
        (e) => e.kind, 'kind', TranscriptionFailureKind.cancelled)));
    await started.future;
    final cancel = workflow.cancel();
    finishInference.complete();
    // Wait for adapter disposal; cancellation itself is still in flight.
    await disposed.future;
    expect(resources.activeUse, AsrResourceUse.independentRerun);
    await expectLater(second.run(projectId: project.id, engine: IndependentRerunEngine.whisper),
        throwsA(isA<TranscriptionException>().having((e) => e.kind, 'kind', TranscriptionFailureKind.busy)));
    finishCancel.complete();
    expect(await cancel, isTrue);
    await cancelled;
    expect(resources.activeUse, isNull);
    await second.run(projectId: project.id, engine: IndependentRerunEngine.whisper);
    expect(resources.activeUse, isNull);
  });

  test('selected engine alone runs and both versions persist', () async {
    for (final engine in IndependentRerunEngine.values) {
      final result = await workflow.run(projectId: project.id, engine: engine);
      final used = engine == IndependentRerunEngine.qwen ? qwen : whisper;
      expect(used.requests, hasLength(1));
      expect(
        used.requests.single.config.mode,
        engine == IndependentRerunEngine.qwen
            ? TranscriptionMode.highestQuality
            : TranscriptionMode.whisperOnly,
      );
      expect(result.pair.engine, engine);
      expect(result.pair.original.toJson(), manual.toJson());
      expect(result.pair.candidate.toJson(), draft.toJson());
      expect(used.disposed, isTrue);
      expect(
        await Directory(used.requests.single.outputDirectory).exists(),
        isFalse,
      );
    }
    final reloaded = (await FileProjectRepository(
      rootDirectory: root,
    ).getProjectById(project.id))!;
    expect(reloaded.lyricDocument!.toJson(), manual.toJson());
    expect(ProjectRerunCandidateStore(disk).read(reloaded), hasLength(2));
    expect(workflow.phase, IndependentRerunPhase.idle);
  });

  test(
    'selected engine failure is propagated without fallback or write',
    () async {
      qwen.onRun = () async =>
          throw const TranscriptionException.environment('qwen failed');
      await expectLater(
        workflow.run(
          projectId: project.id,
          engine: IndependentRerunEngine.qwen,
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.kind,
            'kind',
            TranscriptionFailureKind.environment,
          ),
        ),
      );
      expect(qwen.requests, hasLength(1));
      expect(qwen.disposed, isTrue);
      expect(resources.activeUse, isNull);
      expect(whisper.requests, isEmpty);
      final latest = (await disk.getProjectById(project.id))!;
      expect(ProjectRerunCandidateStore(disk).read(latest), isEmpty);
      expect(latest.lyricDocument!.toJson(), manual.toJson());
    },
  );

  test(
    'repaired model configuration reaches the selected engine and candidate',
    () async {
      runtime.onRepair = (input) => input.copyWith(modelPath: 'repaired-model');
      final result = await workflow.run(
        projectId: project.id,
        engine: IndependentRerunEngine.whisper,
      );
      expect(runtime.inspected!.modelPath, 'repaired-model');
      expect(whisper.requests.single.config.modelPath, 'repaired-model');
      expect(result.pair.modelReference, 'repaired-model');
    },
  );

  test('missing selected engine never silently falls back', () async {
    runtime.ready.remove(AsrRuntimeComponent.qwenModel);
    await expectLater(
      workflow.run(projectId: project.id, engine: IndependentRerunEngine.qwen),
      throwsA(
        isA<TranscriptionException>().having(
          (e) => e.kind,
          'kind',
          TranscriptionFailureKind.environment,
        ),
      ),
    );
    expect(runtime.inspected!.mode, TranscriptionMode.highestQuality);
    expect(qwen.requests, isEmpty);
    expect(whisper.requests, isEmpty);
    expect(
      ProjectRerunCandidateStore(
        disk,
      ).read((await disk.getProjectById(project.id))!),
      isEmpty,
    );
    // A missing Qwen model does not prevent an explicit Whisper run.
    await workflow.run(
      projectId: project.id,
      engine: IndependentRerunEngine.whisper,
    );
    expect(whisper.requests, hasLength(1));
    expect(qwen.requests, isEmpty);
  });

  test(
    'absent readiness components and missing settings fail before inference',
    () async {
      runtime.ready.remove(AsrRuntimeComponent.ffmpeg);
      await expectLater(
        workflow.run(
          projectId: project.id,
          engine: IndependentRerunEngine.whisper,
        ),
        throwsA(isA<TranscriptionException>()),
      );
      settings.value = null;
      await expectLater(
        workflow.run(
          projectId: project.id,
          engine: IndependentRerunEngine.qwen,
        ),
        throwsA(isA<TranscriptionException>()),
      );
      expect(qwen.requests, isEmpty);
      expect(whisper.requests, isEmpty);
    },
  );

  test('active runtime installation is never cancelled or used', () async {
    runtime.installing = true;
    await expectLater(
      workflow.run(projectId: project.id, engine: IndependentRerunEngine.qwen),
      throwsA(
        isA<TranscriptionException>().having(
          (e) => e.kind,
          'kind',
          TranscriptionFailureKind.busy,
        ),
      ),
    );
    expect(runtime.cancelled, isFalse);
    expect(qwen.requests, isEmpty);
  });

  test(
    'preflight cancellation and overlapping calls do not launch engines',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      settings.onLoad = () async {
        started.complete();
        await release.future;
      };
      final operation = workflow.run(
        projectId: project.id,
        engine: IndependentRerunEngine.qwen,
      );
      final assertion = expectLater(
        operation,
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.kind,
            'kind',
            TranscriptionFailureKind.cancelled,
          ),
        ),
      );
      await started.future;
      expect(workflow.phase, IndependentRerunPhase.preparing);
      await expectLater(
        workflow.run(
          projectId: project.id,
          engine: IndependentRerunEngine.whisper,
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.kind,
            'kind',
            TranscriptionFailureKind.busy,
          ),
        ),
      );
      expect(await workflow.cancel(), isTrue);
      expect(resources.activeUse, AsrResourceUse.independentRerun);
      release.complete();
      await assertion;
      expect(resources.activeUse, isNull);
      expect(qwen.requests, isEmpty);
      expect(whisper.requests, isEmpty);
      expect(runtime.cancelled, isFalse);
    },
  );

  test('cancel during recognition discards the result and cleans up', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    qwen.onRun = () async {
      started.complete();
      await release.future;
    };
    final operation = workflow.run(
      projectId: project.id,
      engine: IndependentRerunEngine.qwen,
    );
    final assertion = expectLater(
      operation,
      throwsA(
        isA<TranscriptionException>().having(
          (e) => e.kind,
          'kind',
          TranscriptionFailureKind.cancelled,
        ),
      ),
    );
    await started.future;
    expect(workflow.phase, IndependentRerunPhase.recognizing);
    expect(await workflow.cancel(), isTrue);
    expect(qwen.cancelled, isTrue);
    release.complete();
    await assertion;
    expect(qwen.disposed, isTrue);
    expect(
      ProjectRerunCandidateStore(
        disk,
      ).read((await disk.getProjectById(project.id))!),
      isEmpty,
    );
  });

  test('saving is a non-cancellable commit boundary', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    repo.beforeUpdate = () async {
      started.complete();
      await release.future;
    };
    final operation = workflow.run(
      projectId: project.id,
      engine: IndependentRerunEngine.whisper,
    );
    await started.future;
    expect(workflow.phase, IndependentRerunPhase.saving);
    expect(resources.activeUse, AsrResourceUse.independentRerun);
    expect(await workflow.cancel(), isFalse);
    release.complete();
    final result = await operation;
    expect(result.pair.engine, IndependentRerunEngine.whisper);
    expect(
      ProjectRerunCandidateStore(
        disk,
      ).read((await disk.getProjectById(project.id))!),
      hasLength(1),
    );
  });

  test('concurrent lyric edit discards candidate', () async {
    qwen.onRun = () async {
      final latest = (await disk.getProjectById(project.id))!;
      await disk.updateProject(latest.copyWith(lyricDocument: draft));
    };
    await expectLater(
      workflow.run(projectId: project.id, engine: IndependentRerunEngine.qwen),
      throwsA(isA<TranscriptionException>()),
    );
    final current = (await disk.getProjectById(project.id))!;
    expect(current.lyricDocument!.toJson(), draft.toJson());
    expect(ProjectRerunCandidateStore(disk).read(current), isEmpty);
  });
}

class _Repository implements ProjectRepository {
  final ProjectRepository delegate;
  Future<void> Function()? beforeUpdate;
  _Repository(this.delegate);
  @override
  Future<ProjectManifest?> getProjectById(String id) =>
      delegate.getProjectById(id);
  @override
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest project, {
    required int expectedRevision,
  }) async {
    if (beforeUpdate != null) await beforeUpdate!();
    return delegate.updateProjectIfUnchanged(
      project,
      expectedRevision: expectedRevision,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings implements TranscriptionSettingsStore {
  TranscriptionConfig? value = config;
  Future<void> Function()? onLoad;
  @override
  Future<TranscriptionConfig?> load() async {
    if (onLoad != null) await onLoad!();
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements TranscriptionProfileResolver {
  @override
  Future<TranscriptionHardwareInfo> detectHardware() async =>
      const TranscriptionHardwareInfo(
        operatingSystem: 'linux',
        architecture: 'x86_64',
      );
  @override
  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig config,
  ) async => ResolvedTranscriptionProfile(
    profile: TranscriptionProfilePreference.custom,
    label: 'test',
    description: 'test',
    hardware: await detectHardware(),
    config: config,
  );
}

class _Runtime implements AsrRuntimeManager {
  final _Profiles profiles;
  final ready = AsrRuntimeComponent.values.toSet();
  TranscriptionConfig? inspected;
  TranscriptionConfig Function(TranscriptionConfig)? onRepair;
  bool cancelled = false;
  bool installing = false;
  _Runtime(this.profiles);
  @override
  bool get isInstalling => installing;
  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    inspected = config;
    return AsrRuntimeStatus(
      profile: await profiles.resolve(config),
      managedRoot: '',
      components: [
        for (final component in ready)
          AsrRuntimeComponentStatus(
            component: component,
            state: AsrRuntimeComponentState.ready,
            label: component.name,
            detail: 'ready',
          ),
      ],
    );
  }

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      onRepair?.call(config) ?? config;
  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements TranscriptionService {
  final requests = <TranscriptionRequest>[];
  Future<void> Function()? onRun;
  bool cancelled = false;
  bool disposed = false;
  Future<void> Function()? onCancel;
  void Function()? onDispose;
  @override
  bool get isRunning => false;
  @override
  Stream<TranscriptionProgress> get progressStream => const Stream.empty();
  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    requests.add(request);
    if (onRun != null) await onRun!();
    return const TranscriptionResult(
      lyrics: draft,
      normalizedAudioPath: '',
      rawJsonPath: '',
      detectedLanguage: 'en',
    );
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (onCancel != null) await onCancel!();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    onDispose?.call();
  }
}
