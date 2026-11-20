import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/project_manifest.dart';

/// Where a project is on one production step.
enum ProductionStepState {
  /// The project has passed this step.
  done,

  /// The step is running now (lyric recognition in progress).
  inProgress,

  /// The first step not yet done, when nothing is running.
  next,

  /// A later step.
  upcoming,
}

/// One step of the 制作进度 card.
@immutable
class ProductionStep {
  const ProductionStep({
    required this.label,
    required this.icon,
    required this.state,
  });

  final String label;
  final IconData icon;
  final ProductionStepState state;

  bool get isDone => state == ProductionStepState.done;

  /// The step the user should look at: running now, or next to do.
  bool get isCurrent =>
      state == ProductionStepState.inProgress ||
      state == ProductionStepState.next;

  /// Word read after the label: 已完成, 进行中, 下一步 or 未开始.
  String get stateLabel => switch (state) {
    ProductionStepState.done => '已完成',
    ProductionStepState.inProgress => '进行中',
    ProductionStepState.next => '下一步',
    ProductionStepState.upcoming => '未开始',
  };

  @override
  bool operator ==(Object other) =>
      other is ProductionStep &&
      other.label == label &&
      other.icon == icon &&
      other.state == state;

  @override
  int get hashCode => Object.hash(label, icon, state);

  @override
  String toString() => 'ProductionStep($label, $state)';
}

/// The five production steps for a project at [stage].
///
/// [transcribing] marks 歌词识别 as running. Without a running step, the first
/// step not yet done is marked as next.
List<ProductionStep> productionStepsFor(
  ProcessingStage stage, {
  bool transcribing = false,
}) {
  const steps = [
    (label: '导入', icon: Icons.audio_file_outlined, doneAt: _imported),
    (label: '音频处理', icon: Icons.tune_rounded, doneAt: _normalized),
    (label: '歌词识别', icon: Icons.auto_awesome, doneAt: _transcribed),
    (label: '歌词校对', icon: Icons.edit_note_rounded, doneAt: _edited),
    (label: '导出', icon: Icons.ios_share_rounded, doneAt: _exported),
  ];
  var nextMarked = false;
  ProductionStepState stateOf(ProcessingStage doneAt) {
    if (stage.index >= doneAt.index) return ProductionStepState.done;
    if (transcribing && doneAt == _transcribed) {
      return ProductionStepState.inProgress;
    }
    if (transcribing || nextMarked) return ProductionStepState.upcoming;
    nextMarked = true;
    return ProductionStepState.next;
  }

  return [
    for (final step in steps)
      ProductionStep(
        label: step.label,
        icon: step.icon,
        state: stateOf(step.doneAt),
      ),
  ];
}

const _imported = ProcessingStage.audioImported;
const _normalized = ProcessingStage.audioNormalized;
const _transcribed = ProcessingStage.transcriptionComplete;
const _edited = ProcessingStage.lyricsEdited;
const _exported = ProcessingStage.exported;

/// Connected row of production steps.
///
/// Replaces the row of `_StagePill`s on the project page, which looked like
/// the status and metadata badges around it and, on phones, scrolled
/// sideways (audit P-01). Each step is an icon in a circle on a line, with
/// the label below; done steps are filled, the current step is outlined, and
/// all five fit a 320 px wide card. Each step reads as 第 N 步，共 5 步：label，
/// state.
class ProductionSteps extends StatelessWidget {
  const ProductionSteps({super.key, required this.steps});

  final List<ProductionStep> steps;

  /// Diameter of a step circle.
  static const double markerExtent = 28;

  /// Finished steps and the line between them are green, the status colour
  /// for "done"; the step to look at now gets the accent ring. Both used to
  /// be the accent, back when the accent was the same green (audit A-01).
  static Color get doneColor => AppColors.success;
  static Color get currentColor => AppColors.accent;

  /// Check mark on a finished step: black on the dark theme's green is
  /// 8.1:1, white on the light theme's deeper green 5.3:1.
  static Color get onDoneColor => AppColors.onSuccess;

  static Key stepKey(int index) => ValueKey('production-step:$index');

  /// What a screen reader says for the step at [index].
  static String semanticsLabelFor(List<ProductionStep> steps, int index) {
    final step = steps[index];
    return '第 ${index + 1} 步，共 ${steps.length} 步：'
        '${step.label}，${step.stateLabel}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < steps.length; index++)
          Expanded(
            child: Semantics(
              key: stepKey(index),
              container: true,
              label: semanticsLabelFor(steps, index),
              child: ExcludeSemantics(
                child: _StepTile(
                  step: steps[index],
                  lineBefore: index == 0 ? null : steps[index].isDone,
                  lineAfter: index == steps.length - 1
                      ? null
                      : steps[index + 1].isDone,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.lineBefore,
    required this.lineAfter,
  });

  final ProductionStep step;

  /// Whether the line into this step is filled; null for the first step.
  final bool? lineBefore;

  /// Whether the line out of this step is filled; null for the last step.
  final bool? lineAfter;

  @override
  Widget build(BuildContext context) {
    final highlighted = step.isDone || step.isCurrent;
    final text = Theme.of(context).textTheme;
    final labelStyle = text.labelSmall?.copyWith(
      color: highlighted ? AppColors.textPrimary : AppColors.textTertiary,
      fontWeight: step.isCurrent ? FontWeight.w700 : FontWeight.w500,
    );

    return Column(
      children: [
        SizedBox(
          height: ProductionSteps.markerExtent,
          child: Row(
            children: [
              Expanded(child: _Line(filled: lineBefore)),
              _Marker(step: step),
              Expanded(child: _Line(filled: lineAfter)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          step.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: labelStyle,
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.filled});

  /// Null draws nothing (the ends of the row).
  final bool? filled;

  @override
  Widget build(BuildContext context) {
    final value = filled;
    if (value == null) return const SizedBox.shrink();
    return Container(
      height: 2,
      color: value ? ProductionSteps.doneColor : AppColors.bgHighlight,
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.step});

  final ProductionStep step;

  @override
  Widget build(BuildContext context) {
    final done = step.isDone;
    final current = step.isCurrent;
    final Color iconColor;
    if (done) {
      iconColor = ProductionSteps.onDoneColor;
    } else if (current) {
      iconColor = ProductionSteps.currentColor;
    } else {
      iconColor = AppColors.textTertiary;
    }

    return Container(
      width: ProductionSteps.markerExtent,
      height: ProductionSteps.markerExtent,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? ProductionSteps.doneColor : AppColors.bgSurface,
        border: Border.all(
          color: current ? ProductionSteps.currentColor : Colors.transparent,
          width: 2,
        ),
      ),
      child: Icon(
        done ? Icons.check_rounded : step.icon,
        size: 16,
        color: iconColor,
      ),
    );
  }
}
