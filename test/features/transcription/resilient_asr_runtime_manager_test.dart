import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resilient_asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';

void main() {
  const whisperRuntime = r'C:\LyricForge\whisper\whisper-cli.exe';
  const whisperModel = r'C:\LyricForge\models\ggml-large-v3.bin';
  const ffmpeg = r'C:\LyricForge\ffmpeg\ffmpeg.exe';

  TranscriptionConfig highestQualityConfig() {
    return const TranscriptionConfig(
      mode: TranscriptionMode.highestQuality,
      profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
      qwenExecutable: 'qwen3-asr',
      whisperExecutable: 'whisper-cli',
      modelPath: '',
    );
  }

  test('prepares Whisper baseline before attempting highest quality', () async {
    final delegate = _FakeAsrRuntimeManager(
      whisperModel: whisperModel,
      ffmpeg: ffmpeg,
    );
    final manager = ResilientAsrRuntimeManager(
      delegate: delegate,
      whisperRuntimeBootstrap: (_) async => whisperRuntime,
    );
    addTearDown(manager.dispose);

    final result = await manager.installRecommended(highestQualityConfig());

    expect(delegate.installs, hasLength(2));
    expect(delegate.installs[0].mode, TranscriptionMode.whisperOnly);
    expect(delegate.installs[0].whisperExecutable, whisperRuntime);
    expect(delegate.installs[1].mode, TranscriptionMode.highestQuality);
    expect(delegate.installs[1].whisperExecutable, whisperRuntime);
    expect(delegate.installs[1].modelPath, whisperModel);
    expect(delegate.installs[1].ffmpegExecutable, ffmpeg);
    expect(result.mode, TranscriptionMode.highestQuality);
  });

  test('does not silently downgrade when Qwen upgrade fails', () async {
    final delegate = _FakeAsrRuntimeManager(
      whisperModel: whisperModel,
      ffmpeg: ffmpeg,
      failHighestQuality: true,
    );
    final manager = ResilientAsrRuntimeManager(
      delegate: delegate,
      whisperRuntimeBootstrap: (_) async => whisperRuntime,
    );
    addTearDown(manager.dispose);

    await expectLater(
      manager.installRecommended(highestQualityConfig()),
      throwsA(
        isA<TranscriptionException>()
            .having(
              (error) => error.message,
              'message',
              contains('没有切换识别方案'),
            )
            .having(
              (error) => error.details,
              'details',
              contains('Qwen runtime release unavailable'),
            ),
      ),
    );

    expect(delegate.installs, hasLength(2));
    expect(delegate.installs[0].mode, TranscriptionMode.whisperOnly);
    expect(delegate.installs[1].mode, TranscriptionMode.highestQuality);
  });

  test(
    'does not swallow cancellation during highest-quality upgrade',
    () async {
      final delegate = _FakeAsrRuntimeManager(
        whisperModel: whisperModel,
        ffmpeg: ffmpeg,
        cancelHighestQuality: true,
      );
      final manager = ResilientAsrRuntimeManager(
        delegate: delegate,
        whisperRuntimeBootstrap: (_) async => whisperRuntime,
      );
      addTearDown(manager.dispose);

      await expectLater(
        manager.installRecommended(highestQualityConfig()),
        throwsA(
          isA<TranscriptionException>()
              .having((error) => error.isCancelled, 'isCancelled', isTrue)
              .having(
                (error) => error.message,
                'message',
                'Runtime upgrade cancellation with arbitrary text.',
              ),
        ),
      );

      expect(delegate.installs, hasLength(2));
    },
  );

  test('propagates typed cancellation from runtime inspection', () async {
    final root = await Directory.systemTemp.createTemp('resilient-cancel-');
    addTearDown(() => root.delete(recursive: true));
    final delegate = _FakeAsrRuntimeManager(
      whisperModel: whisperModel,
      ffmpeg: ffmpeg,
      inspectFailure: const TranscriptionException.cancelled(
        'Runtime inspection was cancelled.',
      ),
    );
    final manager = ResilientAsrRuntimeManager(
      delegate: delegate,
      managedRootResolver: () async => root,
    );
    addTearDown(manager.dispose);

    await expectLater(
      manager.installRecommended(highestQualityConfig()),
      throwsA(
        isA<TranscriptionException>().having(
          (error) => error.isCancelled,
          'isCancelled',
          isTrue,
        ),
      ),
    );
    expect(delegate.installs, isEmpty);
  });

  test(
    'cancellation-like text with unknown kind remains an ordinary failure',
    () async {
      final delegate = _FakeAsrRuntimeManager(
        whisperModel: whisperModel,
        ffmpeg: ffmpeg,
        unknownCancellationMessage: true,
      );
      final manager = ResilientAsrRuntimeManager(
        delegate: delegate,
        whisperRuntimeBootstrap: (_) async => whisperRuntime,
      );
      addTearDown(manager.dispose);

      await expectLater(
        manager.installRecommended(highestQualityConfig()),
        throwsA(
          isA<TranscriptionException>()
              .having((error) => error.isCancelled, 'isCancelled', isFalse)
              .having(
                (error) => error.message,
                'message',
                contains('最高质量双引擎准备失败'),
              )
              .having((error) => error.details, 'details', contains('歌词识别已取消')),
        ),
      );

      expect(delegate.installs, hasLength(2));
    },
  );

  test(
    'cancel() produces a typed cancellation after bootstrap returns',
    () async {
      final delegate = _FakeAsrRuntimeManager(
        whisperModel: whisperModel,
        ffmpeg: ffmpeg,
      );
      final bootstrapStarted = Completer<void>();
      final releaseBootstrap = Completer<String?>();
      final manager = ResilientAsrRuntimeManager(
        delegate: delegate,
        whisperRuntimeBootstrap: (_) async {
          bootstrapStarted.complete();
          return releaseBootstrap.future;
        },
      );
      addTearDown(manager.dispose);

      final installing = manager.installRecommended(highestQualityConfig());
      await bootstrapStarted.future;
      await manager.cancel();
      releaseBootstrap.complete(whisperRuntime);

      await expectLater(
        installing,
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.isCancelled,
            'isCancelled',
            isTrue,
          ),
        ),
      );
      expect(delegate.installs, isEmpty);
    },
  );

  test('Whisper-only setup uses standalone bootstrap without Qwen attempt',
      () async {
    final delegate = _FakeAsrRuntimeManager(
      whisperModel: whisperModel,
      ffmpeg: ffmpeg,
    );
    final manager = ResilientAsrRuntimeManager(
      delegate: delegate,
      whisperRuntimeBootstrap: (_) async => whisperRuntime,
    );
    addTearDown(manager.dispose);

    final result = await manager.installRecommended(
      highestQualityConfig().copyWith(mode: TranscriptionMode.whisperOnly),
    );

    expect(delegate.installs, hasLength(1));
    expect(delegate.installs.single.mode, TranscriptionMode.whisperOnly);
    expect(delegate.installs.single.whisperExecutable, whisperRuntime);
    expect(result.mode, TranscriptionMode.whisperOnly);
  });
}

