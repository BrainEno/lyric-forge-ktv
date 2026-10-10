import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';

void main() {
  test('install progress carries real transfer metrics without breaking old events', () {
    const legacy = AsrRuntimeInstallProgress(
      progress: 0.2,
      message: 'legacy',
    );
    const rich = AsrRuntimeInstallProgress(
      component: AsrRuntimeComponent.qwenModel,
      progress: 0.5,
      message: 'download',
      downloadedBytes: 512,
      totalBytes: 1024,
      bytesPerSecond: 256,
      estimatedRemaining: Duration(seconds: 2),
    );

    expect(legacy.hasTransferMetrics, isFalse);
    expect(rich.hasTransferMetrics, isTrue);
    expect(rich.downloadedBytes, 512);
    expect(rich.totalBytes, 1024);
    expect(rich.bytesPerSecond, 256);
    expect(rich.estimatedRemaining, const Duration(seconds: 2));
  });

  test('runtime and Qwen downloaders emit bytes, speed and ETA', () {
    final runtime = File(
      'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
    ).readAsStringSync();
    final qwen = File(
      'lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart',
    ).readAsStringSync();

    for (final source in [runtime, qwen]) {
      expect(source, contains('downloadedBytes:'));
      expect(source, contains('totalBytes:'));
      expect(source, contains('bytesPerSecond:'));
      expect(source, contains('estimatedRemaining:'));
      expect(source, contains('Stopwatch()..start()'));
    }
    expect(qwen, contains('progress.downloadedBytes'));
    expect(qwen, contains('progress.estimatedRemaining'));
  });

  test('setup and settings use resumable pause, continue and failed-component retry', () {
    final setup = File(
      'lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart',
    ).readAsStringSync();

    for (final source in [setup, settings]) {
      expect(source, contains('AsrInstallProgressCard('));
      expect(source, contains('_pauseRequested'));
      expect(source, contains('await _runtimeManager.cancel()'));
      expect(source, contains('_install(resume: true)'));
      expect(source, contains('重试未完成组件'));
      expect(source, contains('_failedComponent'));
    }

    expect(setup, contains('暂停下载'));
    expect(setup, contains('继续下载'));
    expect(settings, contains('暂停下载'));
    expect(settings, contains('继续下载'));
  });

  test('rich progress card exposes component, bytes, speed and ETA copy', () {
    final card = File(
      'lib/features/transcription/presentation/widgets/asr_install_progress_card.dart',
    ).readAsStringSync();

    expect(card, contains('_componentLabel(progress.component)'));
    expect(card, contains('_formatBytes(downloaded)'));
    expect(card, contains('_formatSpeed(progress.bytesPerSecond!)'));
    expect(card, contains('_formatDuration(progress.estimatedRemaining!)'));
    expect(card, contains('断点已保留'));
    expect(card, contains('已完成组件会自动复用'));
  });
}
