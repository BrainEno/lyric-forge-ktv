import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_span_rerecognition.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_span_recognition_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_resource_coordinator.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

const config = TranscriptionConfig(
  mode: TranscriptionMode.whisperOnly,
  whisperExecutable: 'whisper',
  modelPath: '/models/ggml-large-v3.bin',
  qwenExecutable: 'qwen',
  qwenModelPath: '/models/Qwen3-ASR-1.7B',
  qwenAlignerModelPath: '/models/aligner',
);

/// A clip-local result: the engine only ever sees the cut clip.
const clipDraft = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: 'found again',
      startTime: Duration(milliseconds: 400),
      endTime: Duration(milliseconds: 2400),
      words: [
        LyricWordTiming(
          text: 'found',
          start: Duration(milliseconds: 400),
          end: Duration(milliseconds: 1200),
        ),
        LyricWordTiming(
          text: 'again',
          start: Duration(milliseconds: 1300),
          end: Duration(milliseconds: 2400),
        ),
      ],
    ),
  ],
);

void main() {
  late Directory root;
  late FileProjectRepository disk;
  late ProjectManifest project;
  late _Settings settings;
  late _Runtime runtime;
  late _Engine qwen;
  late _Engine whisper;
  late AsrResourceCoordinator resources;
  late List<({Duration start, Duration length, String output})> cuts;
  late List<({String audioPath, String text, Duration duration})> alignments;
  late ProjectSpanRecognitionService service;

  ProjectSpanRecognitionService build({
    ForcedAlignmentRunner? align,
    SpanClipCutter? cut,
  }) => ProjectSpanRecognitionService(
    projects: disk,
    settings: settings,
    profiles: _Profiles(),
    runtime: runtime,
    resources: resources,
    alignClip:
        align ??
        ({
          required String audioPath,
          required String text,
          required String language,
          required Duration audioDuration,
        }) async {
          alignments.add((
            audioPath: audioPath,
            text: text,
            duration: audioDuration,
          ));
          return const [
            ForcedAlignedSpan(
              text: 'hello',
              start: Duration(milliseconds: 100),
              end: Duration(milliseconds: 600),
            ),
          ];
        },
    createQwen: () => qwen,
    createWhisper: () => whisper,
    cutClip:
        cut ??
        ({
          required String ffmpegExecutable,
          required String inputPath,
          required String outputPath,
          required Duration start,
          required Duration length,
          required void Function(Process? process) onProcess,
        }) async {
          cuts.add((start: start, length: length, output: outputPath));
          await File(outputPath).writeAsBytes(List.filled(64, 0));
        },
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('span-recognition-');
    final input = File('${root.path}/audio.wav');
    await input.writeAsBytes([1, 2, 3]);
    disk = FileProjectRepository(rootDirectory: root);
    final created = await disk.createProject(name: 'Song');
    project = await disk.updateProject(
      created.copyWith(
        audioAsset: AudioAsset(
          originalPath: input.path,
          format: 'wav',
          duration: const Duration(seconds: 200),
        ),
      ),
    );
    settings = _Settings();
    runtime = _Runtime();
    qwen = _Engine();
    whisper = _Engine();
    resources = AsrResourceCoordinator();
    cuts = [];
    alignments = [];
    service = build();
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('recognises only the cut clip and moves the result onto the song '
      'timeline', () async {
    final result = await service.recognize(
      projectId: project.id,
      start: const Duration(seconds: 60),
      end: const Duration(seconds: 64),
      engine: LyricSpanEngine.qwen,
    );

    expect(cuts.single.start, const Duration(seconds: 60));
    expect(cuts.single.length, const Duration(seconds: 4));
    final request = qwen.requests.single;
    expect(request.inputAudioPath, cuts.single.output);
    expect(request.normalizedInputAudioPath, cuts.single.output);
    expect(request.recognitionHints.songTitle, 'Song');
    expect(whisper.requests, isEmpty);

    final line = result.lines.single;
    expect(line.text, 'found again');
    expect(line.startTime, const Duration(milliseconds: 60400));
    expect(line.endTime, const Duration(milliseconds: 62400));
    expect(line.words.first.start, const Duration(milliseconds: 60400));
    expect(line.words.last.end, const Duration(milliseconds: 62400));
    expect(result.engineLabel, contains('Qwen3-ASR'));
    expect(result.language, 'en');
    expect(qwen.disposed, isTrue);
    expect(resources.activeUse, isNull);
    // The temporary clip directory is removed afterwards.
    expect(
      await Directory(File(cuts.single.output).parent.path).exists(),
      isFalse,
    );
  });

  test('runs Qwen on the shared adapter without disposing it', () async {
    final shared = _Engine();
    final withShared = ProjectSpanRecognitionService(
      projects: disk,
      settings: settings,
      profiles: _Profiles(),
      runtime: runtime,
      resources: resources,
      alignClip:
          ({
            required String audioPath,
            required String text,
            required String language,
            required Duration audioDuration,
          }) async => const [],
      createQwen: () => qwen,
      createWhisper: () => whisper,
      sharedQwen: shared,
      cutClip:
          ({
            required String ffmpegExecutable,
            required String inputPath,
            required String outputPath,
            required Duration start,
            required Duration length,
            required void Function(Process? process) onProcess,
          }) async {
            await File(outputPath).writeAsBytes(List.filled(64, 0));
          },
    );
    await withShared.recognize(
      projectId: project.id,
      start: Duration.zero,
      end: const Duration(seconds: 3),
      engine: LyricSpanEngine.qwen,
    );
    expect(shared.requests, hasLength(1));
    expect(shared.disposed, isFalse);
    expect(qwen.requests, isEmpty);

    await withShared.recognize(
      projectId: project.id,
      start: Duration.zero,
      end: const Duration(seconds: 3),
      engine: LyricSpanEngine.whisper,
    );
    expect(whisper.requests, hasLength(1));
    expect(whisper.disposed, isTrue);
  });

  test('Whisper runs Whisper and inspects the Whisper components', () async {
    await service.recognize(
      projectId: project.id,
      start: const Duration(seconds: 10),
      end: const Duration(seconds: 12),
      engine: LyricSpanEngine.whisper,
    );
    expect(whisper.requests, hasLength(1));
    expect(qwen.requests, isEmpty);
    expect(runtime.inspected?.mode, TranscriptionMode.whisperOnly);
  });

  test('holds the shared resource lease for the whole run', () async {
    final release = Completer<void>();
    qwen.onRun = () async {
      expect(resources.activeUse, AsrResourceUse.spanRecognition);
      await release.future;
    };
    final running = service.recognize(
      projectId: project.id,
      start: Duration.zero,
      end: const Duration(seconds: 3),
      engine: LyricSpanEngine.qwen,
    );
    await pumpEventQueue();
    await expectLater(
      service.recognize(
        projectId: project.id,
        start: Duration.zero,
        end: const Duration(seconds: 3),
        engine: LyricSpanEngine.qwen,
      ),
      throwsA(
        isA<LyricSpanRecognitionException>().having(
          (e) => e.busy,
          'busy',
          true,
        ),
      ),
    );
    release.complete();
    await running;
    expect(resources.activeUse, isNull);
  });

  test('refuses while another ASR task owns the resources', () async {
    final lease = resources.tryAcquire(AsrResourceUse.transcription)!;
    await expectLater(
      service.recognize(
        projectId: project.id,
        start: Duration.zero,
        end: const Duration(seconds: 3),
        engine: LyricSpanEngine.qwen,
      ),
      throwsA(
        isA<LyricSpanRecognitionException>().having(
          (e) => e.busy,
          'busy',
          true,
        ),
      ),
    );
    expect(cuts, isEmpty);
    lease.release();
  });

  test('rejects invalid and over-long stretches before cutting', () async {
    for (final (start, end) in [
      (const Duration(seconds: 5), const Duration(seconds: 5)),
      (const Duration(seconds: -1), const Duration(seconds: 5)),
      (Duration.zero, const Duration(seconds: 91)),
    ]) {
      await expectLater(
        service.recognize(
          projectId: project.id,
          start: start,
          end: end,
          engine: LyricSpanEngine.qwen,
        ),
        throwsA(isA<LyricSpanRecognitionException>()),
      );
    }
    expect(cuts, isEmpty);
    expect(resources.activeUse, isNull);
  });

  test('clamps the clip to the audio length', () async {
    await service.recognize(
      projectId: project.id,
      start: const Duration(seconds: 198),
      end: const Duration(seconds: 205),
      engine: LyricSpanEngine.qwen,
    );
    expect(cuts.single.length, const Duration(seconds: 2));
  });

  test(
    'reports a runtime that is not ready without running an engine',
    () async {
      runtime.ready.remove(AsrRuntimeComponent.qwenModel);
      await expectLater(
        service.recognize(
          projectId: project.id,
          start: Duration.zero,
          end: const Duration(seconds: 3),
          engine: LyricSpanEngine.qwen,
        ),
        throwsA(
          isA<LyricSpanRecognitionException>().having(
            (e) => e.message,
            'message',
            contains('Qwen3-ASR'),
          ),
        ),
      );
      expect(qwen.requests, isEmpty);
      expect(resources.activeUse, isNull);
    },
  );

  test('turns engine failures into messages the dialog can show', () async {
    qwen.failure = const TranscriptionException.input('Qwen3-ASR 返回 HTTP 400');
    await expectLater(
      service.recognize(
        projectId: project.id,
        start: Duration.zero,
        end: const Duration(seconds: 3),
        engine: LyricSpanEngine.qwen,
      ),
      throwsA(
        isA<LyricSpanRecognitionException>().having(
          (e) => e.message,
          'message',
          'Qwen3-ASR 返回 HTTP 400',
        ),
      ),
    );
    expect(qwen.disposed, isTrue);
  });

  test('cancel stops the engine and reports cancellation', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    qwen.onRun = () async {
      started.complete();
      await release.future;
    };
    qwen.onCancel = () async => release.complete();
    final running = service.recognize(
      projectId: project.id,
      start: Duration.zero,
      end: const Duration(seconds: 3),
      engine: LyricSpanEngine.qwen,
    );
    await started.future;
    await service.cancel();
    await expectLater(
      running,
      throwsA(
        isA<LyricSpanRecognitionException>().having(
          (e) => e.cancelled,
          'cancelled',
          true,
        ),
      ),
    );
    expect(qwen.cancelled, isTrue);
    expect(resources.activeUse, isNull);
  });

  test('aligns the clip and moves the spans onto the song timeline', () async {
    final spans = await service.align(
      projectId: project.id,
      start: const Duration(seconds: 30),
      end: const Duration(seconds: 33),
      text: 'hello',
      language: 'English',
    );
    expect(alignments.single.audioPath, cuts.single.output);
    expect(alignments.single.text, 'hello');
    expect(
      alignments.single.duration,
      const Duration(seconds: 3) + ProjectSpanRecognitionService.alignmentSlack,
    );
    expect(spans.single.start, const Duration(milliseconds: 30100));
    expect(spans.single.end, const Duration(milliseconds: 30600));
    expect(resources.activeUse, isNull);
  });

  test('alignment refuses empty text', () async {
    await expectLater(
      service.align(
        projectId: project.id,
        start: Duration.zero,
        end: const Duration(seconds: 3),
        text: '  ',
        language: 'English',
      ),
      throwsA(isA<LyricSpanRecognitionException>()),
    );
    expect(cuts, isEmpty);
  });

  test('a project without audio is reported, not crashed on', () async {
    final bare = await disk.createProject(name: 'No audio');
    await expectLater(
      service.recognize(
        projectId: bare.id,
        start: Duration.zero,
        end: const Duration(seconds: 3),
        engine: LyricSpanEngine.qwen,
      ),
      throwsA(isA<LyricSpanRecognitionException>()),
    );
    expect(resources.activeUse, isNull);
  });
}

class _Settings implements TranscriptionSettingsStore {
  TranscriptionConfig? value = config;

  @override
  Future<TranscriptionConfig?> load() async => value;

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
  final ready = AsrRuntimeComponent.values.toSet();
  TranscriptionConfig? inspected;
  bool installing = false;

  @override
  bool get isInstalling => installing;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    inspected = config;
    return AsrRuntimeStatus(
      profile: await _Profiles().resolve(config),
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
      config;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements TranscriptionService {
  final requests = <TranscriptionRequest>[];
  Future<void> Function()? onRun;
  Future<void> Function()? onCancel;
  TranscriptionException? failure;
  bool cancelled = false;
  bool disposed = false;

  @override
  bool get isRunning => false;

  @override
  Stream<TranscriptionProgress> get progressStream => const Stream.empty();

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    requests.add(request);
    if (onRun != null) await onRun!();
    if (failure != null) throw failure!;
    return const TranscriptionResult(
      lyrics: clipDraft,
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
  }
}
