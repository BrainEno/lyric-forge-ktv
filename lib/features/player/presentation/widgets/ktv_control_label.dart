import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';

/// Label + current value pair for a slider row.
///
/// Shared by the KTV microphone/backing controls and the take sheet so every
/// "音量 80%" row reads the same.
class KtvControlLabel extends StatelessWidget {
  final String title;
  final String value;

  const KtvControlLabel({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
