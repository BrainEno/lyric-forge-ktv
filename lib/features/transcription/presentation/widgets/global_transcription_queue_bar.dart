import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/transcription_queue_models.dart';

class GlobalTranscriptionQueueBar extends StatefulWidget {
  const GlobalTranscriptionQueueBar({super.key});

  @override
  State<GlobalTranscriptionQueueBar> createState() =>
      _GlobalTranscriptionQueueBarState();
}

class _GlobalTranscriptionQueueBarState
    extends State<GlobalTranscriptionQueueBar> {
  static bool _rememberedCollapsed = false;
  late bool _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = _rememberedCollapsed;
  }

  void _setCollapsed(bool value) {
    if (_collapsed == value) return;
    _rememberedCollapsed = value;
    setState(() => _collapsed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (!isDesktop) return const SizedBox.shrink();

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
        final statusColor = state.failedCount > 0
            ? AppColors.warning
            : state.isPaused
                ? AppColors.warning
                : AppColors.accent;

        return Material(
          color: AppColors.bgBase,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: overall,
                minHeight: 2,
                backgroundColor: AppColors.bgHighlight,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: _collapsed
                    ? _buildCollapsedBar(
                        context,
                        state: state,
                        focus: focus,
                        done: done,
                        total: total,
                        statusColor: statusColor,
                      )
                    : _buildExpandedBar(
                        context,
                        state: state,
                        focus: focus,
                        done: done,
                        total: total,
                        statusColor: statusColor,
                        onPause: queue.pause,
                        onResume: queue.resume,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollapsedBar(
    BuildContext context, {
    required TranscriptionQueueSnapshot state,
    required TranscriptionQueueItem focus,
    required int done,
    required int total,
    required Color statusColor,
  }) {
    return InkWell(
      onTap: () => _setCollapsed(false),
      hoverColor: AppColors.hoverOverlay,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.borderMuted),
            bottom: BorderSide(color: AppColors.borderMuted),
          ),
        ),
        child: Row(
          children: [
            Icon(
              state.isPaused ? Icons.pause_circle_outline : Icons.auto_awesome,
              size: 17,
              color: statusColor,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${state.isPaused ? '解析已暂停' : '后台解析'} · $done / $total · ${focus.projectName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (state.failedCount > 0) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${state.failedCount} 失败',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.warning,
                    ),
              ),
            ],
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              tooltip: '展开后台解析状态',
              visualDensity: VisualDensity.compact,
              onPressed: () => _setCollapsed(false),
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedBar(
    BuildContext context, {
    required TranscriptionQueueSnapshot state,
    required TranscriptionQueueItem focus,
    required int done,
    required int total,
    required Color statusColor,
    required Future<void> Function() onPause,
    required Future<void> Function() onResume,
  }) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, Routes.import),
      hoverColor: AppColors.hoverOverlay,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
                borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
              ),
              child: Icon(
                state.isPaused ? Icons.pause_rounded : Icons.auto_awesome_rounded,
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
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
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
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.warning,
                    ),
              ),
            ],
            const SizedBox(width: AppSpacing.md),
            Text(
              '$done / $total',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (state.isPaused)
              IconButton(
                tooltip: state.isProcessing ? '正在保存进度' : '继续队列',
                visualDensity: VisualDensity.compact,
                onPressed: state.isProcessing ? null : onResume,
                icon: const Icon(Icons.play_arrow_rounded, size: 19),
              )
            else if (state.isProcessing)
              IconButton(
                tooltip: '暂停队列',
                visualDensity: VisualDensity.compact,
                onPressed: onPause,
                icon: const Icon(Icons.pause_rounded, size: 19),
              ),
            IconButton(
              tooltip: '收起后台解析状态',
              visualDensity: VisualDensity.compact,
              onPressed: () => _setCollapsed(true),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
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
