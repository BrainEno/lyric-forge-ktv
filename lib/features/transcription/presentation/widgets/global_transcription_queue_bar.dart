import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/transcription_queue_models.dart';

class GlobalTranscriptionQueueBar extends StatelessWidget {
  const GlobalTranscriptionQueueBar({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = ServiceLocatorGlobal.I.transcriptionQueue;
    return StreamBuilder<TranscriptionQueueSnapshot>(
      stream: queue.snapshots,
      initialData: queue.current,
      builder: (context, snapshot) {
        final state = snapshot.data ?? queue.current;
        final visibleItems = state.items.where((item) {
          return item.status != TranscriptionQueueItemStatus.completed;
        }).toList(growable: false);
        if (visibleItems.isEmpty) return const SizedBox.shrink();

        final running = _firstWithStatus(
          state.items,
          TranscriptionQueueItemStatus.running,
        );
        final focus = running ?? visibleItems.first;
        final total = state.items.length;
        final done = state.completedCount;
        final overall = total == 0
            ? 0.0
            : ((done + (running?.progress ?? 0)) / total)
                .clamp(0.0, 1.0)
                .toDouble();

        return Material(
          color: AppColors.bgElevated,
          child: InkWell(
            onTap: () => Navigator.pushNamed(context, Routes.import),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    state.isPaused
                        ? Icons.pause_circle_outline
                        : Icons.auto_awesome,
                    size: 20,
                    color: state.failedCount > 0
                        ? AppColors.warning
                        : AppColors.accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                state.isPaused
                                    ? '后台解析已暂停 · ${focus.projectName}'
                                    : '后台解析 · ${focus.projectName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              '$done / $total',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: AppColors.textTertiary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: overall,
                          minHeight: 3,
                          backgroundColor: AppColors.bgHighlight,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusCircular,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          focus.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppColors.textTertiary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (state.isPaused)
                    IconButton(
                      tooltip: state.isProcessing ? '正在保存进度' : '继续队列',
                      onPressed: state.isProcessing
                          ? null
                          : () => queue.resume(),
                      icon: const Icon(Icons.play_arrow),
                    )
                  else if (state.isProcessing)
                    IconButton(
                      tooltip: '暂停队列',
                      onPressed: () => queue.pause(),
                      icon: const Icon(Icons.pause),
                    ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
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
}
