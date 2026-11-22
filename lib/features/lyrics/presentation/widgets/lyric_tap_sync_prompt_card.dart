import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// Shown above the lyric list while no line has a time (D-054 lyrics taken
/// without timestamps, or pasted text): the words are there, but nothing can
/// follow the song until it is timed, so the next step is 打轴.
///
/// The card goes away by itself once the first times are applied.
class LyricTapSyncPromptCard extends StatelessWidget {
  final int lineCount;

  /// Whether the project has a recording to tap along to.
  final bool hasAudio;

  /// Opens 跟拍打轴; null disables the button.
  final VoidCallback? onStartTapSync;

  const LyricTapSyncPromptCard({
    super.key,
    required this.lineCount,
    required this.hasAudio,
    required this.onStartTapSync,
  });

  static const startKey = ValueKey('lyric-editor-start-tap-sync');

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final theme = Theme.of(context);
    final message = hasAudio
        ? '边听边点，每唱到一行点一下，就能给 $lineCount 行歌词打上时间。'
              '打完后播放器和 KTV 才能跟着唱。'
        : '这个工程还没有音频。先加上歌曲音频，再边听边点给歌词打时间。';
    final button = FilledButton.icon(
      key: startKey,
      onPressed: hasAudio ? onStartTapSync : null,
      icon: const Icon(Icons.touch_app_rounded),
      label: const Text('开始打轴'),
    );
    return Container(
      key: const ValueKey('lyric-editor-tap-sync-prompt'),
      margin: EdgeInsets.fromLTRB(
        spec.isCompact ? AppSpacing.sm : AppSpacing.md,
        AppSpacing.sm,
        spec.isCompact ? AppSpacing.sm : AppSpacing.md,
        AppSpacing.xs,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, color: AppColors.onAccentContainer),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '歌词还没有时间轴',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.onAccentContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onAccentContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(alignment: Alignment.centerLeft, child: button),
        ],
      ),
    );
  }
}
