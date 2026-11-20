import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// The steps of the desktop import flow, in order.
enum ImportStep {
  /// Check the computer and install the recognition models (once).
  prepare('准备识别环境'),

  /// Pick songs and hand them to the background queue.
  choose('选择歌曲');

  const ImportStep(this.label);

  final String label;
}

/// Compact "1 准备识别环境 — 2 选择歌曲" strip at the top of the import flow.
///
/// The environment check used to open under the title 批量导入, so people
/// expected a file picker and found a model installer (audit I-01). The strip
/// says which step this is and that choosing songs comes next. Mobile import
/// has no preparation step and does not show it.
class ImportStepIndicator extends StatelessWidget {
  const ImportStepIndicator({super.key, required this.current});

  final ImportStep current;

  /// Diameter of the numbered circle.
  static const double markerExtent = 24;

  /// Spoken summary, e.g. "第 1 步，共 2 步：准备识别环境".
  String get semanticsLabel {
    final total = ImportStep.values.length;
    return '第 ${current.index + 1} 步，共 $total 步：${current.label}';
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final step in ImportStep.values) {
      if (step.index > 0) {
        children.add(
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              color: step.index <= current.index
                  ? AppColors.accent
                  : AppColors.borderSubtle,
            ),
          ),
        );
      }
      children.add(_StepLabel(step: step, current: current));
    }
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(child: Row(children: children)),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.step, required this.current});

  final ImportStep step;
  final ImportStep current;

  @override
  Widget build(BuildContext context) {
    final done = step.index < current.index;
    final active = step == current;
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: ValueKey('import-step:${step.name}'),
          width: ImportStepIndicator.markerExtent,
          height: ImportStepIndicator.markerExtent,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done || active ? AppColors.accent : AppColors.bgSurface,
          ),
          child: done
              ? Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AppColors.onAccent,
                )
              : Text(
                  '${step.index + 1}',
                  style: text.labelMedium?.copyWith(
                    color: active ? AppColors.onAccent : AppColors.textTertiary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          step.label,
          style: text.labelLarge?.copyWith(
            color: active ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
