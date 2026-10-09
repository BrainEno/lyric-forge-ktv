import 'dart:async';

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

  test('falls back to ready Whisper config when Qwen upgrade fails', () async {
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

    final result = await manager.installRecommended(highestQualityConfig());

    expect(delegate.installs, hasLength(2));
    expect(result.mode, TranscriptionMode.whisperOnly);
    expect(result.whisperExecutable, whisperRuntime);
    expect(result.modelPath, whisperModel);
    expect(result.ffmpegExecutable, ffmpeg);
  });

  test('does not swallow cancellation during highest-quality upgrade', () async {
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
        isA<TranscriptionException>().having(
          (error) => error.message,
          'message',
          contains('取消'),
        ),
      ),
    );

    expect(delegate.installs, hasLength(2));
  });

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

  final StreamController<AsrRuntimeInstallProgress> _progressController =
      StreamController<AsrRuntimeInstallProgress>.broadcast();
  final List<TranscriptionConfig> installs = [];

  _FakeAsrRuntimeManager({
    required this.whisperModel,
    required this.ffmpeg,
    this.failHighestQuality = false,
    this.cancelHighestQuality = false,
  });

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream =>
      _progressController.stream;

  @override
  bool get isInstalling => false;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) {
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
        throw const TranscriptionException('识别环境安装已取消');
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
