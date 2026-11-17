import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_word_timing_service.dart';

/// The selected row's word timing in the inspector: every word with the
/// time it starts, so a misaligned word (or one the aligner stretched over
/// a long note) is visible without opening an export.
///
/// Rows without word timing show nothing. A row whose text no longer
/// matches its word timing says so, because karaoke export then falls back
/// to an estimate for it.
class LyricWordTimingStrip extends StatelessWidget {
  const LyricWordTimingStrip({
    super.key,
    required this.line,
    this.service = const LyricWordTimingService(),
    this.onSeek,
    this.onClear,
    this.onEdit,
  });

  final LyricLine line;
  final LyricWordTimingService service;

  /// Seeks the audio to a word's start (lyric timeline); null makes the
  /// chips display-only.
  final ValueChanged<Duration>? onSeek;

  /// Removes the row's word timing, so karaoke export estimates it again.
  final VoidCallback? onClear;

  /// Opens word timing fine-tuning for the row; null hides the button.
  final VoidCallback? onEdit;

  /// A word held at least this long is marked: it is either a long note or
  /// an alignment that swallowed a pause, and worth a listen.
  static const Duration longWord = Duration(milliseconds: 2500);

  static const String staleNote =
      '这一行的文字已改动（字数与逐字时间不一致），逐字时间暂不使用，导出卡拉 OK 时按字数估算。';

  @override
  Widget build(BuildContext context) {
    if (line.words.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final words = service.normalized(line);
    final label = Text(
      '逐字时间',
      style: theme.textTheme.labelMedium?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
    final clear = onClear == null
        ? null
        : TextButton(
            key: const ValueKey('word_timing_clear'),
            onPressed: onClear,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            ),
            child: const Text('清除'),
          );
    final edit = onEdit == null
        ? null
        : TextButton(
            key: const ValueKey('word_timing_edit'),
            onPressed: onEdit,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            ),
            child: const Text('微调'),
          );
    if (words.isEmpty) {
      return Column(
        key: const ValueKey('word_timing_stale'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: label),
              ?clear,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            staleNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.warning,
            ),
          ),
        ],
      );
    }
    final longCount = words.where((w) => w.end - w.start >= longWord).length;
    return Column(
      key: const ValueKey('word_timing_strip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            label,
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                longCount == 0
                    ? '${words.length} 个词'
                    : '${words.length} 个词，$longCount 个拖长超过 '
                          '${longWord.inMilliseconds / 1000} 秒',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: longCount == 0
                      ? AppColors.textTertiary
                      : AppColors.warning,
                ),
              ),
            ),
            ?edit,
            ?clear,
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (var index = 0; index < words.length; index++)
              _WordChip(
                key: ValueKey('word_timing_$index'),
                word: words[index],
                long: words[index].end - words[index].start >= longWord,
                onTap: onSeek == null
                    ? null
                    : () => onSeek!(words[index].start),
              ),
          ],
        ),
      ],
    );
  }

  /// `m:ss.s`, compact enough for a chip.
  static String clock(Duration value) {
    final minutes = value.inMinutes;
    final tenths = (value.inMilliseconds % 60000) ~/ 100;
    final seconds = tenths ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${tenths % 10}';
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    super.key,
    required this.word,
    required this.long,
    this.onTap,
  });

  final LyricWordTiming word;
  final bool long;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds = (word.end - word.start).inMilliseconds / 1000;
    return Tooltip(
      message:
          '${LyricWordTimingStrip.clock(word.start)} → '
          '${LyricWordTimingStrip.clock(word.end)}'
          ' · ${seconds.toStringAsFixed(2)} 秒'
          '${onTap == null ? '' : ' · 点击跳到这里'}',
      child: _tappable(
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.bgBase,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: long ? AppColors.warning : AppColors.textTertiary,
              width: long ? 1.2 : 0.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(word.text.trim(), style: theme.textTheme.bodyMedium),
              Text(
                LyricWordTimingStrip.clock(word.start),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tappable(Widget child) {
    final tap = onTap;
    if (tap == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: tap, child: child),
    );
  }
}
