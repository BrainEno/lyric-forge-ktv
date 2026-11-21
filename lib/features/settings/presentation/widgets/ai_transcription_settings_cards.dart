import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/services/asr_managed_storage_service.dart';
import '../../../transcription/domain/services/asr_runtime_manager.dart';
import '../../../transcription/domain/services/asr_storage_preflight_service.dart';
import '../../../transcription/presentation/widgets/asr_existing_model_actions.dart';
import '../../../transcription/presentation/widgets/asr_install_error_card.dart';
import '../../../transcription/presentation/widgets/asr_install_progress_card.dart';
import '../../../transcription/presentation/widgets/asr_storage_preflight_card.dart';
import 'asr_runtime_overview.dart';
import 'settings_section_card.dart';

/// Wording shared by the AI transcription settings cards.
///
/// Pure functions so the labels can be checked without building a widget.
abstract final class AsrSettingsText {
  static const String retryUnfinished = '重试未完成组件';

  static String componentLabel(AsrRuntimeComponent component) {
    return switch (component) {
      AsrRuntimeComponent.ffmpeg => 'FFmpeg',
      AsrRuntimeComponent.whisperRuntime => 'Whisper runtime',
      AsrRuntimeComponent.whisperModel => 'Whisper 模型',
      AsrRuntimeComponent.qwenRuntime => 'Qwen runtime',
      AsrRuntimeComponent.qwenModel => 'Qwen 模型',
      AsrRuntimeComponent.qwenAligner => 'ForcedAligner',
    };
  }

  static String modeLabel(TranscriptionMode mode) {
    return switch (mode) {
      TranscriptionMode.highestQuality => '最高质量 · Qwen + 对齐 + Whisper fallback',
      TranscriptionMode.whisperOnly => 'Whisper 单模型 · 更省空间',
    };
  }

  /// The models a run will actually use, in a single line.
  static String modelSummary(TranscriptionConfig config) {
    if (config.mode == TranscriptionMode.whisperOnly) {
      final model = config.modelPath.trim().isEmpty
          ? 'Whisper large-v3（待安装）'
          : basename(config.modelPath);
      return '$model · Whisper runtime';
    }

    final qwen = modelDisplay(config.qwenModelPath, 'Qwen3-ASR 1.7B');
    final aligner = modelDisplay(
      config.qwenAlignerModelPath,
      'ForcedAligner 0.6B',
    );
    final whisper = config.modelPath.trim().isEmpty
        ? 'Whisper fallback'
        : '${basename(config.modelPath)} fallback';
    return '$qwen + $aligner + $whisper';
  }

  static String modelDisplay(String pathOrId, String fallback) {
    final value = pathOrId.trim();
    if (value.isEmpty) return fallback;
    if (value.contains('Qwen3-ASR-1.7B')) return 'Qwen3-ASR 1.7B';
    if (value.contains('Qwen3-ASR-0.6B')) return 'Qwen3-ASR 0.6B';
    if (value.contains('ForcedAligner-0.6B')) return 'ForcedAligner 0.6B';
    return basename(value);
  }

  /// Last path segment, for POSIX and Windows separators alike.
  static String basename(String path) {
    final parts = path
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? path : parts.last;
  }

  static String formatBytes(int? bytes) {
    if (bytes == null) return '无法读取';
    if (bytes == 0) return '0 MB';
    final gib = bytes / (1024 * 1024 * 1024);
    if (gib >= 1) return '${gib.toStringAsFixed(gib >= 10 ? 1 : 2)} GB';
    final mib = bytes / (1024 * 1024);
    return '${mib.toStringAsFixed(mib >= 10 ? 0 : 1)} MB';
  }

  /// The 安装状态 tile.
  static String installState({
    required AsrRuntimeStatus? status,
    required bool installing,
  }) {
    if (status?.isReady == true) return '已就绪';
    if (installing) return '正在安装';
    if (status == null) return '未检测';
    return '${status.readyCount}/${status.components.length} 个组件已就绪';
  }

