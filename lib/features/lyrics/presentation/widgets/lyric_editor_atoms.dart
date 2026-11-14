import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// Small shared pieces of the lyric editor: badges, nudge steppers and the
/// duration formatters the list, inspector and toolbar all print.
///
/// They live here instead of inside the editor screen so the extracted panes
/// can use them without importing a 2,000-line `State`.

class LyricTinyBadge extends StatelessWidget {
  final String label;
  final bool accent;
  final bool warning;

  const LyricTinyBadge({
    super.key,
    required this.label,
    this.accent = false,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? AppColors.warning
        : accent
        ? AppColors.accent
        : AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

class LyricNudgeButton extends StatelessWidget {
  final String label;
  final double minHeight;
  final VoidCallback onPressed;

  const LyricNudgeButton({
    super.key,
    required this.label,
    required this.minHeight,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(70, minHeight),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label),
    );
  }
}

String formatLyricDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  final millis = (safe.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(
    2,
    '0',
  );
  return '$minutes:$seconds.$millis';
}

String formatCompactLyricDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  if (safe.inSeconds >= 1) {
    return '${(safe.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  return '${safe.inMilliseconds}ms';
}
