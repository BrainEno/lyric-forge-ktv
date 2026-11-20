import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_runtime_setup_text.dart';

import 'asr_setup_fakes.dart';

void main() {
  group('header', () {
    test('ready wins over installing', () {
      expect(
        AsrSetupText.headerTitle(ready: true, installing: true),
        '本地歌词识别已准备好',
      );
      expect(
        AsrSetupText.headerTitle(ready: false, installing: true),
        '正在准备本地歌词识别',
      );
      expect(
        AsrSetupText.headerTitle(ready: false, installing: false),
        '首次使用，只需完成一次准备',
      );
    });

    test('the subtitle says what happens next', () {
      expect(AsrSetupText.headerSubtitle(ready: true), contains('直接导入歌曲'));
      expect(AsrSetupText.headerSubtitle(ready: false), contains('自动检测电脑'));
    });
  });

  group('steps and cards', () {
    test('both quality modes are offered, recommended first', () {
      expect(AsrSetupText.modes, [
        TranscriptionMode.highestQuality,
        TranscriptionMode.whisperOnly,
      ]);
      expect(
        AsrSetupText.modeOption(TranscriptionMode.highestQuality),
        '最高质量 · 双引擎校对（推荐）',
      );
      expect(
        AsrSetupText.modeOption(TranscriptionMode.whisperOnly),
        'Whisper 单模型 · 更省空间',
      );
    });

    test('the check step and cards follow readiness', () {
      expect(AsrSetupText.checkStepSubtitle(ready: true), contains('匹配完成'));
      expect(AsrSetupText.checkStepSubtitle(ready: false), contains('磁盘空间'));
      expect(AsrSetupText.profileBadge(ready: true), '已就绪');
      expect(AsrSetupText.profileBadge(ready: false), '自动推荐');
      expect(AsrSetupText.componentsTitle(ready: true), '本地组件');
      expect(AsrSetupText.componentsTitle(ready: false), '首次使用需要准备');
    });

    test('every component state has a word', () {
      expect(
        AsrSetupText.componentState(AsrRuntimeComponentState.ready),
        '已准备',
      );
      expect(
        AsrSetupText.componentState(AsrRuntimeComponentState.unavailable),
        '需手动配置',
      );
      for (final state in [
        AsrRuntimeComponentState.missing,
        AsrRuntimeComponentState.installing,
        AsrRuntimeComponentState.failed,
      ]) {
        expect(AsrSetupText.componentState(state), '待准备');
      }
    });
  });

  group('hardware summary', () {
    test('lists the platform, chips and memory', () {
      expect(
        AsrSetupText.hardwareSummary(setupHardware),
        'macos / arm64 · Apple M2 · 16 GB RAM',
      );
    });

    test('includes the graphics card and its memory', () {
      const hardware = TranscriptionHardwareInfo(
        operatingSystem: 'windows',
        architecture: 'x86_64',
        cpuName: 'Ryzen 9',
        gpuName: 'RTX 5080',
        gpuMemoryMb: 16384,
        systemMemoryMb: 65536,
      );
      expect(
        AsrSetupText.hardwareSummary(hardware),
        'windows / x86_64 · Ryzen 9 · RTX 5080 · 16 GB VRAM · 64 GB RAM',
      );
    });

    test('skips blank names', () {
      const hardware = TranscriptionHardwareInfo(
        operatingSystem: 'linux',
        architecture: 'x86_64',
        cpuName: '  ',
        gpuName: '',
      );
      expect(AsrSetupText.hardwareSummary(hardware), 'linux / x86_64');
    });

    test('trims names', () {
      const hardware = TranscriptionHardwareInfo(
        operatingSystem: 'linux',
        architecture: 'arm64',
        cpuName: ' Cortex ',
      );
      expect(AsrSetupText.hardwareSummary(hardware), 'linux / arm64 · Cortex');
    });
  });

  group('sizes', () {
    test('gigabytes have two decimals below ten', () {
      expect(AsrSetupText.formatBytes(3 << 29), '1.50 GB');
      expect(AsrSetupText.formatBytes(1 << 30), '1.00 GB');
    });

    test('gigabytes have one decimal from ten', () {
      expect(AsrSetupText.formatBytes(12 << 30), '12.0 GB');
    });

    test('megabytes below one gigabyte', () {
      expect(AsrSetupText.formatBytes(512 << 20), '512 MB');
      expect(AsrSetupText.formatBytes((7 << 20) ~/ 2), '3.5 MB');
      expect(AsrSetupText.formatBytes(0), '0.0 MB');
    });
  });

  group('install', () {
    test('the retry button names the failed component', () {
      expect(AsrSetupText.retryLabel(null), '重试未完成组件');
      expect(AsrSetupText.retryLabel(AsrRuntimeComponent.ffmpeg), '重试 FFmpeg');
      expect(
        AsrSetupText.retryLabel(AsrRuntimeComponent.qwenAligner),
        '重试 ForcedAligner',
      );
    });

    test('every component has a short name', () {
      final names = {
        for (final component in AsrRuntimeComponent.values)
          AsrSetupText.componentName(component),
      };
      expect(names, hasLength(AsrRuntimeComponent.values.length));
      expect(
        AsrSetupText.componentName(AsrRuntimeComponent.whisperRuntime),
        'Whisper runtime',
      );
    });

    test('the install button says when space is short', () {
      expect(AsrSetupText.installLabel(storageBlocked: true), '空间不足');
      expect(AsrSetupText.installLabel(storageBlocked: false), '校验并准备识别环境');
    });

    test('the shortfall names need, free space and the gap', () {
      final message = AsrSetupText.storageShortfall(
        setupSpace(AsrStoragePreflightState.insufficient),
      );
      expect(
        message,
        '磁盘空间不足：本次安装建议至少可用 4.00 GB，当前可用 1.00 GB，'
        '还差 3.00 GB。请释放空间后点击“重新检测”。',
      );
    });

    test('unknown free space is said as such', () {
      const storage = AsrStoragePreflightResult(
        state: AsrStoragePreflightState.unknown,
        managedRoot: '/runtime',
        estimatedInstalledBytes: 1 << 30,
        existingRelevantBytes: 0,
        temporaryHeadroomBytes: 0,
        safetyMarginBytes: 0,
        requiredAdditionalBytes: 1 << 30,
        availableBytes: null,
        detail: '',
      );
      expect(AsrSetupText.storageShortfall(storage), contains('当前可用 无法读取'));
    });
  });

  group('existing downloads', () {
    test('adopting promises no download', () {
      expect(AsrSetupText.adopting('/a'), contains('此步骤不会下载'));
      expect(AsrSetupText.adopting('/a'), contains('/a'));
    });

    test('adopted follows what the inspection found', () {
      expect(AsrSetupText.adopted('/a', null), contains('请重新检测'));
      expect(
        AsrSetupText.adopted('/a', setupStatus(ready: true)),
        '已启用已有环境：/a。组件已就绪，本次没有下载。',
      );
      final partial = AsrSetupText.adopted('/a', setupStatus(ready: false));
      expect(partial, contains('当前 1/2 个组件就绪'));
      expect(partial, contains('只有缺失或校验失败的组件才会下载'));
    });

    test('a move says whether it copied, switched or left the old folder', () {
      expect(
        AsrSetupText.moved(setupMoved(adoptedExisting: true)),
        contains('没有复制或删除旧目录'),
      );
      expect(
        AsrSetupText.moved(setupMoved(oldRootRetained: true)),
        contains('请稍后手工清理'),
      );
      expect(AsrSetupText.moved(setupMoved()), '识别环境已安全迁移到新位置。');
      expect(AsrSetupText.movedOntoExisting('/b'), contains('/b'));
    });
  });

  test('failures keep their prefixes', () {
    final error = StateError('x');
    expect(AsrSetupText.inspectFailed(error), startsWith('检测识别环境失败：'));
    expect(AsrSetupText.installFailed(error), startsWith('安装识别环境失败：'));
    expect(AsrSetupText.existingFailed(error), startsWith('识别已有模型失败：'));
    expect(AsrSetupText.moveFailed(error), startsWith('更改模型存储位置失败：'));
    expect(AsrSetupText.saveFailed(error), startsWith('保存本地识别设置失败：'));
  });
}