  /// Label of the retry button after a failed install.
  static String retryLabel(AsrRuntimeComponent? failed) {
    if (failed == null) return retryUnfinished;
    return '重试 ${componentLabel(failed)}';
  }

  /// Label of the main install button when no download is running.
  static String installAction({
    required bool ready,
    required bool storageBlocked,
    required bool failed,
    required AsrRuntimeComponent? failedComponent,
  }) {
    if (storageBlocked) return '空间不足';
    if (failed) return retryLabel(failedComponent);
    return ready ? '校验并修复' : '校验并补齐缺失组件';
  }

  static String movingStorage(int copiedBytes, int totalBytes) {
    if (totalBytes <= 0) return '正在迁移识别环境…';
    return '正在迁移 ${formatBytes(copiedBytes)} / ${formatBytes(totalBytes)}';
  }

  /// Rows of the 查看当前路径 list in the advanced card.
  static List<(String, String)> configuredPaths(TranscriptionConfig config) {
    String orUnset(String value) => value.trim().isEmpty ? '未指定' : value;
    return [
      ('Qwen runtime', orUnset(config.qwenExecutable)),
      ('Qwen 模型', orUnset(config.qwenModelPath)),
      ('ForcedAligner', orUnset(config.qwenAlignerModelPath)),
      ('Whisper runtime', orUnset(config.whisperExecutable)),
      ('Whisper 模型', orUnset(config.modelPath)),
      ('FFmpeg', orUnset(config.ffmpegExecutable)),
    ];
  }
}

/// Recommended profile, actual models, install state and the quality plan.
class AsrPlanCard extends StatelessWidget {
  const AsrPlanCard({
    super.key,
    required this.config,
    required this.status,
    required this.loading,
    required this.installing,
    required this.managedBytes,
    required this.onModeChanged,
  });

  final TranscriptionConfig config;
  final AsrRuntimeStatus? status;
  final bool loading;
  final bool installing;
  final int? managedBytes;

  /// Null while something else is running, which disables the selector.
  final ValueChanged<TranscriptionMode>? onModeChanged;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final ready = status?.isReady == true;
    final onModeChanged = this.onModeChanged;
    return SettingsSectionCard(
      icon: Icons.auto_awesome_rounded,
      title: 'AI / 歌词识别',
      subtitle: '这里是桌面端统一的模型与 runtime 管理入口。保存后，工程详情和下一次歌词识别会读取同一份配置。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AsrInfoGrid(
            children: [
              AsrInfoTile(
                label: '当前推荐方案',
                value: status?.profile.label ?? (loading ? '正在检测…' : '尚未检测'),
                detail: status?.profile.description,
              ),
              AsrInfoTile(
                label: '当前实际模型',
                value: AsrSettingsText.modelSummary(config),
              ),
              AsrInfoTile(
                label: '安装状态',
                value: AsrSettingsText.installState(
                  status: status,
                  installing: installing,
                ),
                valueColor: ready ? AppColors.success : null,
              ),
              AsrInfoTile(
                label: '托管环境占用空间',
                value: AsrSettingsText.formatBytes(managedBytes),
                detail: '仅统计 Elysium Player 托管目录；外部手工模型不计入',
              ),
              AsrInfoTile(
                label: '安装目录',
                value: status?.managedRoot ?? '检测后显示',
                selectable: true,
              ),
              AsrInfoTile(
                label: '当前质量方案',
                value: AsrSettingsText.modeLabel(config.mode),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<TranscriptionMode>(
            initialValue: config.mode,
            decoration: const InputDecoration(
              labelText: '质量方案',
              helperText: '切换后立即保存，并作用于下一次识别。',
            ),
            items: const [
              DropdownMenuItem(
                value: TranscriptionMode.highestQuality,
                child: Text('最高质量 · Qwen + ForcedAligner + Whisper fallback'),
              ),
              DropdownMenuItem(
                value: TranscriptionMode.whisperOnly,
                child: Text('Whisper 单模型 · 更省空间'),
              ),
            ],
            onChanged: onModeChanged == null
                ? null
                : (value) {
                    if (value != null && value != config.mode) {
                      onModeChanged(value);
                    }
                  },
          ),
          if (status != null) ...[
            const SizedBox(height: AppSpacing.md),
            AsrComponentList(components: status.components),
          ],
        ],
      ),
    );
  }
}

