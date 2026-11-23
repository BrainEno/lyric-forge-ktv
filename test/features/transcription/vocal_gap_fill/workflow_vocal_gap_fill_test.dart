import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_gap_fill_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_span_rerecognition.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_project_transcription_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/spoken_language.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_run_progress.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_activity.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_gap_fill_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_resource_coordinator.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/spoken_language_detector.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_vocal_check.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_vocal_gap_fill.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/vocal_activity_lyric_gate.dart';

const _config = TranscriptionConfig(
  mode: TranscriptionMode.whisperOnly,
  whisperExecutable: 'whisper',
  modelPath: 'model',
);

const _gap = LyricVocalCheckSpan(Duration(seconds: 8), Duration(seconds: 11));

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
  test('fills the stretches the vocal check found before saving', () async {
    final fixture = await _Fixture.create();
    final progress = <TranscriptionProgress>[];
    final workflow = fixture.workflow();
    final subscription = workflow.progressStream.listen(progress.add);
    addTearDown(subscription.cancel);

    await workflow.transcribeProject('p');

    final request = fixture.gapFill.lastRequest!;
    expect(request.audioPath, fixture.vocalPath);
    expect(request.engines, [LyricSpanEngine.whisper]);
    expect(request.hints.songTitle, 'Song');
    expect(request.config.whisperExecutable, 'whisper');
    // The step saw the checked draft, with its record.
    expect(fixture.gapFill.lastDraft?.lines.single.text, 'checked row');
    expect(
      LyricVocalCheckRecord.fromMetadata(
        fixture.gapFill.lastDraft!.metadata,
      )?.uncoveredSpans,
      [_gap],
    );

    final saved = fixture.repository.project;
    expect(saved.status, ProjectStatus.editing);
    expect(saved.lyricDocument?.lines.map((line) => line.text), [
      'checked row',
      'filled row',
    ]);
    expect(saved.lyricDocument?.metadata['editableDraft'], isTrue);
    expect(
      LyricVocalGapFillRecord.fromMetadata(
        saved.lyricDocument!.metadata,
      )?.insertedLineIds,
      ['filled-1'],
    );
    final transcription = saved.metadata['transcription'] as Map;
    final report = transcription['vocalGapFill'] as Map;
    expect(report['applied'], isTrue);
    expect(report['filledSpans'], 1);
    expect(report['insertedLines'], 1);
    expect(progress.map((p) => p.message), contains('正在补全漏句 1/1'));
    expect(progress.map((p) => p.message), contains('已自动补上 1 处漏句（1 行）'));
    // D-049: every event names its step, the steps come in order and the
    // bar of the whole run only moves forward, ending full after saving.
    expect(progress.last.message, '歌词草稿已保存');
    expect(progress.last.step, TranscriptionRunStep.saving);
    expect(progress.last.overall, closeTo(1, 1e-9));
    final steps = progress.map((p) => p.step!.index).toList();
    expect(steps, orderedEquals([...steps]..sort()));
    final overall = progress.map((p) => p.overall!).toList();
    for (var i = 1; i < overall.length; i++) {
      expect(overall[i], greaterThanOrEqualTo(overall[i - 1]));
    }
    final fill = progress.firstWhere((p) => p.message == '正在补全漏句 1/1');
    expect(fill.step, TranscriptionRunStep.fillingGaps);
    expect(
      fill.overall,
      closeTo(
        TranscriptionRunPlan.overallAt(TranscriptionRunStep.fillingGaps, 0.95),
        1e-9,
      ),
    );
  });

  test('switched off in the settings, the draft keeps its gaps', () async {
    final fixture = await _Fixture.create();
    fixture.settings.config = _config.copyWith(
      vocalGapFill: VocalGapFillPreference.off,
    );
    await fixture.workflow().transcribeProject('p');

    expect(fixture.gapFill.calls, 0);
    final saved = fixture.repository.project;
    expect(saved.lyricDocument?.lines.single.text, 'checked row');
    final report =
        (saved.metadata['transcription'] as Map)['vocalGapFill'] as Map;
    expect(report['applied'], isFalse);
    expect(report['skipReason'], 'disabled');
  });

  test('a check without stretches of missed singing skips the step', () async {
    final fixture = await _Fixture.create();
    fixture.check.spans = const [];
    await fixture.workflow().transcribeProject('p');

    expect(fixture.gapFill.calls, 0);
    final report =
        (fixture.repository.project.metadata['transcription']
                as Map)['vocalGapFill']
            as Map;
    expect(report['skipReason'], 'noGaps');
  });

  test('recognition of the mix has no check, so no step', () async {
    final fixture = await _Fixture.create(withVocal: false);
    await fixture.workflow().transcribeProject('p');

    expect(fixture.check.calls, 0);
    expect(fixture.gapFill.calls, 0);
    final transcription =
        fixture.repository.project.metadata['transcription'] as Map;
    expect((transcription['vocalCheck'] as Map)['skipReason'], 'notVocalInput');
    expect(
      (transcription['vocalGapFill'] as Map)['skipReason'],
      'noVocalCheck',
    );
    expect(
      fixture.repository.project.lyricDocument?.lines.single.text,
      'ASR draft',
    );
  });

  test('a skipped vocal check skips the step', () async {
    final fixture = await _Fixture.create();
    fixture.check.applied = false;
    await fixture.workflow().transcribeProject('p');
    expect(fixture.gapFill.calls, 0);
    final report =
        (fixture.repository.project.metadata['transcription']
                as Map)['vocalGapFill']
            as Map;
    expect(report['skipReason'], 'noVocalCheck');
  });

  test('a failing step keeps the checked draft and the run', () async {
    final fixture = await _Fixture.create();
    fixture.gapFill.error = StateError('boom');
    await fixture.workflow().transcribeProject('p');

    final saved = fixture.repository.project;
    expect(saved.status, ProjectStatus.editing);
    expect(saved.lyricDocument?.lines.single.text, 'checked row');
    final report =
        (saved.metadata['transcription'] as Map)['vocalGapFill'] as Map;
    expect(report['skipReason'], 'failed');
    expect(report['error'], contains('boom'));
    expect(report['engines'], ['whisper']);
  });

  test('a two-engine run tries Qwen first, then Whisper', () async {
    final fixture = await _Fixture.create();
    fixture.settings.config = _config.copyWith(
      mode: TranscriptionMode.highestQuality,
      qwenExecutable: 'qwen',
    );
    fixture.runtime.ready = AsrRuntimeComponent.values.toSet();
    await fixture.workflow().transcribeProject('p');
    expect(fixture.gapFill.lastRequest?.engines, [
      LyricSpanEngine.qwen,
      LyricSpanEngine.whisper,
    ]);
  });

  test('a run degraded to Whisper fills with Whisper only', () async {
    final fixture = await _Fixture.create();
    fixture.settings.config = _config.copyWith(
      mode: TranscriptionMode.highestQuality,
      qwenExecutable: 'qwen',
    );
    fixture.runtime.ready = AsrRuntimeComponent.values.toSet();
    fixture.service.metadata = const {'degraded': true};
    await fixture.workflow().transcribeProject('p');
    expect(fixture.gapFill.lastRequest?.engines, [LyricSpanEngine.whisper]);
  });

  test('cancelling during the step cancels the run', () async {
    final fixture = await _Fixture.create();
    final entered = Completer<void>();
    final release = Completer<void>();
    fixture.gapFill.onFill = () async {
      entered.complete();
      await release.future;
    };
    fixture.gapFill.onCancel = () async {
      if (!release.isCompleted) release.complete();
    };
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
    expect(fixture.gapFill.cancels, 1);
    expect(fixture.repository.project.lyricDocument, isNull);
    expect(fixture.repository.project.status, ProjectStatus.editing);
    expect(
      fixture.repository.project.metadata.containsKey(
        'activeTranscriptionRunId',
      ),
      isFalse,
    );
    expect(workflow.isRunning, isFalse);
  });

  group('without the step', () {
    test('nothing is recorded', () async {
      final fixture = await _Fixture.create();
      await fixture.workflow(withGapFill: false).transcribeProject('p');
      final transcription =
          fixture.repository.project.metadata['transcription'] as Map;
      expect(transcription['vocalGapFill'], isNull);
      expect(
        fixture.repository.project.lyricDocument?.lines.single.text,
        'checked row',
      );
    });

    test('without the step, recognition events are still tagged', () async {
      final fixture = await _Fixture.create();
      final workflow = fixture.workflow(withGapFill: false);
      final progress = <TranscriptionProgress>[];
      final subscription = workflow.progressStream.listen(progress.add);
      addTearDown(subscription.cancel);

      await workflow.transcribeProject('p');

      expect(
        progress.map((p) => p.step),
        isNot(contains(TranscriptionRunStep.fillingGaps)),
      );
      expect(progress.first.step, TranscriptionRunStep.preparing);
      expect(progress.last.step, TranscriptionRunStep.saving);
    });

    test('with the step, recognition progress still comes through', () async {
      final fixture = await _Fixture.create();
      final workflow = fixture.workflow();
      final progress = <TranscriptionProgress>[];
      final subscription = workflow.progressStream.listen(progress.add);
      addTearDown(subscription.cancel);
      fixture.service.emit('Whisper 识别中');
      await pumpEventQueue();
      expect(progress.single.message, 'Whisper 识别中');
    });
  });

  group('the sung language (D-061)', () {
    test('auto: recognition and gap filling use the detected one', () async {
      final fixture = await _Fixture.create();
      final detector = _Detector();
      final workflow = fixture.workflow(languageDetector: detector);
      final progress = <TranscriptionProgress>[];
      final subscription = workflow.progressStream.listen(progress.add);
      addTearDown(subscription.cancel);

      await workflow.transcribeProject('p');

      expect(detector.requests.single.inputAudioPath, fixture.vocalPath);
      expect(detector.requests.single.config.language, 'auto');
      expect(detector.requests.single.recognitionHints.songTitle, 'Song');
      expect(fixture.service.lastRequest?.config.language, 'en');
      expect(fixture.gapFill.lastRequest?.config.language, 'en');
      final messages = progress.map((p) => p.message).toList();
      expect(messages, contains('正在判断演唱语言'));
      expect(messages, contains('演唱语言：英文'));
      expect(
        messages.indexOf('演唱语言：英文'),
        lessThan(messages.indexOf('正在启动识别引擎')),
      );
      final transcription =
          fixture.repository.project.metadata['transcription'] as Map;
      final stored = transcription['spokenLanguage'] as Map;
      expect(stored['language'], 'en');
      expect(stored['source'], 'detected');
      expect((stored['probes'] as List).single, {
        'language': 'en',
        'probability': 0.97,
      });
      expect(
        SpokenLanguageResolution.languageOfProject(
          fixture.repository.project.metadata,
        ),
        'en',
      );
      // The editor's summary reads it from the draft (D-062).
      final draftLanguage =
          fixture.repository.project.lyricDocument!.metadata['spokenLanguage']
              as Map;
      expect(draftLanguage['source'], 'detected');
    });

    test('a language set for the song wins, unprobed (D-062)', () async {
      final fixture = await _Fixture.create();
      fixture.repository.project = fixture.repository.project.copyWith(
        metadata: const {'sungLanguage': 'ja'},
      );
      fixture.settings.config = _config.copyWith(language: 'zh');
      final detector = _Detector();
      final workflow = fixture.workflow(languageDetector: detector);
      final progress = <TranscriptionProgress>[];
      final subscription = workflow.progressStream.listen(progress.add);
      addTearDown(subscription.cancel);

      await workflow.transcribeProject('p');

      expect(detector.requests, isEmpty);
      expect(fixture.service.lastRequest?.config.language, 'ja');
      expect(fixture.gapFill.lastRequest?.config.language, 'ja');
      expect(progress.map((p) => p.message), contains('演唱语言：日文（本首歌设置）'));
      final saved = fixture.repository.project;
      expect(saved.metadata['sungLanguage'], 'ja');
      final stored =
          (saved.metadata['transcription'] as Map)['spokenLanguage'] as Map;
      expect(stored['source'], 'project');
      expect(stored['language'], 'ja');
      expect(
        (saved.lyricDocument!.metadata['spokenLanguage'] as Map)['language'],
        'ja',
      );
    });

    test('without a detector a song setting still applies', () async {
      final fixture = await _Fixture.create();
      fixture.repository.project = fixture.repository.project.copyWith(
        metadata: const {'sungLanguage': 'ko'},
      );
      await fixture.workflow().transcribeProject('p');
      expect(fixture.service.lastRequest?.config.language, 'ko');
    });

    test('a language chosen in the settings is never probed', () async {
      final fixture = await _Fixture.create();
      fixture.settings.config = _config.copyWith(language: 'zh');
      final detector = _Detector();
      await fixture.workflow(languageDetector: detector).transcribeProject('p');

      expect(detector.requests, isEmpty);
      expect(fixture.service.lastRequest?.config.language, 'zh');
      final transcription =
          fixture.repository.project.metadata['transcription'] as Map;
      expect(transcription['spokenLanguage'], isNull);
      expect(
        fixture.repository.project.lyricDocument!.metadata,
        isNot(contains('spokenLanguage')),
      );
    });

    test('an unresolved probe leaves the language to the engines', () async {
      final fixture = await _Fixture.create();
      final detector = _Detector()
        ..result = const SpokenLanguageResolution.unresolved(
          probes: [SpokenLanguageProbe('nn', 0.4)],
        );
      await fixture.workflow(languageDetector: detector).transcribeProject('p');

      expect(fixture.service.lastRequest?.config.language, 'auto');
      final stored =
          (fixture.repository.project.metadata['transcription']
                  as Map)['spokenLanguage']
              as Map;
      expect(stored['source'], 'unresolved');
      expect(stored['language'], 'auto');
    });

    test('a failing probe does not fail the run', () async {
      final fixture = await _Fixture.create();
      final detector = _Detector()..error = StateError('probe broke');
      await fixture.workflow(languageDetector: detector).transcribeProject('p');

      final saved = fixture.repository.project;
      expect(saved.status, ProjectStatus.editing);
      expect(fixture.service.lastRequest?.config.language, 'auto');
      final stored =
          (saved.metadata['transcription'] as Map)['spokenLanguage'] as Map;
      expect(stored['source'], 'unresolved');
      expect(stored['error'], contains('probe broke'));
    });

    test('cancelling while probing stops the probe and the run', () async {
      final fixture = await _Fixture.create();
      final started = Completer<void>();
      final gate = Completer<void>();
      final detector = _Detector()
        ..onDetect = () {
          started.complete();
          return gate.future;
        };
      final workflow = fixture.workflow(languageDetector: detector);
      final outcome = expectLater(
        workflow.transcribeProject('p'),
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.kind,
            'kind',
            TranscriptionFailureKind.cancelled,
          ),
        ),
      );
      await started.future;

      final cancelled = workflow.cancel();
      gate.complete();
      await cancelled;
      await outcome;
      expect(detector.cancels, 1);
      expect(fixture.service.lastRequest, isNull);
    });
  });
}

