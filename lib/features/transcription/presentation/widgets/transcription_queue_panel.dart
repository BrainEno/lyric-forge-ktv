import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/transcription_queue_models.dart';
import '../../domain/services/batch_transcription_queue.dart';

class TranscriptionQueuePanel extends StatelessWidget {
  final BatchTranscriptionQueue? queue;

  const TranscriptionQueuePanel({super.key, this.queue});

  @override
  Widget build(BuildContext context) {
    final service = queue ?? ServiceLocatorGlobal.I.transcriptionQueue;
    return StreamBuilder<TranscriptionQueueSnapshot>(
      stream: service.snapshots,
      initialData: service.current,
      builder: (context, snapshot) {
        final state = snapshot.data ?? service.current;
        if (state.items.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            ),
            child: const Text('解析队列为空。选择音频或整个文件夹后，可让 LyricForge 逐首生成歌词。'),
          );
        }

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '后台解析队列',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  _CountChip(label: '等待 ${state.queuedCount}'),
                  _CountChip(label: '完成 ${state.completedCount}'),
                  if (state.failedCount > 0)
                    _CountChip(label: '失败 ${state.failedCount}'),
                  if (state.isPaused)
                    _CountChip(
                      label: state.isProcessing ? '正在暂停...' : '已暂停',
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (state.isPaused)
                    FilledButton.tonalIcon(
                      onPressed: state.isProcessing
                          ? null
                          : () => service.resume(),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        state.isProcessing ? '正在保存进度...' : '继续队列',
                      ),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: state.isProcessing
                          ? () => service.pause()
                          : null,
                      icon: const Icon(Icons.pause),
                      label: const Text('暂停'),
                    ),
                  if (state.failedCount > 0)
                    OutlinedButton.icon(
                      onPressed: () => service.retryFailed(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试失败项'),
                    ),
                  if (state.completedCount > 0)
                    TextButton.icon(
                      onPressed: () => service.clearCompleted(),
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('清理已完成'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (final item in state.items) ...[
                _QueueItemTile(item: item, queue: service),
                if (item != state.items.last)
                  const Divider(height: AppSpacing.lg),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;

  const _CountChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _QueueItemTile extends StatelessWidget {
  final TranscriptionQueueItem item;
  final BatchTranscriptionQueue queue;

  const _QueueItemTile({required this.item, required this.queue});

  @override
  Widget build(BuildContext context) {
    final running = item.status == TranscriptionQueueItemStatus.running;
    final failed = item.status == TranscriptionQueueItemStatus.failed;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            _icon(item.status),
            size: 20,
            color: _color(item.status),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.projectName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                item.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: failed ? AppColors.error : AppColors.textTertiary,
                    ),
              ),
              if (running) ...[
                const SizedBox(height: AppSpacing.xs),
                LinearProgressIndicator(
                  value: item.progress.clamp(0.0, 1.0).toDouble(),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
                ),
              ],
              if (failed && item.error != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.error,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (!running)
          IconButton(
            tooltip: '从队列移除',
            onPressed: () => queue.remove(item.id),
            icon: const Icon(Icons.close, size: 18),
          ),
      ],
    );
  }

  IconData _icon(TranscriptionQueueItemStatus status) {
    return switch (status) {
      TranscriptionQueueItemStatus.queued => Icons.schedule,
      TranscriptionQueueItemStatus.running => Icons.auto_awesome,
      TranscriptionQueueItemStatus.paused => Icons.pause_circle_outline,
      TranscriptionQueueItemStatus.completed => Icons.check_circle_outline,
      TranscriptionQueueItemStatus.failed => Icons.error_outline,
    };
  }

  Color _color(TranscriptionQueueItemStatus status) {
    return switch (status) {
      TranscriptionQueueItemStatus.queued => AppColors.textTertiary,
      TranscriptionQueueItemStatus.running => AppColors.accent,
      TranscriptionQueueItemStatus.paused => AppColors.warning,
      TranscriptionQueueItemStatus.completed => AppColors.accent,
      TranscriptionQueueItemStatus.failed => AppColors.error,
    };
  }
}