/// Adopting models that are already on disk and moving the managed folder.
class AsrStorageSettingsCard extends StatelessWidget {
  const AsrStorageSettingsCard({
    super.key,
    required this.ready,
    required this.loading,
    required this.storage,
    required this.location,
    required this.scanningExisting,
    required this.existingModelMessage,
    required this.movingStorage,
    required this.movingCopiedBytes,
    required this.movingTotalBytes,
    required this.onScan,
    this.cleaningLeftovers = false,
    this.leftoverMessage,
    this.onCleanUpLeftovers,
    required this.onPastePath,
    required this.onBrowse,
    required this.onChangeLocation,
    required this.onRestoreDefault,
  });

  final bool ready;
  final bool loading;
  final AsrStoragePreflightResult? storage;
  final AsrManagedStorageLocation? location;
  final bool scanningExisting;
  final String? existingModelMessage;
  final bool movingStorage;
  final int movingCopiedBytes;
  final int movingTotalBytes;

  /// A clean-up of leftover copies is running (D-048).
  final bool cleaningLeftovers;

  /// What the last clean-up did.
  final String? leftoverMessage;

  /// Each action is null while the section is busy.
  final VoidCallback? onCleanUpLeftovers;
  final VoidCallback? onScan;
  final VoidCallback? onPastePath;
  final VoidCallback? onBrowse;
  final VoidCallback? onChangeLocation;
  final VoidCallback? onRestoreDefault;

