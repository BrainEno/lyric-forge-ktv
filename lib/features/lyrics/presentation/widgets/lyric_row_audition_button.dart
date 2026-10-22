import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../lyric_review_strings.dart';

/// One-tap access to the current project's bounded single-line audition.
class LyricRowAuditionButton extends StatelessWidget {
  final bool hasAudio;
  final bool isPlaying;
  final VoidCallback? onPressed;

  const LyricRowAuditionButton({
    super.key,
    required this.hasAudio,
    required this.isPlaying,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasAudio) return const SizedBox.shrink();

    final extent = AppResponsive.of(context).minimumInteractiveExtent;
    return SizedBox(
      width: extent,
      height: extent,
      child: IconButton(
        tooltip: isPlaying
            ? LyricReviewStrings.auditionPauseTooltip
            : LyricReviewStrings.auditionPlayTooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: extent, height: extent),
        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
    );
  }
}
