import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_run_progress.dart';

/// The project page while lyrics are being recognised (D-049).
///
/// The page used to show the engine's last message over a 5 px bar and a
/// percentage. The bar ran back to 0% between separation, recognition and
/// gap filling, and while a model worked through the whole song nothing on
/// the page moved for minutes, so users could not tell whether anything was
/// still happening. This card names the step (of six), keeps a stopwatch
/// running, moves a light sweep along the bar the whole time, estimates the
/// time left once there is something to go on, and after
/// [TranscriptionRunTracker.quietAfter] without news says that the program
/// is still running and what the step usually takes.
class RecognitionProgressCard extends StatefulWidget {
  const RecognitionProgressCard({
    super.key,
    required this.tracker,
    this.onCancel,
    this.clock = DateTime.now,
    this.tick = const Duration(seconds: 1),
  });

  /// The run being shown; the page records every progress event into it.
  final TranscriptionRunTracker tracker;

  /// Stops the run (the page asks first); null hides the button.
  final VoidCallback? onCancel;

  /// The current time; replaced in tests.
  final DateTime Function() clock;

  /// How often the stopwatch is redrawn.
  final Duration tick;

  @override
  State<RecognitionProgressCard> createState() =>
      _RecognitionProgressCardState();
}

class _RecognitionProgressCardState extends State<RecognitionProgressCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(widget.tick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracker = widget.tracker;
    final now = widget.clock();
    final step = tracker.step;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final spec = AppResponsive.of(context);
    final quiet = tracker.isQuiet(now);
    final percent = TranscriptionRunText.percent(tracker.overall);
    final title = TranscriptionRunText.stepTitle(step);
    final counter = TranscriptionRunText.stepCounter(step);

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title，$counter，$percent',
      child: Container(
        key: const ValueKey('recognition_progress_card'),
        padding: EdgeInsets.all(spec.isCompact ? AppSpacing.sm : AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          border: Border.all(color: AppColors.accent.withAlpha(90)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _ActivityIcon(reduceMotion: reduceMotion),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        key: const ValueKey('recognition_progress_title'),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$counter · '
                        '${TranscriptionRunText.elapsed(tracker.elapsed(now))}',
                        key: const ValueKey('recognition_progress_elapsed'),
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  percent,
                  key: const ValueKey('recognition_progress_percent'),
                  style: textTheme.headlineSmall?.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _RunBar(value: tracker.overall, reduceMotion: reduceMotion),
            const SizedBox(height: AppSpacing.sm),
            Text(
              tracker.message,
              key: const ValueKey('recognition_progress_message'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              TranscriptionRunText.remaining(tracker.remaining(now)),
              key: const ValueKey('recognition_progress_remaining'),
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            if (quiet) ...[
              const SizedBox(height: AppSpacing.sm),
              _QuietNote(
                hint: TranscriptionRunText.stepHint(step),
                quiet: TranscriptionRunText.quiet(tracker.sinceLastEvent(now)),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final each in TranscriptionRunStep.values)
                  _StepChip(
                    step: each,
                    state: tracker.stateOf(each),
                    reduceMotion: reduceMotion,
                  ),
              ],
            ),
            if (widget.onCancel != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('recognition_progress_cancel'),
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('停止识别'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A spinner beside the title, or a still icon when motion is reduced.
class _ActivityIcon extends StatelessWidget {
  const _ActivityIcon({required this.reduceMotion});

  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent.withAlpha(24),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: reduceMotion
          ? Icon(Icons.graphic_eq_rounded, color: AppColors.accent)
          : SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.accent,
              ),
            ),
    );
  }
}

/// The run's progress with a light sweep moving along the track, so the
/// bar shows activity even while the percentage stands still.
class _RunBar extends StatelessWidget {
  const _RunBar({required this.value, required this.reduceMotion});

  final double value;
  final bool reduceMotion;

  static const double height = 8;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppSpacing.radiusCircular);
    return SizedBox(
      key: const ValueKey('recognition_progress_bar'),
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!reduceMotion)
            LinearProgressIndicator(
              key: const ValueKey('recognition_progress_activity'),
              minHeight: height,
              backgroundColor: AppColors.bgHighlight,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.accent.withAlpha(56),
              ),
              borderRadius: radius,
            ),
          LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: height,
            backgroundColor: reduceMotion
                ? AppColors.bgHighlight
                : Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            borderRadius: radius,
          ),
        ],
      ),
    );
  }
}

/// Said when nothing has been reported for a while.
class _QuietNote extends StatelessWidget {
  const _QuietNote({required this.hint, required this.quiet});

  final String hint;
  final String quiet;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.4);
    return Container(
      key: const ValueKey('recognition_progress_quiet'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top_rounded, size: 18, color: AppColors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('$quiet$hint', style: style)),
        ],
      ),
    );
  }
}

/// One step of the run: done, skipped, in progress or still to come.
class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.step,
    required this.state,
    required this.reduceMotion,
  });

  final TranscriptionRunStep step;
  final TranscriptionRunStepState state;
  final bool reduceMotion;

  /// What the chip says about [state], for screen readers and the label.
  static String stateLabel(TranscriptionRunStepState state) => switch (state) {
    TranscriptionRunStepState.done => '已完成',
    TranscriptionRunStepState.skipped => '已跳过',
    TranscriptionRunStepState.active => '进行中',
    TranscriptionRunStepState.pending => '等待中',
  };

  @override
  Widget build(BuildContext context) {
    final active = state == TranscriptionRunStepState.active;
    final color = switch (state) {
      TranscriptionRunStepState.done => AppColors.success,
      TranscriptionRunStepState.active => AppColors.accent,
      TranscriptionRunStepState.skipped ||
      TranscriptionRunStepState.pending => AppColors.textTertiary,
    };
    final Widget icon = switch (state) {
      TranscriptionRunStepState.done => Icon(
        Icons.check_circle_rounded,
        size: 16,
        color: color,
      ),
      TranscriptionRunStepState.skipped => Icon(
        Icons.remove_circle_outline_rounded,
        size: 16,
        color: color,
      ),
      TranscriptionRunStepState.pending => Icon(
        Icons.radio_button_unchecked_rounded,
        size: 16,
        color: color,
      ),
      TranscriptionRunStepState.active =>
        reduceMotion
            ? Icon(Icons.play_circle_fill_rounded, size: 16, color: color)
            : SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
    };
    final label = TranscriptionRunText.stepLabel(step);
    final skipped = state == TranscriptionRunStepState.skipped;
    return Semantics(
      container: true,
      label: '$label，${stateLabel(state)}',
      excludeSemantics: true,
      child: Container(
        key: ValueKey('recognition_step_${step.name}'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withAlpha(26) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
          border: Border.all(
            color: active ? AppColors.accent.withAlpha(120) : AppColors.borderMuted,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: AppSpacing.xs),
            Text(
              skipped ? '$label（跳过）' : label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: active ? AppColors.textPrimary : color,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                decoration: skipped ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
