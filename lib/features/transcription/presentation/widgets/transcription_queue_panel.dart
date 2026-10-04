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
          return const _EmptyQueueState();
        }

        final running = _firstWithStatus(
          state.items,
          TranscriptionQueueItemStatus.running,
        );
        final total = state.items.length;
        final overall = total == 0
            ? 0.0
            : ((state.completedCount + (running?.progress ?? 0)) / total)
                .clamp(0.0, 1.0)
                .toDouble();

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            border: Border.all(color: AppColors.borderMuted),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMedium),
                    ),
                    child: Icon(
                      state.isPaused
                          ? Icons.pause_rounded
                          : Icons.queue_music_rounded,
                      color: state.isPaused
                          ? AppColors.warning
                          : AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '后台解析队列',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _summaryText(state, running),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusBadge(
                    label: state.isPaused
                        ? (state.isProcessing ? '正在暂停' : '已暂停')
                        : (state.isProcessing ? '处理中' : '等待中'),
                    color: state.isPaused
                        ? AppColors.warning
                        : AppColors.accent,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: overall,
                      minHeight: 4,
                      backgroundColor: AppColors.bgHighlight,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusCircular),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${(overall * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _CountPill(
                    icon: Icons.schedule_rounded,
                    label: '等待 ${state.queuedCount}',
                  ),
                  _CountPill(
                    icon: Icons.check_rounded,
                    label: '完成 ${state.completedCount}',
                  ),
                  if (state.failedCount > 0)
                    _CountPill(
                      icon: Icons.error_outline_rounded,
                      label: '失败 ${state.failedCount}',
                      emphasis: AppColors.error,
                    ),
                  const SizedBox(width: AppSpacing.xs),
                  if (state.isPaused)
                    FilledButton.tonalIcon(
                      onPressed: state.isProcessing
                          ? null
                          : () => service.resume(),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(
                        state.isProcessing ? '正在保存进度' : '继续',
                      ),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: state.isProcessing
                          ? () => service.pause()
                          : null,
                      icon: const Icon(Icons.pause_rounded, size: 18),
                      label: const Text('暂停'),
                    ),
                  if (state.failedCount > 0)
                    OutlinedButton.icon(
                      onPressed: () => service.retryFailed(),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('重试失败项'),
                    ),
                  if (state.completedCount > 0)
                    TextButton.icon(
                      onPressed: () => service.clearCompleted(),
                      icon: const Icon(Icons.cleaning_services_outlined,
                          size: 18),
                      label: const Text('清理已完成'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1, color: AppColors.borderMuted),
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: state.items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    return _QueueItemTile(
                      item: state.items[index],
                      queue: service,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  TranscriptionQueueItem? _firstWithStatus(
    List<TranscriptionQueueItem> items,
    TranscriptionQueueItemStatus status,
  ) {
    for (final item in items) {
      if (item.status == status) return item;
    }
    return null;
  }

  String _summaryText(
    TranscriptionQueueSnapshot state,
    TranscriptionQueueItem? running,
  ) {
    if (state.isPaused) {
      return running == null
          ? '队列已暂停，可稍后从当前进度继续'
          : '正在安全保存 ${running.projectName} 的当前进度';
    }
    if (running != null) {
      return '正在解析 ${running.projectName} · 完成后会自动处理下一首';
    }
    if (state.failedCount > 0 && state.queuedCount == 0) {
      return '队列已处理完毕，但仍有 ${state.failedCount} 首需要重试';
    }
    return '等待后台任务启动';
  }
}

class _EmptyQueueState extends StatelessWidget {
  const _EmptyQueueState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            ),
            child: const Icon(
              Icons.queue_music_rounded,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '后台队列还没有歌曲',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '从上方选择音频或音乐文件夹。加入后可以离开此页面，LyricForge 会继续逐首生成歌词。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? emphasis;

  const _CountPill({
    required this.icon,
    required this.label,
    this.emphasis,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = emphasis ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: emphasis == null
            ? AppColors.bgSurface
            : emphasis!.withAlpha(20),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
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
    final completed = item.status == TranscriptionQueueItemStatus.completed;
    final statusColor = _color(item.status);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: running
            ? AppColors.accent.withAlpha(12)
            : failed
                ? AppColors.error.withAlpha(10)
                : AppColors.bgBase,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(
          color: running
              ? AppColors.accent.withAlpha(50)
              : failed
                  ? AppColors.error.withAlpha(40)
                  : AppColors.borderMuted,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            child: Icon(
              _icon(item.status),
              size: 17,
              color: statusColor,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  running ? FontWeight.w700 : FontWeight.w500,
                              color: completed
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _statusLabel(item.status),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (running) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${(item.progress.clamp(0.0, 1.0) * 100).round()}%',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.message,
                  maxLines: failed ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: failed
                            ? AppColors.error
                            : AppColors.textTertiary,
                      ),
                ),
                if (running) ...[
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: item.progress.clamp(0.0, 1.0).toDouble(),
                    minHeight: 3,
                    backgroundColor: AppColors.bgHighlight,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusCircular),
                  ),
                ],
                if (failed && item.error != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    item.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
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
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 17),
            ),
        ],
      ),
    );
  }

  String _statusLabel(TranscriptionQueueItemStatus status) {
    return switch (status) {
      TranscriptionQueueItemStatus.queued => '等待',
      TranscriptionQueueItemStatus.running => '解析中',
      TranscriptionQueueItemStatus.paused => '已暂停',
      TranscriptionQueueItemStatus.completed => '完成',
      TranscriptionQueueItemStatus.failed => '失败',
    };
  }

  IconData _icon(TranscriptionQueueItemStatus status) {
    return switch (status) {
      TranscriptionQueueItemStatus.queued => Icons.schedule_rounded,
      TranscriptionQueueItemStatus.running => Icons.auto_awesome_rounded,
      TranscriptionQueueItemStatus.paused => Icons.pause_rounded,
      TranscriptionQueueItemStatus.completed => Icons.check_rounded,
      TranscriptionQueueItemStatus.failed => Icons.error_outline_rounded,
    };
  }

  Color _color(TranscriptionQueueItemStatus status) {
    return switch (status) {
      TranscriptionQueueItemStatus.queued => AppColors.textTertiary,
      TranscriptionQueueItemStatus.running => AppColors.accent,
      TranscriptionQueueItemStatus.paused => AppColors.warning,
      TranscriptionQueueItemStatus.completed => AppColors.success,
      TranscriptionQueueItemStatus.failed => AppColors.error,
    };
  }
}
