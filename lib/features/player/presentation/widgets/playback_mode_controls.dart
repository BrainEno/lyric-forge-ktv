import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../domain/services/playback_session_service.dart';

class PlaybackModeControls extends StatelessWidget {
  final PlaybackSessionService session;
  final bool compact;

  const PlaybackModeControls({
    super.key,
    required this.session,
    this.compact = false,
  });

  PlaybackRepeatMode _nextRepeatMode(PlaybackRepeatMode current) {
    switch (current) {
      case PlaybackRepeatMode.off:
        return PlaybackRepeatMode.all;
      case PlaybackRepeatMode.all:
        return PlaybackRepeatMode.one;
      case PlaybackRepeatMode.one:
        return PlaybackRepeatMode.off;
    }
  }

  String _repeatTooltip(PlaybackRepeatMode mode) {
    switch (mode) {
      case PlaybackRepeatMode.off:
        return '循环关闭 · 点击开启列表循环';
      case PlaybackRepeatMode.all:
        return '列表循环 · 点击切换单曲循环';
      case PlaybackRepeatMode.one:
        return '单曲循环 · 点击关闭循环';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackSessionState>(
      stream: session.stateStream,
      initialData: session.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? session.currentState;
        final shuffle = state.shuffleEnabled;
        final repeat = state.repeatMode;
        final activeColor = Theme.of(context).colorScheme.primary;
        final inactiveColor = AppColors.textTertiary;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: compact ? VisualDensity.compact : null,
              tooltip: shuffle ? '关闭随机播放' : '开启随机播放',
              onPressed: state.queue.length < 2
                  ? null
                  : () => session.setShuffleEnabled(!shuffle),
              color: shuffle ? activeColor : inactiveColor,
              icon: const Icon(Icons.shuffle_rounded),
            ),
            IconButton(
              visualDensity: compact ? VisualDensity.compact : null,
              tooltip: _repeatTooltip(repeat),
              onPressed: state.currentItem == null
                  ? null
                  : () => session.setRepeatMode(_nextRepeatMode(repeat)),
              color: repeat == PlaybackRepeatMode.off
                  ? inactiveColor
                  : activeColor,
              icon: Icon(
                repeat == PlaybackRepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
              ),
            ),
          ],
        );
      },
    );
  }
}
