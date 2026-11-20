import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/app_chrome_scope.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_tap_target.dart';
import '../../domain/models/transcription_queue_models.dart';
import '../../domain/services/batch_transcription_queue.dart';

class GlobalTranscriptionQueueBar extends StatelessWidget {
  final BatchTranscriptionQueue queue;

  const GlobalTranscriptionQueueBar({super.key, required this.queue});

  static const String openHint = '打开导入与解析队列';
  static const String resumeLabel = '继续队列';
  static const String pauseLabel = '暂停队列';

  /// The bar as one spoken button (audit A-04): state, the song in focus,
  /// failures and the count, which were loose words around a bare `InkWell`
  /// whose tap opened the import page without saying so. Pause and resume
  /// are the bar's actions as well as its buttons.
  static String semanticsLabel({
    required bool paused,
    required String projectName,
    required int failed,
    required int done,
    required int total,
  }) {
    return AppTapTarget.join([
      paused ? '后台解析已暂停' : '正在后台解析',
      projectName,
      if (failed > 0) '$failed 首失败',
      '已完成 $done / $total 首',
    ]);
  }

  /// The overall progress bar as a percentage.
  static String progressValue(double overall) =>
      '${(overall.clamp(0.0, 1.0) * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (!isDesktop) return const SizedBox.shrink();

    return StreamBuilder<TranscriptionQueueSnapshot>(
      stream: queue.snapshots,
      initialData: queue.current,
      builder: (context, snapshot) {
        final state = snapshot.data ?? queue.current;
        final visibleItems = state.items
            .where((item) {
              return item.status != TranscriptionQueueItemStatus.completed;
            })
            .toList(growable: false);
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
        final statusColor = state.failedCount > 0
            ? AppColors.warning
            : state.isPaused
            ? AppColors.warning
            : AppColors.accent;

        void open() => AppChromeScope.pushNamed<void>(context, Routes.import);

        return Material(
          color: AppColors.bgBase,
          child: AppTapTarget(
            label: GlobalTranscriptionQueueBar.semanticsLabel(
              paused: state.isPaused,
              projectName: focus.projectName,
              failed: state.failedCount,
              done: done,
              total: total,
            ),
            value: GlobalTranscriptionQueueBar.progressValue(overall),
            hint: GlobalTranscriptionQueueBar.openHint,
            onTap: open,
            actions: {
              if (state.isPaused && !state.isProcessing)
                GlobalTranscriptionQueueBar.resumeLabel: queue.resume,
              if (!state.isPaused && state.isProcessing)
                GlobalTranscriptionQueueBar.pauseLabel: queue.pause,
            },
            child: InkWell(
              // Chrome beside the navigator: see AppChromeScope.
              onTap: open,
              hoverColor: AppColors.hoverOverlay,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: overall,
                    minHeight: 2,
                    backgroundColor: AppColors.bgHighlight,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                  Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.borderMuted),
                        bottom: BorderSide(color: AppColors.borderMuted),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusCircular,
                            ),
                          ),
                          child: Icon(
                            state.isPaused
                                ? Icons.pause_rounded
                                : Icons.auto_awesome_rounded,
                            size: 16,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  state.isPaused ? '后台解析已暂停' : '正在后台解析',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              const Text(
                                '·',
                                style: TextStyle(color: AppColors.textTertiary),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Flexible(
                                flex: 2,
                                child: Text(
                                  focus.projectName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (state.failedCount > 0) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${state.failedCount} 首失败',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.warning),
                          ),
                        ],
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          '$done / $total',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        if (state.isPaused)
                          IconButton(
                            tooltip: state.isProcessing
                                ? '正在保存进度'
                                : resumeLabel,
                            visualDensity: VisualDensity.compact,
                            onPressed: state.isProcessing
                                ? null
                                : () => queue.resume(),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 19,
                            ),
                          )
                        else if (state.isProcessing)
                          IconButton(
                            tooltip: pauseLabel,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => queue.pause(),
                            icon: const Icon(Icons.pause_rounded, size: 19),
                          ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
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
