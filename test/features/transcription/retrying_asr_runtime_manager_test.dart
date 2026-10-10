import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/retrying_asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';

void main() {
  const config = TranscriptionConfig(
    whisperExecutable: 'whisper-cli',
    modelPath: 'ggml-model.bin',
  );

  test('retries transient download failure and preserves visible byte progress',
      () async {
    final delegate = _FakeRuntimeManager(
      onInstall: (attempt, config) async {
        if (attempt == 1) {
          delegateProgress(
            delegate,
            const AsrRuntimeInstallProgress(
              component: AsrRuntimeComponent.qwenModel,
              progress: 0.31,
              message: '正在下载 Qwen3-ASR',
              downloadedBytes: 2 * 1024 * 1024 * 1024,
              totalBytes: 4 * 1024 * 1024 * 1024,
            ),
          );
          throw const TranscriptionException(
            '下载 Qwen3-ASR 失败',
            details: 'SocketException: Connection reset by peer',
          );
        }
        return config;
      },
    );
    final manager = RetryingAsrRuntimeManager(
      delegate: delegate,
      maxAttempts: 3,
      retryDelay: Duration.zero,
    );
    final messages = <String>[];
    final subscription = manager.progressStream.listen(
      (progress) => messages.add(progress.message),
    );

    final installed = await manager.installRecommended(config);

    expect(installed, same(config));
    expect(delegate.installCalls, 2);
    expect(
      messages,
      contains(
        '网络连接中断，将从 2.00 GB / 4.00 GB 继续（第 2/3 次）',
      ),
    );

    await subscription.cancel();
    await manager.dispose();
  });

  test('retries an explicitly incomplete retained part download', () async {
    final delegate = _FakeRuntimeManager(
      onInstall: (attempt, config) async {
        if (attempt == 1) {
          throw const TranscriptionException(
            'Qwen3-ASR 下载未完成，下次将从断点继续',
            details: 'expected=4000, actual=1200',
          );
        }
        return config;
      },
    );
    final manager = RetryingAsrRuntimeManager(
      delegate: delegate,
      retryDelay: Duration.zero,
    );

    await manager.installRecommended(config);

    expect(delegate.installCalls, 2);
    await manager.dispose();
  });

  test('does not retry permission or integrity failures', () async {
    final delegate = _FakeRuntimeManager(
      onInstall: (attempt, config) async {
        throw const TranscriptionException(
          '下载 Qwen3-ASR 失败',
          details: 'PathAccessException: Operation not permitted',
        );
      },
    );
    final manager = RetryingAsrRuntimeManager(
      delegate: delegate,
      retryDelay: Duration.zero,
    );

    await expectLater(
      manager.installRecommended(config),
      throwsA(isA<TranscriptionException>()),
    );

    expect(delegate.installCalls, 1);
    await manager.dispose();
  });
}

void delegateProgress(
  _FakeRuntimeManager delegate,
  AsrRuntimeInstallProgress progress,
) {
  delegate.emit(progress);
}

class _FakeRuntimeManager implements AsrRuntimeManager {
  final Future<TranscriptionConfig> Function(
    int attempt,
    TranscriptionConfig config,
  ) onInstall;

  final StreamController<AsrRuntimeInstallProgress> _progressController =
      StreamController<AsrRuntimeInstallProgress>.broadcast(sync: true);

  int installCalls = 0;
  bool cancelled = false;

  _FakeRuntimeManager({required this.onInstall});

  void emit(AsrRuntimeInstallProgress progress) {
    _progressController.add(progress);
  }

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
  ) {
    installCalls += 1;
    return onInstall(installCalls, config);
  }

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async => config;

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}
