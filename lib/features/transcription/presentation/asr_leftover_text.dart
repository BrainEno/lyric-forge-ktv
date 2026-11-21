import '../domain/services/asr_managed_storage_service.dart';
import 'asr_folder_text.dart';
import 'widgets/asr_runtime_setup_text.dart';

/// The wording of D-048: what was taken over from a nested copy when an
/// existing environment was adopted, the leftover copies of the environment
/// and their clean-up.
///
/// Shared by the setup dialog and 设置 → 本地识别; settings reaches it
/// through asr_existing_model_actions.dart.
abstract final class AsrLeftoverText {
  /// The name of [unit] as the component list writes it.
  static String unitLabel(AsrRuntimeUnit unit) => switch (unit) {
    AsrRuntimeUnit.runtime => '识别程序',
    AsrRuntimeUnit.whisperRuntime => 'Whisper 程序',
    AsrRuntimeUnit.ffmpeg => 'FFmpeg',
    AsrRuntimeUnit.whisperModel => 'Whisper large-v3 模型',
    AsrRuntimeUnit.qwenAsrLarge => 'Qwen3-ASR 1.7B 模型',
    AsrRuntimeUnit.qwenAsrSmall => 'Qwen3-ASR 0.6B 模型',
    AsrRuntimeUnit.forcedAligner => 'Qwen3 强制对齐模型',
  };

  /// [units] joined the way a Chinese list is.
  static String unitList(Iterable<AsrRuntimeUnit> units) =>
      units.map(unitLabel).join('、');

  /// What to add to the "adopted" message after [result]; empty when the
  /// adoption only switched the pointer.
  static String adoptionNote(AsrManagedStorageMoveResult result) {
    final parts = <String>[];
    if (result.movedUnits.isNotEmpty) {
      parts.add(
        '已把内层重复文件夹里下载好的${unitList(result.movedUnits)}'
        '移到这里直接使用（同一磁盘内移动，没有复制或重新下载）。',
      );
    }
    if (result.otherRoots.isNotEmpty) {
      parts.add('另外在 ${result.otherRoots.join('、')} 也找到识别环境，未使用、未改动。');
    }
    return parts.join();
  }

  /// [message] followed by the note for [result], if any.
  static String withAdoptionNote(
    String message,
    AsrManagedStorageMoveResult result,
  ) {
    final note = adoptionNote(result);
    return note.isEmpty ? message : '$message$note';
  }

  /// Title of the leftover notice.
  static String title(AsrManagedStorageLocation location) {
    final bytes = location.reclaimableBytes;
    if (bytes <= 0) return '发现重复的识别环境文件夹';
    return '发现重复的识别环境文件夹，可释放约 ${AsrSetupText.formatBytes(bytes)}';
  }

  /// One line per leftover.
  static String line(AsrRuntimeLeftover leftover) {
    final size = leftover.isEmpty
        ? '只有空文件夹'
        : AsrSetupText.formatBytes(leftover.bytes);
    final missing = leftover.missingInActive;
    switch (leftover.kind) {
      case AsrRuntimeLeftoverKind.nestedCopy:
        final carry = missing.isEmpty
            ? '其中的组件当前环境都已具备，可以直接删除。'
            : '其中的${unitList(missing)}当前环境还没有，清理时会先移过来再删除，不会重新下载。';
        return '内层重复的 ${AsrFolderText.folder}：${leftover.path}（$size）。'
            '这是旧版本误建的文件夹，$carry';
      case AsrRuntimeLeftoverKind.activeIsNested:
        return '当前正在使用内层重复的文件夹 ${leftover.path}（$size）。'
            '清理时会把其中的组件移回外层 ${outerOf(leftover.path)} 并改用外层，'
            '再删除内层，不会重新下载。';
      case AsrRuntimeLeftoverKind.defaultCopy:
        final verdict = missing.isEmpty
            ? '当前环境已经有这些组件，可以删除。'
            : '其中的${unitList(missing)}当前环境还没有，清理时会保留这个文件夹。';
        return '默认位置的旧环境：${leftover.path}（$size）。$verdict';
      case AsrRuntimeLeftoverKind.migrationStaging:
        return '迁移中断留下的暂存文件夹：${leftover.path}（$size），可以删除。';
    }
  }

  /// The folder an older build nested [nestedPath] in: [nestedPath] without
  /// its trailing `LyricForge/ASRRuntime`.
  static String outerOf(String nestedPath) {
    final suffix = '${AsrFolderText.separator}${AsrFolderText.folder}';
    final trimmed = nestedPath.replaceAll(RegExp(r'[/\\]+$'), '');
    if (trimmed.toLowerCase().endsWith(suffix.toLowerCase())) {
      return trimmed.substring(0, trimmed.length - suffix.length);
    }
    return trimmed;
  }

  /// Label of the clean-up button.
  static const String cleanUpLabel = '合并并清理';

  /// Label of the button while cleaning.
  static const String cleaningLabel = '正在清理…';

  /// Title of the confirmation.
  static const String confirmTitle = '清理重复的识别环境？';

  /// Body of the confirmation.
  static String confirmation(AsrManagedStorageLocation location) {
    final lines = [
      for (final leftover in location.leftovers) '• ${line(leftover)}',
    ];
    return '${lines.join('\n')}\n\n'
        '当前环境缺少、而重复文件夹里已经下载好的组件会先在同一磁盘内移过来；'
        '只删除当前环境已经具备的重复文件。清理期间不能开始识别或下载。';
  }

  /// The confirmation's action.
  static const String confirmAction = '开始清理';

  /// What the clean-up did.
  static String cleanedUp(AsrRuntimeCleanupResult result) {
    final parts = <String>[];
    if (result.movedUnits.isNotEmpty) {
      parts.add('已把${unitList(result.movedUnits)}移入当前环境');
    }
    if (result.removedPaths.isNotEmpty) {
      parts.add(
        '删除了 ${result.removedPaths.length} 个重复文件夹，'
        '释放 ${AsrSetupText.formatBytes(result.freedBytes)}',
      );
    }
    if (parts.isEmpty && result.retainedPaths.isEmpty) {
      return '没有需要清理的重复文件夹。';
    }
    final summary = parts.isEmpty ? '' : '${parts.join('，')}。';
    if (result.retainedPaths.isEmpty) return '$summary当前环境：${result.activeRoot}。';
    return '$summary以下文件夹已保留：${result.retainedPaths.join('、')}'
        '（含有当前环境没有的组件，或有文件正在使用；关闭正在运行的识别后可以再清理一次）。';
  }

  /// When the clean-up failed as a whole.
  static String cleanupFailed(Object error) => '清理重复的识别环境失败：$error';
}
