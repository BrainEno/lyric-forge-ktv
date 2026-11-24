import 'package:flutter/material.dart';

import '../layout/app_responsive.dart';
import '../theme/color_tokens.dart';
import '../theme/spacing_tokens.dart';
import 'getting_started.dart';

/// The words every 开始使用 checklist shares (D-070, D-071).
abstract final class GettingStartedCardText {
  static const String eyebrow = '开始使用';
  static const String finish = '收起';
  static const String dismissTooltip = '收起开始指南';
  static const String dismissedNotice = '已收起开始指南，可以在设置里重新打开。';
  static const String doneLabel = '已完成';

  static String progress(int done, int total) => '已完成 $done / $total';

  static String stateLabel(GettingStartedStepState state) => switch (state) {
    GettingStartedStepState.done => '已完成',
    GettingStartedStepState.inProgress => '进行中',
    GettingStartedStepState.ready => '可以开始',
    GettingStartedStepState.locked => '等前面的步骤完成',
  };

  /// What a screen reader says for a step, before its buttons.
  static String stepSemantics({
    required int number,
    required String title,
    required GettingStartedStepState state,
    required String detail,
  }) => '第 $number 步，$title，${stateLabel(state)}。$detail';
}

/// One step of a [GettingStartedCard].
class GettingStartedItem {
  /// Key of the step's row, for tests.
  final Key? key;
  final String title;
  final String detail;
  final GettingStartedStepState state;

  /// The button that does the step; none while done or locked.
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  /// A second, quieter way to do it (从电脑传 beside 导入歌曲).
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Key? secondaryKey;

  const GettingStartedItem({
    this.key,
    required this.title,
    required this.detail,
    required this.state,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    this.secondaryLabel,
    this.onSecondary,
    this.secondaryKey,
  });

  bool get isDone => state == GettingStartedStepState.done;

  bool get isLocked => state == GettingStartedStepState.locked;
}

/// A 开始使用 checklist (D-070, D-071): numbered steps that tick themselves,
/// a button on each step that can be done now, a progress line, a close
/// button and, once every step is done, a way to put it away.
///
/// The desktop dashboard and the phone's 听歌 page fill it with their own
/// steps.
class GettingStartedCard extends StatelessWidget {
  final String title;
  final String doneTitle;
  final String doneMessage;
  final List<GettingStartedItem> items;
  final VoidCallback onDismiss;
  final VoidCallback onFinish;
  final Key? dismissKey;
  final Key? finishKey;

  /// The card's fill; the elevated surface when null.
  final Color? color;

  const GettingStartedCard({
    super.key,
    required this.title,
    required this.doneTitle,
    required this.doneMessage,
    required this.items,
    required this.onDismiss,
    required this.onFinish,
    this.dismissKey,
    this.finishKey,
    this.color,
  });

  /// Below this width a step's buttons go under its words.
  static const double stackBelowWidth = 520;

  /// The number or tick in front of a step.
  static const double markerExtent = 28;

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final text = Theme.of(context).textTheme;
    final total = items.length;
    final done = items.where((item) => item.isDone).length;
    final allDone = total > 0 && done == total;
    final next = items.indexWhere((item) => !item.isDone);

    return Container(
      padding: EdgeInsets.all(layout.isCompact ? AppSpacing.md : AppSpacing.lg),
      decoration: BoxDecoration(
        color: color ?? AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      GettingStartedCardText.eyebrow,
                      style: text.labelSmall?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Semantics(
                      header: true,
                      child: Text(
                        allDone ? doneTitle : title,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      GettingStartedCardText.progress(done, total),
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: dismissKey,
                tooltip: GettingStartedCardText.dismissTooltip,
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ExcludeSemantics(
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: AppSpacing.progressBarHeight,
              color: AppColors.success,
              backgroundColor: AppColors.borderMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            _StepTile(
              key: items[index].key,
              number: index + 1,
              item: items[index],
              prominent: index == next,
            ),
          ],
          if (allDone) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              doneMessage,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                key: finishKey,
                style: FilledButton.styleFrom(
                  minimumSize: Size(
                    layout.minimumInteractiveExtent,
                    layout.minimumInteractiveExtent,
                  ),
                ),
                onPressed: onFinish,
                child: const Text(GettingStartedCardText.finish),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int number;
  final GettingStartedItem item;
  final bool prominent;

  const _StepTile({
    super.key,
    required this.number,
    required this.item,
    required this.prominent,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = item.isDone;
    final locked = item.isLocked;
    const extent = GettingStartedCard.markerExtent;

    final marker = SizedBox(
      width: extent,
      height: extent,
      child: done
          ? Icon(Icons.check_circle_rounded, color: AppColors.success)
          : DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: locked ? AppColors.borderMuted : AppColors.accent,
                ),
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: text.labelMedium?.copyWith(
                    color: locked
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
    );

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: locked || done
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          item.detail,
          style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );

    final described = Semantics(
      container: true,
      label: GettingStartedCardText.stepSemantics(
        number: number,
        title: item.title,
        state: item.state,
        detail: item.detail,
      ),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            marker,
            const SizedBox(width: AppSpacing.md),
            Expanded(child: words),
          ],
        ),
      ),
    );

    final buttons = _buttons(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (buttons == null) return described;
        // Narrow cards put the buttons under the words instead of squeezing
        // them into a sliver beside them.
        if (constraints.maxWidth < GettingStartedCard.stackBelowWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              described,
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: extent + AppSpacing.md,
                ),
                child: buttons,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: described),
            const SizedBox(width: AppSpacing.md),
            buttons,
          ],
        );
      },
    );
  }

  /// The step's buttons, 已完成 once it is done, nothing while locked.
  Widget? _buttons(BuildContext context) {
    if (item.isDone) {
      return ExcludeSemantics(
        child: Text(
          GettingStartedCardText.doneLabel,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.success),
        ),
      );
    }
    final label = item.actionLabel;
    final onAction = item.onAction;
    if (item.isLocked || label == null || onAction == null) return null;
    final extent = AppResponsive.of(context).minimumInteractiveExtent;
    final size = Size(extent, extent);
    final primary = prominent
        ? FilledButton(
            key: item.actionKey,
            style: FilledButton.styleFrom(minimumSize: size),
            onPressed: onAction,
            child: Text(label),
          )
        : OutlinedButton(
            key: item.actionKey,
            style: OutlinedButton.styleFrom(minimumSize: size),
            onPressed: onAction,
            child: Text(label),
          );
    final secondaryLabel = item.secondaryLabel;
    final onSecondary = item.onSecondary;
    if (secondaryLabel == null || onSecondary == null) return primary;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        primary,
        TextButton(
          key: item.secondaryKey,
          style: TextButton.styleFrom(minimumSize: size),
          onPressed: onSecondary,
          child: Text(secondaryLabel),
        ),
      ],
    );
  }
}
