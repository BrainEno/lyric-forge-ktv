import 'package:flutter/material.dart';

import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../domain/services/playback_session_service.dart';

/// Where a playing item comes from.
enum PlaybackOrigin {
  local('本地音乐'),
  remote('桌面音乐库'),
  project('歌词工程');

  const PlaybackOrigin(this.label);

  /// Name shown above the title on Now Playing.
  final String label;

  static PlaybackOrigin of(PlaybackItem item) {
    if (item.projectId != null) return PlaybackOrigin.project;
    if (item.isRemoteStream) return PlaybackOrigin.remote;
    return PlaybackOrigin.local;
  }
}

/// The format and lyrics badges under a song title.
///
/// Now Playing and quick play each kept a private `_InfoChip` and their own
/// set of facts: one showed `MP3`, `LOCAL` and `LYRICS`, the other `MP3`,
/// `已有歌词` or `未添加歌词`, and `LOCAL` again. The origin badge repeated
/// what both pages already say (the 本地音乐 title on quick play, the
/// origin line above the title on Now Playing) and the English words broke
/// the Chinese interface. Both pages now show the same two facts with the
/// same words (audit: player family, duplicated `_InfoChip`).
class PlaybackFactBadges extends StatelessWidget {
  const PlaybackFactBadges({
    super.key,
    required this.item,
    this.showMissingLyrics = true,
  });

  final PlaybackItem item;

  /// Shows [missingLyricsLabel] for songs without lyrics. Quick play keeps it
  /// because its lyrics button is right below; Now Playing only mentions
  /// lyrics that exist.
  final bool showMissingLyrics;

  static const String unknownFormatLabel = '音频';
  static const String lyricsLabel = '已有歌词';
  static const String missingLyricsLabel = '未添加歌词';

  /// The file format in capitals, such as `MP3`, or [unknownFormatLabel].
  static String formatLabel(PlaybackItem item) {
    final format = item.audioAsset.format.trim();
    final bare = format.startsWith('.') ? format.substring(1) : format;
    return bare.isEmpty ? unknownFormatLabel : bare.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        AppBadge(label: formatLabel(item), emphasized: true),
        if (item.hasLyrics)
          const AppBadge(
            label: lyricsLabel,
            icon: Icons.lyrics_rounded,
            tone: AppBadgeTone.success,
            emphasized: true,
          )
        else if (showMissingLyrics)
          const AppBadge(label: missingLyricsLabel),
      ],
    );
  }
}
