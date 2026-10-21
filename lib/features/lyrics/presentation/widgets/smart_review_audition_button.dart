import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';

/// One-tap access to the existing project playback session from a smart-review row.
class SmartReviewAuditionButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const SmartReviewAuditionButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final extent = AppResponsive.of(context).minimumInteractiveExtent;
    return SizedBox(
      width: extent,
      height: extent,
      child: IconButton(
        tooltip: '从这一行开始试听',
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: extent, height: extent),
        icon: const Icon(Icons.play_arrow_rounded),
      ),
    );
  }
}
