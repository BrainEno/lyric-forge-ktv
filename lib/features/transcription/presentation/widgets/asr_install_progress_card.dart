import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/services/asr_runtime_manager.dart';

class AsrInstallProgressCard extends StatelessWidget {
  final AsrRuntimeInstallProgress progress;
  final bool paused;
  final bool failed;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onRetry;
  final String? retryLabel;

  const AsrInstallProgressCard({
    super.key,
    required this.progress,
    this.paused = false,
    this.failed = false,
    this.onPause,
    this.onResume,
    this.onRetry,
    this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final overall = progress.progress.clamp(0.0, 1.0).toDouble();
    final component = _componentLabel(progress.component);
    final downloaded = progress.downloadedBytes;
    final total = progress.totalBytes;
    final hasTransfer = downloaded != null && total != null && total > 0;
    final transferFraction = hasTransfer
        ? (downloaded / total).clamp(0.0, 1.0).toDouble()
        : null;
    final accent = failed
        ? AppColors.error
        : paused
            ? AppColors.warning
            : AppColors.accent;

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
            children: [
              Icon(
                failed
                    ? Icons.error_outline_rounded
                    : paused
                        ? Icons.pause_circle_outline_rounded
                        : Icons.downloading_rounded,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  failed
                      ? '当前组件需要重试'
                      : paused
                          ? '下载已暂停，断点已保留'
                          : '正在准备 · $component',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                '${(overall * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: overall,
            minHeight: 6,
            backgroundColor: AppColors.bgHighlight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(progress.message, style: Theme.of(context).textTheme.bodySmall),
          if (hasTransfer) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatBytes(downloaded)} / ${_formatBytes(total)}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (progress.bytesPerSecond != null &&
                    progress.bytesPerSecond! > 0)
                  Text(
                    _formatSpeed(progress.bytesPerSecond!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                if (progress.estimatedRemaining != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    '约 ${_formatDuration(progress.estimatedRemaining!)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            LinearProgressIndicator(
              value: transferFraction,
              minHeight: 3,
              backgroundColor: AppColors.bgHighlight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            paused
                ? '继续后会从现有 .part 文件断点续传，不会重新下载已经完成的内容。'
                : '模型文件较大；已完成组件会自动复用，失败重试只会继续未完成部分。',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
          if (onPause != null || onResume != null || onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (onPause != null)
                  OutlinedButton.icon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause_rounded, size: 18),
                    label: const Text('暂停下载'),
                  ),
                if (onResume != null)
                  FilledButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('继续下载'),
                  ),
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(retryLabel ?? '重试当前组件'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _componentLabel(AsrRuntimeComponent? component) {
    return switch (component) {
      AsrRuntimeComponent.ffmpeg => 'FFmpeg',
      AsrRuntimeComponent.whisperRuntime => 'Whisper runtime',
      AsrRuntimeComponent.whisperModel => 'Whisper large-v3',
      AsrRuntimeComponent.qwenRuntime => 'Qwen3-ASR runtime',
      AsrRuntimeComponent.qwenModel => 'Qwen3-ASR 模型',
      AsrRuntimeComponent.qwenAligner => 'ForcedAligner',
      null => '安装环境',
    };
  }

  static String _formatBytes(int bytes) {
    final gib = bytes / (1024 * 1024 * 1024);
    if (gib >= 1) return '${gib.toStringAsFixed(gib >= 10 ? 1 : 2)} GB';
    final mib = bytes / (1024 * 1024);
    if (mib >= 1) return '${mib.toStringAsFixed(mib >= 100 ? 0 : 1)} MB';
    final kib = bytes / 1024;
    return '${kib.toStringAsFixed(0)} KB';
  }

  static String _formatSpeed(double bytesPerSecond) {
    final mib = bytesPerSecond / (1024 * 1024);
    if (mib >= 1) return '${mib.toStringAsFixed(mib >= 10 ? 1 : 2)} MB/s';
    final kib = bytesPerSecond / 1024;
    return '${kib.toStringAsFixed(0)} KB/s';
  }

  static String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 24 * 60 * 60);
    if (seconds >= 3600) {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}小时${minutes > 0 ? '$minutes分' : ''}';
    }
    if (seconds >= 60) {
      return '${seconds ~/ 60}分${seconds % 60}秒';
    }
    return '${seconds}秒';
  }
}