class _Detector implements SpokenLanguageDetector {
  final requests = <TranscriptionRequest>[];
  int cancels = 0;
  Object? error;
  Future<void> Function()? onDetect;
  SpokenLanguageResolution result = const SpokenLanguageResolution(
    language: 'en',
    source: SpokenLanguageSource.detected,
    probes: [SpokenLanguageProbe('en', 0.97)],
  );

  @override
  Future<SpokenLanguageResolution> detect(TranscriptionRequest request) async {
    requests.add(request);
    await onDetect?.call();
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }

  @override
  Future<void> cancel() async => cancels++;
}

class _Fixture {
  _Fixture(this.root, this.repository, this.vocalPath);

  final Directory root;
  final _Repository repository;
  final String? vocalPath;
  final service = _Service();
  final settings = _Settings();
  final runtime = _Runtime();
  final check = _VocalCheck();
  final gapFill = _GapFill();

  static Future<_Fixture> create({bool withVocal = true}) async {
    final root = await Directory.systemTemp.createTemp('workflow-gap-fill-');
    addTearDown(() => root.delete(recursive: true));
    final audio = File('${root.path}/song.wav');
    await audio.writeAsBytes([1]);
    String? vocalPath;
    if (withVocal) {
      final vocal = File('${root.path}/我的人声.wav');
      await vocal.writeAsBytes([1, 2, 3]);
      vocalPath = vocal.path;
    }
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
          audioAsset: AudioAsset(
            originalPath: audio.path,
            format: 'wav',
            vocalPath: vocalPath,
          ),
          projectDirectory: root.path,
        ),
      ),
      vocalPath,
    );
  }

  LocalProjectTranscriptionWorkflow workflow({
    bool withGapFill = true,
    SpokenLanguageDetector? languageDetector,
  }) => LocalProjectTranscriptionWorkflow(
    projectRepository: repository,
    transcriptionService: service,
    settingsStore: settings,
    profileResolver: _Resolver(),
    runtimeManager: runtime,
    resources: AsrResourceCoordinator(),
    mediaMetadataRepository: _UnusedMetadata(),
    playbackSession: _UnusedPlayback(),
    pathCanonicalizer: _UnusedCanonicalizer(),
    vocalCheck: check,
    vocalGapFill: withGapFill ? gapFill : null,
    languageDetector: languageDetector,
  );
}

