import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_install_error_card.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_install_progress_card.dart';

void main() {
  test(
    'install progress carries real transfer metrics without breaking old events',
    () {
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
    },
  );

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
    expect(qwen, contains(r'${_percent(modelFraction)}'));
  });

  test(
    'setup and settings use resumable pause, continue and failed-component retry',
    () {
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
      expect(
        settings,
        contains('_loading || _installing || _paused || _deleting'),
      );
    },
  );

  test('advanced setup settings persist before the install dialog can retry', () {
    final setup = File(
      'lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart',
    ).readAsStringSync();
    final save = setup.indexOf('await _settingsStore.save(updated);');
    final apply = setup.indexOf('setState(() => _config = updated);', save);
    final refresh = setup.indexOf('await _refresh();', apply);

    expect(save, greaterThanOrEqualTo(0));
    expect(apply, greaterThan(save));
    expect(refresh, greaterThan(apply));
    expect(setup, contains('保存本地识别设置失败：'));
  });

  test(
    'advanced settings can save proxy without a complete model configuration',
    () {
      final dialog = File(
        'lib/features/transcription/presentation/widgets/transcription_config_dialog.dart',
      ).readAsStringSync();
      final setup = File(
        'lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart',
      ).readAsStringSync();

      expect(dialog, contains('保存代理并退出'));
      expect(dialog, contains('下载代理可以单独保存'));
      expect(dialog, contains('缺少：'));
      expect(dialog, isNot(contains('ScaffoldMessenger.of(context)')));
      expect(dialog, contains('await _downloadProxyStore.saveDownloadProxy'));
      expect(setup, contains('if (updated.isConfigured)'));
    },
  );

  test('Qwen failures stay visible and model settings are accessible from the dashboard', () {
    final runtime = File(
      'lib/features/transcription/data/services/resilient_asr_runtime_manager.dart',
    ).readAsStringSync();
    final dashboard = File(
      'lib/features/home/presentation/screens/dashboard_screen.dart',
    ).readAsStringSync();
    final setup = File(
      'lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart',
    ).readAsStringSync();
    final checker = File(
      'lib/features/transcription/data/services/asr_download_connection_checker.dart',
    ).readAsStringSync();

    expect(runtime, contains('没有切换识别方案'));
    expect(dashboard, contains("tooltip: '更多'"));
    expect(dashboard, contains('Icons.more_horiz_rounded'));
    expect(dashboard, contains("Text('模型高级设置')"));
    expect(dashboard, contains('onOpenModelSettings: _openModelSettings'));
    expect(setup, isNot(contains("tooltip: '打开模型高级设置'")));
    expect(setup, contains("Text('高级设置')"));
    expect(checker, contains('manualProxy: proxyOverride'));
    expect(checker, contains("HttpHeaders.rangeHeader, 'bytes=0-0'"));
    expect(checker, contains('HttpStatus.partialContent'));
    expect(checker, contains('request.followRedirects = false'));
    expect(checker, contains('HuggingFaceFileMetadata.fromHeaders(headers)'));
    expect(checker, contains('fromModelScopeManifest'));
    expect(checker, contains('modelScopeAlignerManifestAvailable'));
    expect(checker, contains('modelScopeAlignerFileAvailable'));
    expect(checker, contains('qwenModelId ='));
    expect(checker, contains('alignerModelId ='));
    expect(checker, contains('ForcedAligner 模型'));
  });

  test('rich progress card exposes component, bytes, speed and ETA copy', () {
    final card = File(
      'lib/features/transcription/presentation/widgets/asr_install_progress_card.dart',
    ).readAsStringSync();

    expect(card, contains('_componentLabel(progress.component)'));
    expect(card, contains('_formatBytes(downloaded)'));
    expect(card, contains('_formatBytes(total)'));
    expect(card, contains('_formatSpeed(progress.bytesPerSecond!)'));
    expect(card, contains('_formatDuration(progress.estimatedRemaining!)'));
    expect(card, contains('断点已保留'));
    expect(card, contains('已完成组件会自动复用'));
    expect(card, contains('整体环境准备进度（估算）'));
    expect(card, contains('失败时的环境准备进度（估算）'));
    expect(card, contains('0.99'));
    expect(card, contains('当前文件下载'));
    expect(card, contains('上方是整个识别环境的估算进度'));
    final errorCard = File(
      'lib/features/transcription/presentation/widgets/asr_install_error_card.dart',
    ).readAsStringSync();
    expect(errorCard, contains('SelectionArea('));
    expect(errorCard, contains('Clipboard.setData'));
    expect(errorCard, contains('复制诊断详情'));
  });

  testWidgets('displays environment and current file progress separately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: AsrInstallProgressCard(
            progress: AsrRuntimeInstallProgress(
              component: AsrRuntimeComponent.whisperModel,
              progress: 0.25,
              message: '正在下载 Whisper large-v3',
              downloadedBytes: 30 * 1024 * 1024,
              totalBytes: 100 * 1024 * 1024,
              bytesPerSecond: 2 * 1024 * 1024,
              estimatedRemaining: Duration(seconds: 35),
            ),
          ),
        ),
      ),
    );

    expect(find.text('整体环境准备进度（估算）'), findsOneWidget);
    expect(find.text('当前文件下载'), findsOneWidget);
    expect(find.text('正在下载 · Whisper large-v3'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('30.0 MB / 100 MB'), findsOneWidget);
  });
  testWidgets('failed installs cannot display a completed progress state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: AsrInstallProgressCard(
            failed: true,
            progress: AsrRuntimeInstallProgress(
              component: AsrRuntimeComponent.qwenModel,
              progress: 1,
              message: 'chat_template.json size mismatch',
            ),
          ),
        ),
      ),
    );

    expect(find.text('失败时的环境准备进度（估算）'), findsOneWidget);
    expect(find.text('99% · 未完成'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
  });

  testWidgets('diagnostic card keeps long details selectable and offers copy', (
    tester,
  ) async {
    const details =
        'Qwen3-ASR chat_template.json expected=206 actual=1161; '
        'ModelScope manifest SHA-256 validation required';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: AsrInstallErrorCard(message: details),
        ),
      ),
    );

    expect(find.text('暂时无法完成准备'), findsOneWidget);
    expect(find.text(details), findsOneWidget);
    expect(find.text('复制诊断详情'), findsOneWidget);
  });

}
