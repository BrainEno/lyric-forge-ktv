import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_managed_storage_service.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/asr_storage_preflight_service.dart';

/// The wording of the first-run speech recognition setup dialog (audit I-03).
///
/// The dialog was one 957-line file in which these sentences sat inside the
/// build method and the flows, next to `setState` calls. They are kept here
/// so they can be tested on their own and read in one place; the cards
/// (asr_runtime_setup_cards.dart) and the controller
/// (asr_runtime_setup_controller.dart) only call them.
abstract final class AsrSetupText {
  // Header.

  static String headerTitle({required bool ready, required bool installing}) {
    if (ready) return '本地歌词识别已准备好';
    if (installing) return '正在准备本地歌词识别';
    return '首次使用，只需完成一次准备';
  }

  static String headerSubtitle({required bool ready}) => ready
      ? '之后可以直接导入歌曲并在后台生成歌词。'
      : 'Elysium Player 会自动检测电脑、下载所需组件并完成配置。';

  // Step 1: the plan.

  static const String chooseStepTitle = '选择识别方案';
  static const String chooseStepSubtitle =
      '大多数电脑保持推荐选项即可，模型和路径由 Elysium Player 自动处理。';
  static const String modeLabel = '质量模式';

  /// The quality modes in the order the menu lists them.
  static const List<TranscriptionMode> modes = [
    TranscriptionMode.highestQuality,
    TranscriptionMode.whisperOnly,
  ];

  static String modeOption(TranscriptionMode mode) => switch (mode) {
    TranscriptionMode.highestQuality => '最高质量 · 双引擎校对（推荐）',
    TranscriptionMode.whisperOnly => 'Whisper 单模型 · 更省空间',
  };

  // Step 2: this computer.

  static const String checkStepTitle = '检查这台电脑';

  static String checkStepSubtitle({required bool ready}) =>
      ready ? '硬件与本地识别组件已经匹配完成。' : '自动检查硬件、模型组合和安装磁盘空间。';

  static const String inspecting = '正在检测电脑配置和已有模型…';

  static String profileBadge({required bool ready}) => ready ? '已就绪' : '自动推荐';

  static String componentsTitle({required bool ready}) =>
      ready ? '本地组件' : '首次使用需要准备';

  /// Ready and unavailable have their own words; everything else is still
  /// to be prepared, including a component that failed last time.
  static String componentState(AsrRuntimeComponentState state) =>
      switch (state) {
        AsrRuntimeComponentState.ready => '已准备',
        AsrRuntimeComponentState.unavailable => '需手动配置',
        AsrRuntimeComponentState.missing ||
        AsrRuntimeComponentState.installing ||
        AsrRuntimeComponentState.failed => '待准备',
      };

  /// e.g. `macos / arm64 · Apple M2 · 16 GB RAM`; blank names are skipped.
  static String hardwareSummary(TranscriptionHardwareInfo hardware) {
    final cpu = hardware.cpuName?.trim();
    final gpu = hardware.gpuName?.trim();
    final gpuMemory = hardware.gpuMemoryMb;
    final systemMemory = hardware.systemMemoryMb;
    return <String>[
      '${hardware.operatingSystem} / ${hardware.architecture}',
      if (cpu != null && cpu.isNotEmpty) cpu,
      if (gpu != null && gpu.isNotEmpty) gpu,
      if (gpuMemory != null) '${(gpuMemory / 1024).toStringAsFixed(0)} GB VRAM',
      if (systemMemory != null)
        '${(systemMemory / 1024).toStringAsFixed(0)} GB RAM',
    ].join(' · ');
  }

  static const String hint =
      '普通使用不需要理解模型目录层级。可以先一键识别本机已有模型；若仍有组件缺失，再校验并只补齐缺失部分。';

  // Install.

  static const String checkingExisting =
      '正在检查已有组件并校验本地文件；只有缺失或校验失败的文件才会下载';

  /// The short name of a component in the retry button.
  static String componentName(AsrRuntimeComponent component) =>
      switch (component) {
        AsrRuntimeComponent.ffmpeg => 'FFmpeg',
        AsrRuntimeComponent.whisperRuntime => 'Whisper runtime',
        AsrRuntimeComponent.whisperModel => 'Whisper 模型',
        AsrRuntimeComponent.qwenRuntime => 'Qwen runtime',
        AsrRuntimeComponent.qwenModel => 'Qwen 模型',
        AsrRuntimeComponent.qwenAligner => 'ForcedAligner',
      };

  static String retryLabel(AsrRuntimeComponent? failed) =>
      failed == null ? '重试未完成组件' : '重试 ${componentName(failed)}';

  static String installLabel({required bool storageBlocked}) =>
      storageBlocked ? '空间不足' : '校验并准备识别环境';

  /// 1.50 GB, 12.0 GB, 512 MB or 3.5 MB.
  static String formatBytes(int bytes) {
    final gib = bytes / (1024 * 1024 * 1024);
    if (gib >= 1) return '${gib.toStringAsFixed(gib >= 10 ? 1 : 2)} GB';
    final mib = bytes / (1024 * 1024);
    return '${mib.toStringAsFixed(mib >= 100 ? 0 : 1)} MB';
  }

  /// Why the install did not start when [storage] says it would not fit.
  static String storageShortfall(AsrStoragePreflightResult storage) {
    final available = storage.availableBytes;
    return '磁盘空间不足：本次安装建议至少可用 '
        '${formatBytes(storage.requiredAdditionalBytes)}，'
        '当前可用 ${available == null ? '无法读取' : formatBytes(available)}，'
        '还差 ${formatBytes(storage.shortfallBytes)}。'
        '请释放空间后点击“重新检测”。';
  }

  // Existing downloads and the storage location.

  /// Shown while the components below an adopted [root] are inspected.
  static String adopting(String root) => '已找到已有环境：$root。正在重新检测组件；此步骤不会下载。';

  /// What the existing-model card says once the environment at [root] was
  /// taken over, given the [status] inspected afterwards.
  static String adopted(String root, AsrRuntimeStatus? status) {
    if (status == null) {
      return '已找到并使用已有环境：$root。请重新检测确认各组件状态。';
    }
    if (status.isReady) return '已启用已有环境：$root。组件已就绪，本次没有下载。';
    return '已找到并使用已有环境：$root。当前 '
        '${status.readyCount}/${status.components.length} 个组件就绪；'
        '点击“校验并准备识别环境”时会先校验已有文件，只有缺失或校验失败的'
        '组件才会下载。';
  }

  /// The existing-model note after a move found an environment at [root].
  static String movedOntoExisting(String root) =>
      '已识别并使用现有识别环境：$root；没有复制或删除旧目录。';

  /// The snack bar after a move of the managed environment finished.
  static String moved(AsrManagedStorageMoveResult result) {
    if (result.adoptedExisting) return '已识别并使用现有的识别环境；没有复制或删除旧目录。';
    if (result.oldRootRetained) return '识别环境已切换到新位置；旧目录未能自动删除，请稍后手工清理。';
    return '识别环境已安全迁移到新位置。';
  }

  // Failures.

  static String inspectFailed(Object error) => '检测识别环境失败：$error';
  static String installFailed(Object error) => '安装识别环境失败：$error';
  static String existingFailed(Object error) => '识别已有模型失败：$error';
  static String moveFailed(Object error) => '更改模型存储位置失败：$error';
  static String saveFailed(Object error) => '保存本地识别设置失败：$error';
}
