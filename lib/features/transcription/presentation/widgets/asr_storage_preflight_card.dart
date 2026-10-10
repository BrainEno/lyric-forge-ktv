import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/services/asr_storage_preflight_service.dart';

class AsrStoragePreflightCard extends StatelessWidget {
  final AsrStoragePreflightResult? result;
  final bool loading;
  final VoidCallback? onChangeLocation;

  const AsrStoragePreflightCard({
    super.key,
    required this.result,
    this.loading = false,
    this.onChangeLocation,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && result == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          border: Border.all(color: AppColors.borderMuted),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('正在检查安装磁盘可用空间…')),
          ],
        ),
      );
    }

    final value = result;
    if (value == null) return const SizedBox.shrink();

    final availableBytes = value.availableBytes;
    final insufficient = value.state == AsrStoragePreflightState.insufficient;
    final unknown = value.state == AsrStoragePreflightState.unknown;
    final ready = value.state == AsrStoragePreflightState.ready;
    final notApplicable =
        value.state == AsrStoragePreflightState.notApplicable;
    final accent = insufficient
        ? AppColors.error
        : unknown
            ? AppColors.warning
            : ready
                ? AppColors.success
                : notApplicable
                    ? AppColors.textTertiary
                    : AppColors.accent;
    final icon = insufficient
        ? Icons.sd_storage_rounded
        : unknown
            ? Icons.help_outline_rounded
            : ready
                ? Icons.check_circle_outline_rounded
                : notApplicable
                    ? Icons.tune_rounded
                    : Icons.storage_rounded;
    final title = insufficient
        ? '磁盘空间不足，暂不开始下载'
        : unknown
            ? '无法读取磁盘剩余空间'
            : ready
                ? '识别环境已安装完成'
                : notApplicable
                    ? '自定义安装位置不参与托管预检'
                    : '磁盘空间充足';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withAlpha(12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: accent.withAlpha(56)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value.detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!ready && !notApplicable) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _Metric(
                  label: '预计完整环境',
                  value: _formatBytes(value.estimatedInstalledBytes),
                ),
                _Metric(
                  label: '已存在可复用',
                  value: _formatBytes(value.existingRelevantBytes),
                ),
                _Metric(
                  label: '本次建议至少可用',
                  value: _formatBytes(value.requiredAdditionalBytes),
                ),
                _Metric(
                  label: '当前可用',
                  value: availableBytes == null
                      ? '无法读取'
                      : _formatBytes(availableBytes),
                  emphasis: insufficient,
                ),
                if (insufficient)
                  _Metric(
                    label: '还差',
                    value: _formatBytes(value.shortfallBytes),
                    emphasis: true,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '空间预算包含安装过程临时空间 ${_formatBytes(value.temporaryHeadroomBytes)} '
              '+ 安全余量 ${_formatBytes(value.safetyMarginBytes)}；已下载的目标模型与 .part 断点会计入可复用空间。',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          SelectionArea(
            child: Text(
              '安装目录：${value.managedRoot}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ),
          if (onChangeLocation != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onChangeLocation,
                icon: const Icon(Icons.drive_file_move_outline_rounded),
                label: Text(insufficient ? '换一个磁盘 / 文件夹' : '更改模型存储位置'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    final gib = bytes / (1024 * 1024 * 1024);
    if (gib >= 1) return '${gib.toStringAsFixed(gib >= 10 ? 1 : 2)} GB';
    final mib = bytes / (1024 * 1024);
    if (mib >= 1) return '${mib.toStringAsFixed(mib >= 100 ? 0 : 1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;

  const _Metric({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSurface.withAlpha(190),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: emphasis ? AppColors.error : null,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
