import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// Where the lyrics for a song should come from.
enum LyricsSourceChoice {
  /// Search the lyric sites, timed lyrics first, and check them by ear.
  online,

  /// A lyric file on disk (LRC, SRT, WebVTT, ASS or TXT).
  file,

  /// Text the user pastes; plain text becomes reference lyrics.
  paste,
}

/// Asks where the lyrics should come from.
///
/// [onlineAvailable] hides the search when the app was built without lyric
/// sites (tests, offline builds); [fileAvailable] hides the file picker where
/// a caller has no importer for it.
Future<LyricsSourceChoice?> showLyricsSourceSheet(
  BuildContext context, {
  required bool onlineAvailable,
  bool fileAvailable = true,
  String? songTitle,
}) {
  return showModalBottomSheet<LyricsSourceChoice>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: AppColors.bgElevated,
    builder: (context) => LyricsSourceSheet(
      onlineAvailable: onlineAvailable,
      fileAvailable: fileAvailable,
      songTitle: songTitle,
    ),
  );
}

class LyricsSourceSheet extends StatelessWidget {
  final bool onlineAvailable;
  final bool fileAvailable;
  final String? songTitle;

  const LyricsSourceSheet({
    super.key,
    required this.onlineAvailable,
    this.fileAvailable = true,
    this.songTitle,
  });

  @override
  Widget build(BuildContext context) {
    final title = songTitle?.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(
              title == null || title.isEmpty ? '添加歌词' : '为“$title”添加歌词',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (onlineAvailable)
            ListTile(
              key: const ValueKey('lyrics-source-online'),
              leading: const Icon(Icons.travel_explore_rounded),
              title: const Text('联网获取歌词（推荐）'),
              subtitle: const Text('优先找带时间轴的歌词，试听确认后再保存；对不上可以只保留文字'),
              onTap: () => Navigator.of(context).pop(LyricsSourceChoice.online),
            ),
          if (fileAvailable)
            ListTile(
              key: const ValueKey('lyrics-source-file'),
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('导入歌词文件'),
              subtitle: const Text('LRC、SRT、VTT、ASS 或 TXT；TXT 会作为无时间轴的参考歌词'),
              onTap: () => Navigator.of(context).pop(LyricsSourceChoice.file),
            ),
          ListTile(
            key: const ValueKey('lyrics-source-paste'),
            leading: const Icon(Icons.content_paste_rounded),
            title: const Text('粘贴歌词文本'),
            subtitle: const Text('纯文本保存为参考歌词，播放时静态显示、手动滚动'),
            onTap: () => Navigator.of(context).pop(LyricsSourceChoice.paste),
          ),
        ],
      ),
    );
  }
}
