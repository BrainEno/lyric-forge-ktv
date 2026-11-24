import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/getting_started.dart';
import 'dashboard_surfaces.dart';

/// The words of the 开始使用 checklist (D-070), kept together for tests.
abstract final class GettingStartedText {
  static const String eyebrow = '开始使用';
  static const String title = '三步做出第一首 KTV 歌词';
  static const String doneTitle = '三步都完成了';
  static const String doneMessage =
      '以后从“最近工程”继续识别、校对和唱歌。这张卡片收起后，可以在设置里重新打开。';
  static const String finish = '收起';
  static const String dismissTooltip = '收起开始指南';
  static const String dismissedNotice = '已收起开始指南，可以在设置里重新打开。';
  static const String doneLabel = '已完成';

  static String progress(int done, int total) => '已完成 $done / $total';

  static String stepTitle(GettingStartedStep step) => switch (step) {
    GettingStartedStep.importSong => '导入一首歌，自动识别歌词',
    GettingStartedStep.reviewLyrics => '校对歌词',
    GettingStartedStep.singKtv => '用 KTV 模式唱一遍',
  };

  static const String lockedDetail = '识别出歌词后就可以开始。';

  static String stepDetail(
    GettingStartedStep step,
    GettingStartedProgress progress,
  ) {
    final state = progress.stateOf(step);
    if (state == GettingStartedStepState.locked) return lockedDetail;
    final done = state == GettingStartedStepState.done;
    switch (step) {
      case GettingStartedStep.importSong:
        final recognizing = progress.recognizing;
        if (recognizing != null) {
          return '正在识别「${recognizing.name}」，识别完成后这一步会自动打勾。';
        }
        final song = progress.lyricsProject;
        if (song != null) return '「${song.name}」的歌词已经识别好了。';
        return '选一首本地歌曲，应用会在后台识别歌词并建好工程。'
            '第一次识别前会先引导你安装识别模型。';
      case GettingStartedStep.reviewLyrics:
        return done
            ? '已经确认过歌词，之后随时可以回到歌词编辑器继续校对。'
            : '在歌词编辑器里边听边看，标着“必看”的行先看，没问题就确认。';
      case GettingStartedStep.singKtv:
        return done
            ? '已经打开过 KTV。想唱哪首，从“最近工程”打开就行。'
            : '打开播放器，点“KTV”跟着逐行亮起的歌词唱，还可以录下来回放。';
    }
  }

  /// The button of a step that can be done now; null when it has none.
  static String? action(
    GettingStartedStep step,
    GettingStartedStepState state,
  ) {
    if (state == GettingStartedStepState.done ||
        state == GettingStartedStepState.locked) {
      return null;
    }
    return switch (step) {
      GettingStartedStep.importSong =>
        state == GettingStartedStepState.inProgress ? '查看进度' : '导入并识别',
      GettingStartedStep.reviewLyrics => '打开歌词编辑器',
      GettingStartedStep.singKtv => '去唱歌',
    };
  }

  static String stateLabel(GettingStartedStepState state) => switch (state) {
    GettingStartedStepState.done => '已完成',
    GettingStartedStepState.inProgress => '进行中',
    GettingStartedStepState.ready => '可以开始',
    GettingStartedStepState.locked => '等前面的步骤完成',
  };

  /// What a screen reader says for a step, before its button.
  static String stepSemantics(
    GettingStartedStep step,
    GettingStartedProgress progress,
  ) {
    final number = step.index + 1;
    final state = stateLabel(progress.stateOf(step));
    return '第 $number 步，${stepTitle(step)}，$state。'
        '${stepDetail(step, progress)}';
  }
}

/// The dashboard's 开始使用 checklist (D-070): import a song, review its
/// lyrics, sing it in KTV. Each step ticks itself from the user's projects
/// and has a button that goes straight to where it is done.
class DashboardGettingStartedCard extends StatelessWidget {
  final GettingStartedProgress progress;
  final ValueChanged<GettingStartedStep> onOpenStep;
  final VoidCallback onDismiss;
  final VoidCallback onFinish;

  const DashboardGettingStartedCard({
    super.key,
    required this.progress,
    required this.onOpenStep,
    required this.onDismiss,
    required this.onFinish,
  });

