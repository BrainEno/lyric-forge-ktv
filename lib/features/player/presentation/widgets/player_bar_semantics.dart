import 'package:flutter/material.dart';

import '../../domain/models/playback_state.dart';
import '../../domain/services/playback_session_service.dart';
import 'transport_bar.dart';

/// Screen-reader wording shared by the desktop and mobile player bars.
///
/// The bars are on screen almost all the time, yet a screen reader met an
/// unlabelled artwork button, a queue toggle that only said "3" on compact
/// widths and a play button that kept saying 播放 while it was disabled
/// during loading (audit A-04). Both bars now take their labels from here, and
/// the busy wording matches the full player's [TransportBar].
abstract final class PlayerBarSemantics {
  /// Hint of the title block, which opens the full player.
  static const String openHint = '打开播放页';

  /// Tooltip of the queue toggle.
  static const String queueTooltip = '播放队列';

  /// Whether the play button is locked because the audio is loading.
  static bool isBusy(PlaybackState playback) =>
      playback.isBuffering || playback.isLoading;

  /// Play button label: loading, pause or play.
  static String playPause(PlaybackState playback) {
    if (isBusy(playback)) return TransportBar.busyTooltip;
    return playback.isPlaying
        ? TransportBar.pauseTooltip
        : TransportBar.playTooltip;
  }

  /// What the title block reads, e.g. 正在播放：晴天，周杰伦.
  static String nowPlaying(String title, String subtitle) {
    final cleanTitle = title.trim().isEmpty ? '未命名歌曲' : title.trim();
    final cleanSubtitle = subtitle.trim();
    return cleanSubtitle.isEmpty
        ? '正在播放：$cleanTitle'
        : '正在播放：$cleanTitle，$cleanSubtitle';
  }

  /// Queue toggle label; the compact bar shows only the number.
  static String queue(int count) => count == 0 ? '播放队列为空' : '播放队列，$count 首';

  /// Second line under the title: the artist, or where the song comes from.
  static String subtitleFor(
    PlaybackItem item, {
    required String projectLabel,
    required String remoteLabel,
    required String localLabel,
  }) {
    final artist = item.artist?.trim();
    if (artist != null && artist.isNotEmpty) return artist;
    if (item.projectId != null) return projectLabel;
    if (item.isRemoteStream) return remoteLabel;
    return localLabel;
  }
}

/// Title block of a player bar. Artwork and text open the full player and are
/// read as one button, `正在播放：title，subtitle`, with the hint 打开播放页.
class PlayerBarNowPlayingTarget extends StatelessWidget {
  const PlayerBarNowPlayingTarget({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onOpen,
    required this.child,
  });

  final String title;
  final String subtitle;
  final VoidCallback onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: PlayerBarSemantics.nowPlaying(title, subtitle),
      hint: PlayerBarSemantics.openHint,
      onTap: onOpen,
      excludeSemantics: true,
      child: child,
    );
  }
}

/// Queue toggle of the desktop bar: icon and count, read as
/// 播放队列，N 首 with its expanded state.
class PlayerBarQueueToggle extends StatelessWidget {
  const PlayerBarQueueToggle({
    super.key,
    required this.count,
    required this.expanded,
    required this.compact,
    required this.onToggle,
  });

  final int count;
  final bool expanded;

  /// Shows only the number instead of 队列 N.
  final bool compact;
  final VoidCallback onToggle;

  static const Key toggleKey = ValueKey('player-bar:queue-toggle');

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: PlayerBarSemantics.queueTooltip,
      child: Semantics(
        button: true,
        expanded: expanded,
        label: PlayerBarSemantics.queue(count),
        onTap: onToggle,
        excludeSemantics: true,
        child: TextButton.icon(
          key: toggleKey,
          onPressed: onToggle,
          icon: Icon(
            expanded
                ? Icons.keyboard_arrow_down_rounded
                : Icons.queue_music_rounded,
            size: 20,
          ),
          label: Text(compact ? '$count' : '队列 $count'),
        ),
      ),
    );
  }
}