class _VocalCheck implements TranscriptionVocalCheck {
  int calls = 0;
  bool applied = true;
  List<LyricVocalCheckSpan> spans = const [_gap];

  @override
  Future<VocalCheckResult> check(
    LyricDocument draft, {
    required List<String> audioPaths,
  }) async {
    calls++;
    final record = LyricVocalCheckRecord(uncoveredSpans: spans);
    final document = draft.copyWith(
      lines: const [
        LyricLine(
          text: 'checked row',
          startTime: Duration(milliseconds: 100),
          endTime: Duration(seconds: 4),
          id: 'checked-1',
        ),
      ],
      metadata: record.writeTo(draft.metadata),
    );
    if (!applied) {
      return VocalCheckResult.unchanged(
        draft,
        const VocalCheckReport.skipped(VocalCheckSkipReason.unreliableProfile),
      );
    }
    return VocalCheckResult(
      document,
      VocalCheckReport.applied(
        audioPath: audioPaths.first,
        profile: VocalActivityProfile(
          duration: const Duration(seconds: 30),
          referenceDb: -12,
          floorDb: -60,
          thresholdDb: -40,
          regions: spans,
        ),
        record: record,
      ),
    );
  }
}

class _GapFill implements TranscriptionVocalGapFill {
  int calls = 0;
  int cancels = 0;
  LyricDocument? lastDraft;
  VocalGapFillRequest? lastRequest;
  Object? error;
  Future<void> Function()? onFill;
  Future<void> Function()? onCancel;