  @override
  Widget build(BuildContext context) {
    final hintStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return SettingsSectionCard(
      icon: Icons.folder_rounded,
      title: '模型与存储',
      // The separator moved into the same folder (D-049).
      subtitle: '识别、对齐和人声分离的模型都放在下面这一个文件夹里；可识别本机已有的模型，或整体迁移到空间更大的磁盘。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Once everything is installed there is nothing to adopt, unless
          // the last scan left a message worth keeping on screen.
          if (!ready || existingModelMessage != null) ...[
            AsrExistingModelCard(
              scanning: scanningExisting,
              message: existingModelMessage,
              onScan: onScan,
              onPastePath: onPastePath,
              onBrowse: onBrowse,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (AsrLeftoverNotice.showsFor(location, leftoverMessage)) ...[
            AsrLeftoverNotice(
              location: location,
              cleaning: cleaningLeftovers,
              message: leftoverMessage,
              onCleanUp: onCleanUpLeftovers,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AsrStoragePreflightCard(
            result: storage,
            loading: loading,
            onChangeLocation: onChangeLocation,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onChangeLocation,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('迁移当前环境到其他文件夹'),
              ),
              if (location?.isDefault == false)
                TextButton.icon(
                  onPressed: onRestoreDefault,
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('迁回默认位置'),
                ),
              if (movingStorage)
                Text(
                  AsrSettingsText.movingStorage(
                    movingCopiedBytes,
                    movingTotalBytes,
                  ),
                  style: hintStyle,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Download progress, failures and the install, repair and delete actions.
class AsrMaintenanceCard extends StatelessWidget {
  const AsrMaintenanceCard({
    super.key,
    required this.ready,
    required this.loading,
    required this.busy,
    required this.storageBlocked,
    required this.installing,
    required this.paused,
    required this.progress,
    required this.error,
    required this.failedComponent,
    required this.onRefresh,
    required this.onInstall,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onDelete,
  });

  final bool ready;
  final bool loading;

  /// Anything else is running (detection, download, move, delete, scan).
  final bool busy;
  final bool storageBlocked;
  final bool installing;
  final bool paused;
  final AsrRuntimeInstallProgress? progress;
  final String? error;
  final AsrRuntimeComponent? failedComponent;

  final VoidCallback onRefresh;
  final VoidCallback onInstall;
  final VoidCallback onPause;
  final VoidCallback onResume;

  /// Resumes the failed install from the first unfinished component.
  final VoidCallback onRetry;

  /// Deletes the managed models; true reinstalls them straight after.
  final ValueChanged<bool> onDelete;

  bool get _failed => error != null && !paused;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final error = this.error;
    return SettingsSectionCard(
      icon: Icons.build_circle_outlined,
      title: '安装与维护',
      subtitle: '下载、校验、修复或删除识别组件；下载可以暂停后继续。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (progress != null && (installing || paused || error != null)) ...[
            AsrInstallProgressCard(
              progress: progress,
              paused: paused,
              failed: _failed,
              onPause: installing ? onPause : null,
              onResume: paused ? onResume : null,
              onRetry: _failed ? onRetry : null,
              retryLabel: AsrSettingsText.retryLabel(failedComponent),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (error != null) ...[
            AsrInstallErrorCard(message: error),
            const SizedBox(height: AppSpacing.md),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新检测'),
              ),
              _primaryAction(error != null),
              OutlinedButton.icon(
                onPressed: busy ? null : () => onDelete(false),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('删除模型'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => onDelete(true),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('删除并重装模型'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _primaryAction(bool failed) {
    if (installing) {
      return OutlinedButton.icon(
        onPressed: onPause,
        icon: const Icon(Icons.pause_rounded),
        label: const Text('暂停下载'),
      );
    }
    if (paused) {
      return FilledButton.icon(
        onPressed: onResume,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('继续下载'),
      );
    }
    final icon = storageBlocked
        ? Icons.sd_storage_rounded
        : failed
        ? Icons.refresh_rounded
        : Icons.fact_check_outlined;
    return FilledButton.icon(
      onPressed: loading || storageBlocked ? null : onInstall,
      icon: Icon(icon),
      label: Text(
        AsrSettingsText.installAction(
          ready: ready,
          storageBlocked: storageBlocked,
          failed: failed,
          failedComponent: failedComponent,
        ),
      ),
    );
  }
}

/// Read-only list of the configured paths and the manual editor.
class AsrAdvancedSettingsCard extends StatelessWidget {
  const AsrAdvancedSettingsCard({
    super.key,
    required this.config,
    required this.onOpenAdvanced,
  });

  final TranscriptionConfig config;

  /// Null while the section is busy.
  final VoidCallback? onOpenAdvanced;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final labelStyle = text.bodySmall?.copyWith(color: AppColors.textTertiary);
    final valueStyle = text.bodySmall?.copyWith(
      color: AppColors.textSecondary,
      height: 1.5,
    );
    return SettingsSectionCard(
      icon: Icons.tune_rounded,
      title: '高级设置',
      subtitle: '手工选择模型路径、runtime、FFmpeg、设备和精度',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The card paints its own background, which would hide the
          // tile's ink; a transparent Material gives it a surface.
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
              title: const Text('查看当前路径'),
              children: [
                // One label/value row per path instead of a single block of
                // text, so long paths wrap under their own label.
                for (final (label, value) in AsrSettingsText.configuredPaths(
                  config,
                ))
                  _PathRow(
                    label: label,
                    value: value,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: onOpenAdvanced,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('手工选择模型路径和 runtime'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({
    required this.label,
    required this.value,
    required this.labelStyle,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: labelStyle)),
          Expanded(child: SelectableText(value, style: valueStyle)),
        ],
      ),
    );
  }
}