class _FakeAsrRuntimeManager implements AsrRuntimeManager {
  final String whisperModel;
  final String ffmpeg;
  final bool failHighestQuality;
  final bool cancelHighestQuality;
  final bool unknownCancellationMessage;
  final TranscriptionException? inspectFailure;

  final StreamController<AsrRuntimeInstallProgress> _progressController =
      StreamController<AsrRuntimeInstallProgress>.broadcast();
  final List<TranscriptionConfig> installs = [];

  _FakeAsrRuntimeManager({
    required this.whisperModel,
    required this.ffmpeg,
    this.failHighestQuality = false,
    this.cancelHighestQuality = false,
    this.unknownCancellationMessage = false,
    this.inspectFailure,
  });

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream =>
      _progressController.stream;

  @override
  bool get isInstalling => false;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) {
    final failure = inspectFailure;
    if (failure != null) throw failure;
    throw UnimplementedError();
  }

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async {
    installs.add(config);
    _progressController.add(
      const AsrRuntimeInstallProgress(
        progress: 0.5,
        message: 'fake progress',
      ),
    );

    if (config.mode == TranscriptionMode.highestQuality) {
      if (cancelHighestQuality) {
        throw const TranscriptionException.cancelled(
          'Runtime upgrade cancellation with arbitrary text.',
        );
      }
      if (unknownCancellationMessage) {
        throw const TranscriptionException('歌词识别已取消');
      }
      if (failHighestQuality) {
        throw const TranscriptionException('Qwen runtime release unavailable');
      }
    }

    return config.copyWith(
      whisperExecutable: config.whisperExecutable,
      modelPath: whisperModel,
      ffmpegExecutable: ffmpeg,
    );
  }

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async => config;

  @override
  Future<void> cancel() async {}
}
