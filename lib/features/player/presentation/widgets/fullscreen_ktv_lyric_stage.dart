import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import 'ktv_karaoke_line.dart';

int? fullscreenKtvCurrentLyricIndex(
  LyricDocument? document,
  Duration position,
) {
  final lines = document?.lines;
  if (lines == null || lines.isEmpty) return null;
  final offset = document?.globalOffset ?? Duration.zero;
  for (var index = lines.length - 1; index >= 0; index--) {
    final shifted = lines[index].startTime + offset;
    final effective = shifted.isNegative ? Duration.zero : shifted;
    if (position >= effective) return index;
  }
  return 0;
}

class FullscreenKtvLyricStage extends StatelessWidget {
  final LyricDocument? document;
  final Duration position;
  final String emptyMessage;

  /// Whether playback is running; the current line then keeps its karaoke
  /// colour moving between position updates.
  final bool isPlaying;

  const FullscreenKtvLyricStage({
    super.key,
    required this.document,
    required this.position,
    this.emptyMessage = '当前歌曲没有可用歌词',
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final lyrics = document?.lines ?? const <LyricLine>[];
    if (lyrics.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(spec.pageGutter),
          child: Text(
            emptyMessage,
            key: const ValueKey('fullscreen-ktv-empty-lyrics'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ),
      );
    }

    final index = fullscreenKtvCurrentLyricIndex(document, position) ?? 0;
    final safeIndex = index.clamp(0, lyrics.length - 1).toInt();
    final previous = safeIndex > 0 ? lyrics[safeIndex - 1] : null;
    final current = lyrics[safeIndex];
    final next = safeIndex + 1 < lyrics.length ? lyrics[safeIndex + 1] : null;
    final gap = spec.isShort
        ? AppSpacing.sm
        : spec.isCompact
        ? AppSpacing.lg
        : AppSpacing.xxl;
    final maxWidth = spec.isExtraLarge
        ? 1480.0
        : spec.isLarge
        ? 1180.0
        : 900.0;

    final text = Theme.of(context).textTheme;
    final previousBase = spec.isShort || spec.isCompact
        ? text.titleMedium
        : text.headlineSmall;
    final previousStyle = previousBase?.copyWith(
      color: AppColors.textTertiary,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );
    final currentBase = spec.isShort
        ? text.headlineMedium
        : spec.isCompact
        ? text.headlineLarge
        : spec.isExtraLarge
        ? text.displayMedium
        : text.displaySmall;
    final currentStyle = currentBase?.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w900,
      height: 1.18,
    );
    final nextBase = spec.isShort || spec.isCompact
        ? text.titleLarge
        : text.headlineMedium;
    final nextStyle = nextBase?.copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final currentStart = current.startTime.inMilliseconds;

    return Center(
      child: ConstrainedBox(
        key: const ValueKey('fullscreen-ktv-lyric-stage-frame'),
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spec.pageGutter.clamp(16, 48).toDouble(),
            vertical: spec.isShort ? AppSpacing.sm : AppSpacing.lg,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AnimatedLyricLine(
                slot: 'previous',
                line: previous,
                style: previousStyle,
                maxLines: spec.isShort ? 1 : 2,
              ),
              SizedBox(height: gap),
              _AnimatedLyricLine(
                slot: 'current',
                line: current,
                style: currentStyle,
                maxLines: spec.isShort ? 2 : 3,
                content: KtvKaraokeLine(
                  key: ValueKey('karaoke:$currentStart'),
                  textKey: ValueKey('current:$currentStart'),
                  line: current,
                  position: position,
                  offset: document?.globalOffset ?? Duration.zero,
                  fallbackEnd: next?.startTime,
                  isPlaying: isPlaying,
                  style: currentStyle,
                  maxLines: spec.isShort ? 2 : 3,
                ),
              ),
              SizedBox(height: gap),
              _AnimatedLyricLine(
                slot: 'next',
                line: next,
                style: nextStyle,
                maxLines: spec.isShort ? 1 : 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedLyricLine extends StatelessWidget {
  final String slot;
  final LyricLine? line;
  final TextStyle? style;
  final int maxLines;

  /// Replaces the plain text, e.g. with the karaoke-coloured current line.
  /// Must carry its own key so the switcher animates line changes.
  final Widget? content;

  const _AnimatedLyricLine({
    required this.slot,
    required this.line,
    required this.style,
    required this.maxLines,
    this.content,
  });

  @override
  Widget build(BuildContext context) {
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
      child:
          content ??
          Text(
            line?.text ?? '',
            key: ValueKey('$slot:${line?.startTime.inMilliseconds ?? -1}'),
            textAlign: TextAlign.center,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
    );
  }
}
