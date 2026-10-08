import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';

/// Focused three-line lyric presentation for KTV surfaces.
///
/// Playback remains external: callers only provide the current lyric index.
/// This keeps the stage reusable by normal and immersive player layouts.
class KtvLyricStage extends StatelessWidget {
  final List<LyricLine> lyrics;
  final int? currentIndex;
  final String emptyLabel;

  const KtvLyricStage({
    super.key,
    required this.lyrics,
    required this.currentIndex,
    this.emptyLabel = '当前歌曲没有可用歌词',
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    if (lyrics.isEmpty) {
      return Center(
        key: const ValueKey('ktv-lyric-stage-empty'),
        child: Padding(
          padding: EdgeInsets.all(spec.pageGutter),
          child: Text(
            emptyLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
        ),
      );
    }

    final index = (currentIndex ?? 0).clamp(0, lyrics.length - 1).toInt();
    final previous = index > 0 ? lyrics[index - 1] : null;
    final current = lyrics[index];
    final next = index + 1 < lyrics.length ? lyrics[index + 1] : null;
    final gap = spec.isShort
        ? AppSpacing.sm
        : spec.isCompact
            ? AppSpacing.lg
            : AppSpacing.xxl;
    final horizontal = spec.pageGutter.clamp(16, 48).toDouble();

    final previousStyle = (spec.isShort || spec.isCompact
            ? Theme.of(context).textTheme.titleMedium
            : Theme.of(context).textTheme.headlineSmall)
        ?.copyWith(
      color: AppColors.textTertiary,
      height: 1.35,
      fontWeight: FontWeight.w500,
    );
    final currentStyle = (spec.isShort
            ? Theme.of(context).textTheme.headlineMedium
            : spec.isCompact
                ? Theme.of(context).textTheme.headlineLarge
                : spec.isExtraLarge
                    ? Theme.of(context).textTheme.displayMedium
                    : Theme.of(context).textTheme.displaySmall)
        ?.copyWith(
      color: AppColors.pureWhite,
      fontWeight: FontWeight.w900,
      height: 1.18,
    );
    final nextStyle = (spec.isShort || spec.isCompact
            ? Theme.of(context).textTheme.titleLarge
            : Theme.of(context).textTheme.headlineMedium)
        ?.copyWith(
      color: AppColors.textSecondary,
      height: 1.3,
      fontWeight: FontWeight.w600,
    );

    return Center(
      child: ConstrainedBox(
        key: const ValueKey('ktv-lyric-stage-bounds'),
        constraints: BoxConstraints(maxWidth: spec.playerContentMaxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontal,
              vertical: spec.isShort ? AppSpacing.sm : AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AnimatedLyricSlot(
                  key: const ValueKey('ktv-lyric-previous'),
                  line: previous,
                  style: previousStyle,
                  maxLines: spec.isShort ? 1 : 2,
                ),
                SizedBox(height: gap),
                _AnimatedLyricSlot(
                  key: const ValueKey('ktv-lyric-current'),
                  line: current,
                  style: currentStyle,
                  maxLines: spec.isShort ? 2 : 3,
                ),
                SizedBox(height: gap),
                _AnimatedLyricSlot(
                  key: const ValueKey('ktv-lyric-next'),
                  line: next,
                  style: nextStyle,
                  maxLines: spec.isShort ? 1 : 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedLyricSlot extends StatelessWidget {
  final LyricLine? line;
  final TextStyle? style;
  final int maxLines;

  const _AnimatedLyricSlot({
    super.key,
    required this.line,
    required this.style,
    required this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final lineKey = '${line?.startTime.inMilliseconds ?? -1}:${line?.text ?? ''}';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Text(
        line?.text ?? '',
        key: ValueKey<String>(lineKey),
        textAlign: TextAlign.center,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
