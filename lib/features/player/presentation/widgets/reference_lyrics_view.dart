import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';

/// Title shown above lyrics that have no timing.
const String referenceLyricsTitle = '参考歌词（无时间轴）';

/// Untimed lyrics as static text the listener scrolls by hand (D-054).
///
/// No line is highlighted, nothing follows the playback position and a tap
/// does not seek — every line's time is 0:00, so any of that would be wrong.
/// The banner says why and offers the two ways to get timing: tap it in the
/// editor, or look for a timed version online.
class ReferenceLyricsView extends StatefulWidget {
  final List<LyricLine> lines;

  /// Where the lyrics came from, e.g. "网易云音乐" or "粘贴"; optional.
  final String? sourceLabel;
  final VoidCallback? onOpenEditor;
  final VoidCallback? onFindTimedLyrics;

  const ReferenceLyricsView({
    super.key,
    required this.lines,
    this.sourceLabel,
    this.onOpenEditor,
    this.onFindTimedLyrics,
  });

  @override
  State<ReferenceLyricsView> createState() => _ReferenceLyricsViewState();
}

class _ReferenceLyricsViewState extends State<ReferenceLyricsView> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final gutter = spec.pageGutter.clamp(12, 28).toDouble();
    final theme = Theme.of(context).textTheme;
    final source = widget.sourceLabel?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            spec.isShort ? AppSpacing.xs : AppSpacing.md,
            gutter,
            AppSpacing.xs,
          ),
          child: Text(
            referenceLyricsTitle,
            style: (spec.isCompact || spec.isShort
                    ? theme.titleMedium
                    : theme.titleLarge)
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: _ReferenceBanner(
            sourceLabel: source == null || source.isEmpty ? null : source,
            onOpenEditor: widget.onOpenEditor,
            onFindTimedLyrics: widget.onFindTimedLyrics,
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: ListView.builder(
              key: const ValueKey('reference-lyrics-list'),
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                gutter,
                AppSpacing.md,
                gutter,
                spec.isShort ? AppSpacing.md : AppSpacing.xxl,
              ),
              itemCount: widget.lines.length,
              itemBuilder: (context, index) {
                final line = widget.lines[index];
                return Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: spec.isShort ? AppSpacing.xs : AppSpacing.sm,
                  ),
                  child: Text(
                    line.text,
                    textAlign: TextAlign.center,
                    style: theme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: spec.isShort ? 1.3 : 1.5,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ReferenceBanner extends StatelessWidget {
  final String? sourceLabel;
  final VoidCallback? onOpenEditor;
  final VoidCallback? onFindTimedLyrics;

  const _ReferenceBanner({
    required this.sourceLabel,
    required this.onOpenEditor,
    required this.onFindTimedLyrics,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    final editor = onOpenEditor;
    final find = onFindTimedLyrics;
    return Container(
      key: const ValueKey('reference-lyrics-banner'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '这份歌词没有时间轴，不会跟着播放滚动或高亮，请手动滚动查看。'
            '打轴后可以同步显示并进入 KTV。'
            '${sourceLabel == null ? '' : '（来源：$sourceLabel）'}',
            style: style,
          ),
          if (editor != null || find != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (editor != null)
                  OutlinedButton.icon(
                    key: const ValueKey('reference-lyrics-open-editor'),
                    onPressed: editor,
                    icon: const Icon(Icons.touch_app_outlined),
                    label: const Text('去打轴'),
                  ),
                if (find != null)
                  OutlinedButton.icon(
                    key: const ValueKey('reference-lyrics-find-timed'),
                    onPressed: find,
                    icon: const Icon(Icons.travel_explore_rounded),
                    label: const Text('联网找带时间轴的歌词'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A short label for where [metadata] says the lyrics came from.
String? lyricSourceLabel(Map<String, dynamic> metadata) {
  final online = metadata['onlineSourceLabel'];
  if (online is String && online.trim().isNotEmpty) return online;
  return switch (metadata['source']) {
    'pasted-text' => '粘贴',
    'imported-file' => '歌词文件',
    _ => null,
  };
}
