// The dashboard card that shows the background transcription queue.
//
// Split out of `dashboard_screen.dart` (audit D-06).

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_queue_models.dart';
import 'dashboard_surfaces.dart';

class DashboardBackgroundWorkCard extends StatelessWidget {
  final TranscriptionQueueSnapshot snapshot;
  final VoidCallback onOpen;
  final Future<void> Function() onPauseResume;

  const DashboardBackgroundWorkCard({
    super.key,
    required this.snapshot,
    required this.onOpen,
    required this.onPauseResume,
  });

  @override
  Widget build(BuildContext context) {
    final running = snapshot.items.where(
      (item) => item.status == TranscriptionQueueItemStatus.running,
    );
    final active = snapshot.items
        .where(
          (item) =>
              item.status == TranscriptionQueueItemStatus.running ||
              item.status == TranscriptionQueueItemStatus.queued ||
              item.status == TranscriptionQueueItemStatus.paused,
        )
        .length;
    final current = running.isEmpty ? null : running.first;
    final progress = snapshot.items.isEmpty
        ? 0.0
        : snapshot.items
                  .map(
                    (item) =>
                        item.status == TranscriptionQueueItemStatus.completed
                        ? 1.0
                        : item.progress.clamp(0.0, 1.0).toDouble(),
                  )
                  .fold<double>(0, (sum, value) => sum + value) /
              snapshot.items.length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: dashboardCardDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = AppResponsive.fromConstraints(constraints);
          final info = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      (snapshot.failedCount > 0
                              ? AppColors.warning
                              : AppColors.accent)
                          .withAlpha(20),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: Icon(
                  snapshot.isPaused
                      ? Icons.pause_rounded
                      : Icons.auto_awesome_motion_rounded,
                  color: snapshot.failedCount > 0
                      ? AppColors.warning
                      : AppColors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.isPaused
                          ? '后台歌词任务已暂停'
                          : current != null
                          ? '正在识别 · ${current.projectName}'
                          : active > 0
                          ? '后台歌词任务'
                          : '歌词任务已处理完毕',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '完成 ${snapshot.completedCount} · 等待 ${snapshot.queuedCount} · 失败 ${snapshot.failedCount}',
                      style: dashboardMutedLabel(context),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: AppColors.bgHighlight,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusCircular,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (active > 0)
                TextButton.icon(
                  onPressed: onPauseResume,
                  icon: Icon(
                    snapshot.isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    size: 17,
                  ),
                  label: Text(snapshot.isPaused ? '继续' : '暂停'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(
                    layout.minimumInteractiveExtent,
                    layout.minimumInteractiveExtent,
                  ),
                ),
                onPressed: onOpen,
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('查看队列'),
              ),
            ],
          );
          if (layout.isCompactOrMedium || layout.isShort) {
            return Column(
              children: [
                info,
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: AppSpacing.md),
              actions,
            ],
          );
        },
      ),
    );
  }
}