  static const Key cardKey = ValueKey('dashboard:getting-started');
  static const Key dismissKey = ValueKey('dashboard:getting-started:dismiss');
  static const Key finishKey = ValueKey('dashboard:getting-started:finish');

  static Key stepKey(GettingStartedStep step) =>
      ValueKey('dashboard:getting-started:${step.name}');

  static Key actionKey(GettingStartedStep step) =>
      ValueKey('dashboard:getting-started:${step.name}:action');

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final text = Theme.of(context).textTheme;
    final total = GettingStartedStep.values.length;
    final done = progress.doneCount;
    final next = progress.next;

    return Container(
      key: cardKey,
      padding: EdgeInsets.all(layout.isCompact ? AppSpacing.md : AppSpacing.lg),
      decoration: dashboardCardDecoration(),
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
                    const DashboardEyebrow(GettingStartedText.eyebrow),
                    const SizedBox(height: AppSpacing.xs),
                    Semantics(
                      header: true,
                      child: Text(
                        progress.allDone
                            ? GettingStartedText.doneTitle
                            : GettingStartedText.title,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      GettingStartedText.progress(done, total),
                      style: dashboardMutedLabel(context),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: dismissKey,
                tooltip: GettingStartedText.dismissTooltip,
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ExcludeSemantics(
            child: LinearProgressIndicator(
              value: done / total,
              minHeight: AppSpacing.progressBarHeight,
              color: AppColors.success,
              backgroundColor: AppColors.borderMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final step in GettingStartedStep.values) ...[
            if (step.index > 0) const SizedBox(height: AppSpacing.sm),
            _StepTile(
              step: step,
              progress: progress,
              prominent: step == next,
              onOpen: () => onOpenStep(step),
            ),
          ],
          if (progress.allDone) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              GettingStartedText.doneMessage,
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
                child: const Text(GettingStartedText.finish),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final GettingStartedStep step;
  final GettingStartedProgress progress;
  final bool prominent;
  final VoidCallback onOpen;

  const _StepTile({
    required this.step,
    required this.progress,
    required this.prominent,
    required this.onOpen,
  });

  /// The number or tick in front of a step.
  static const double markerExtent = 28;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = progress.stateOf(step);
    final done = state == GettingStartedStepState.done;
    final locked = state == GettingStartedStepState.locked;
    final label = GettingStartedText.action(step, state);

    final marker = SizedBox(
      width: markerExtent,
      height: markerExtent,
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
                  '${step.index + 1}',
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
          GettingStartedText.stepTitle(step),
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: locked || done
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          GettingStartedText.stepDetail(step, progress),
          style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );

    final trailing = _trailing(context, label: label, done: done);

    final described = Semantics(
      container: true,
      label: GettingStartedText.stepSemantics(step, progress),
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

    return LayoutBuilder(
      key: DashboardGettingStartedCard.stepKey(step),
      builder: (context, constraints) {
        // Narrow cards put the button under the words instead of squeezing
        // them into a sliver beside it.
        final stacked = constraints.maxWidth < 520;
        if (trailing == null) return described;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              described,
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: markerExtent + AppSpacing.md,
                ),
                child: trailing,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: described),
            const SizedBox(width: AppSpacing.md),
            trailing,
          ],
        );
      },
    );
  }

  /// The step's button, 已完成 once it is done, or nothing while locked.
  Widget? _trailing(
    BuildContext context, {
    required String? label,
    required bool done,
  }) {
    if (label == null) {
      if (!done) return null;
      return ExcludeSemantics(
        child: Text(
          GettingStartedText.doneLabel,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.success),
        ),
      );
    }
    final extent = AppResponsive.of(context).minimumInteractiveExtent;
    final size = Size(extent, extent);
    final key = DashboardGettingStartedCard.actionKey(step);
    if (prominent) {
      return FilledButton(
        key: key,
        style: FilledButton.styleFrom(minimumSize: size),
        onPressed: onOpen,
        child: Text(label),
      );
    }
    return OutlinedButton(
      key: key,
      style: OutlinedButton.styleFrom(minimumSize: size),
      onPressed: onOpen,
      child: Text(label),
    );
  }
}