  @override
  Future<VocalGapFillResult> fill(
    LyricDocument draft,
    VocalGapFillRequest request,
  ) async {
    calls++;
    lastDraft = draft;
    lastRequest = request;
    request.onProgress?.call(
      const TranscriptionProgress(
        stage: TranscriptionStage.parsing,
        progress: 0.95,
        message: '正在补全漏句 1/1',
      ),
    );
    await onFill?.call();
    final failure = error;
    if (failure != null) throw failure;
    final report = VocalGapFillReport.applied(
      engines: request.engines,
      spans: [
        VocalGapFillSpanReport(
          start: _gap.start,
          end: _gap.end,
          outcome: VocalGapFillOutcome.filled,
          engine: request.engines.first,
          insertedLines: 1,
        ),
      ],
      elapsed: const Duration(seconds: 3),
    );
    final document = draft.copyWith(
      lines: [
        ...draft.lines,
        const LyricLine(
          text: 'filled row',
          startTime: Duration(milliseconds: 8100),
          endTime: Duration(milliseconds: 10800),
          id: 'filled-1',
        ),
      ],
    );
    return VocalGapFillResult(
      document.copyWith(
        metadata: report.record(const ['filled-1']).writeTo(document.metadata),
      ),
      report,
    );
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

  @override
  Future<ProjectManifest?> getProjectById(String id) async => project;

  @override
  Future<ProjectManifest> updateProject(ProjectManifest value) async {
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
  Map<String, dynamic> metadata = const {};
  TranscriptionRequest? lastRequest;

  void emit(String message) => _progress.add(
    TranscriptionProgress(
      stage: TranscriptionStage.transcribing,
      progress: 0.5,
      message: message,
    ),
  );

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    lastRequest = request;
    return TranscriptionResult(
      lyrics: LyricDocument(
        language: 'en',
        lines: const [
          LyricLine(
            text: 'ASR draft',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
          ),
        ],
        metadata: metadata,
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
  Future<void> cancel() async {}
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
  Set<AsrRuntimeComponent> ready = const {};

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      config;
  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async =>
      AsrRuntimeStatus(
        profile: _profile(config),
        components: [
          for (final component in ready)
            AsrRuntimeComponentStatus(
              component: component,
              state: AsrRuntimeComponentState.ready,
              label: component.name,
              detail: 'ok',
            ),
        ],
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
