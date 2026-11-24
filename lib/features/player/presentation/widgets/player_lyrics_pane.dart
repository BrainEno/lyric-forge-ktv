import 'package:flutter/material.dart';

import '../../../../core/layout/app_capabilities.dart';
import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_tap_target.dart';
import '../../../project/domain/models/lyric_timing.dart';
import 'lyrics_source_sheet.dart';
import 'player_lyric_semantics.dart';
import 'reference_lyrics_view.dart';

class PlayerLyricsPane extends StatelessWidget {
  final List<LyricLine> lyrics;

  /// Reference lyrics: shown statically, never followed or tapped to seek.
  final bool untimed;
  final String? sourceLabel;
  final bool ktvMode;
  final int? currentIndex;
  final ValueChanged<LyricLine> onLyricTap;
  final VoidCallback? onOpenFullScreenKtv;
  final Future<void> Function()? onOpenLyricEditor;
  final ValueChanged<LyricsSourceChoice?>? onAddLyrics;
  final bool onlineLyricsAvailable;

  const PlayerLyricsPane({
    super.key,
    required this.lyrics,
    required this.untimed,
    required this.sourceLabel,
    required this.ktvMode,
    required this.currentIndex,
    required this.onLyricTap,
    required this.onOpenFullScreenKtv,
    required this.onOpenLyricEditor,
    required this.onAddLyrics,
    required this.onlineLyricsAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final addLyrics = onAddLyrics;
    if (lyrics.isEmpty) {
      return _NoLyricsState(
        onAddLyrics: addLyrics,
        onlineLyricsAvailable: onlineLyricsAvailable,
      );
    }
    if (untimed) {
      return ReferenceLyricsView(
        lines: lyrics,
        sourceLabel: sourceLabel,
        onOpenEditor: onOpenLyricEditor,
        onFindTimedLyrics: addLyrics != null && onlineLyricsAvailable
            ? () => addLyrics(LyricsSourceChoice.online)
            : null,
      );
    }
    final spec = AppResponsive.of(context);
    final gutter = spec.pageGutter.clamp(12, 28).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            spec.isShort ? 6 : AppSpacing.md,
            gutter,
            spec.isShort ? 4 : AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ktvMode ? 'KTV 歌词' : '同步歌词',
                  style:
                      (spec.isCompact || spec.isShort
                              ? Theme.of(context).textTheme.titleMedium
                              : Theme.of(context).textTheme.titleLarge)
                          ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (ktvMode && onOpenFullScreenKtv != null)
                spec.isCompact
                    ? IconButton(
                        tooltip: '全屏 KTV',
                        onPressed: onOpenFullScreenKtv,
                        icon: const Icon(Icons.fullscreen_rounded),
                      )
                    : TextButton.icon(
                        onPressed: onOpenFullScreenKtv,
                        icon: const Icon(Icons.fullscreen_rounded),
                        label: const Text('全屏'),
                      ),
            ],
          ),
        ),
        Expanded(
          child: ktvMode
              ? _KtvFocusLyrics(
                  lyrics: lyrics,
                  currentIndex: currentIndex,
                  onLyricTap: onLyricTap,
                )
              : _ScrollableLyrics(
                  lyrics: lyrics,
                  currentIndex: currentIndex,
                  onLyricTap: onLyricTap,
                ),
        ),
      ],
    );
  }
}

class _ScrollableLyrics extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int? currentIndex;
  final ValueChanged<LyricLine> onLyricTap;

  const _ScrollableLyrics({
    required this.lyrics,
    required this.currentIndex,
    required this.onLyricTap,
  });

  @override
  State<_ScrollableLyrics> createState() => _ScrollableLyricsState();
}

class _ScrollableLyricsState extends State<_ScrollableLyrics> {
  static const double _estimatedRowExtent = 68;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(covariant _ScrollableLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.lyrics.length != widget.lyrics.length) {
      _scheduleFollow();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleFollow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final index = widget.currentIndex;
      if (index == null || index < 0 || index >= widget.lyrics.length) return;

      final position = _scrollController.position;
      final rawTarget =
          index * _estimatedRowExtent - position.viewportDimension * 0.4;
      final target = rawTarget
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((_scrollController.offset - target).abs() < 18) return;

      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final gutter = spec.pageGutter.clamp(10, 28).toDouble();
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        gutter,
        spec.isShort ? 4 : AppSpacing.sm,
        gutter,
        spec.isShort ? AppSpacing.md : AppSpacing.xxl,
      ),
      itemCount: widget.lyrics.length,
      itemBuilder: (context, index) {
        final line = widget.lyrics[index];
        final current = widget.currentIndex == index;
        return Material(
          color: current ? AppColors.accent.withAlpha(18) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          child: AppTapTarget(
            label: PlayerLyricSemantics.listRow(
              time: _formatTime(line.startTime),
              text: line.text,
              chorus: line.isChorus,
              current: current,
            ),
            hint: PlayerLyricSemantics.seekHint,
            selected: current,
            onTap: () => widget.onLyricTap(line),
            child: InkWell(
              onTap: () => widget.onLyricTap(line),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              child: Container(
                constraints: BoxConstraints(
                  minHeight: spec.minimumInteractiveExtent,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: spec.isCompact ? AppSpacing.sm : AppSpacing.md,
                  vertical: spec.isShort ? 6 : AppSpacing.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: spec.isCompact ? 48 : 58,
                      child: Text(
                        _formatTime(line.startTime),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: current
                              ? AppColors.accent
                              : AppColors.textTertiary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line.text,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: current
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight: current
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              height: spec.isShort ? 1.3 : 1.45,
                            ),
                      ),
                    ),
                    if (line.isChorus && !spec.isCompact)
                      Padding(
                        padding: EdgeInsets.only(left: AppSpacing.sm),
                        child: Icon(
                          Icons.queue_music_rounded,
                          size: 18,
                          color: AppColors.accent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KtvFocusLyrics extends StatelessWidget {
  final List<LyricLine> lyrics;
  final int? currentIndex;
  final ValueChanged<LyricLine> onLyricTap;

  const _KtvFocusLyrics({
    required this.lyrics,
    required this.currentIndex,
    required this.onLyricTap,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final index = (currentIndex ?? 0).clamp(0, lyrics.length - 1).toInt();
    final previous = index > 0 ? lyrics[index - 1] : null;
    final current = lyrics[index];
    final next = index + 1 < lyrics.length ? lyrics[index + 1] : null;
    final gap = spec.isShort ? AppSpacing.sm : AppSpacing.xl;
    final horizontal = spec.pageGutter.clamp(16, 48).toDouble();

    final previousStyle =
        (spec.isShort || spec.isCompact
                ? Theme.of(context).textTheme.bodyLarge
                : Theme.of(context).textTheme.titleMedium)
            ?.copyWith(color: AppColors.textTertiary);
    final currentStyle =
        (spec.isShort || spec.isCompact
                ? Theme.of(context).textTheme.headlineSmall
                : Theme.of(context).textTheme.headlineMedium)
            ?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w900,
              height: 1.3,
            );
    final nextStyle =
        (spec.isShort || spec.isCompact
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.titleLarge)
            ?.copyWith(color: AppColors.textSecondary);

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: spec.isShort ? AppSpacing.sm : AppSpacing.xxl,
        ),
        child: Column(
          children: [
            _FocusLyricLine(
              line: previous,
              role: PlayerFocusLyricRole.previous,
              style: previousStyle,
              onTap: previous == null ? null : () => onLyricTap(previous),
            ),
            SizedBox(height: gap),
            _FocusLyricLine(
              line: current,
              role: PlayerFocusLyricRole.current,
              style: currentStyle,
              onTap: () => onLyricTap(current),
            ),
            SizedBox(height: gap),
            _FocusLyricLine(
              line: next,
              role: PlayerFocusLyricRole.next,
              style: nextStyle,
              onTap: next == null ? null : () => onLyricTap(next),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusLyricLine extends StatelessWidget {
  final LyricLine? line;
  final PlayerFocusLyricRole role;
  final TextStyle? style;
  final VoidCallback? onTap;

  const _FocusLyricLine({
    required this.line,
    required this.role,
    required this.style,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    if (line == null) {
      return SizedBox(height: spec.isShort ? 18 : 32);
    }
    return AppTapTarget(
      label: PlayerLyricSemantics.focusLine(role, line!.text),
      hint: onTap == null ? null : PlayerLyricSemantics.seekHint,
      selected: role == PlayerFocusLyricRole.current,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: Container(
          constraints: BoxConstraints(minHeight: spec.minimumInteractiveExtent),
          padding: EdgeInsets.all(spec.isShort ? 6 : AppSpacing.sm),
          child: Text(line!.text, textAlign: TextAlign.center, style: style),
        ),
      ),
    );
  }
}

class _NoLyricsState extends StatelessWidget {
  final ValueChanged<LyricsSourceChoice?>? onAddLyrics;
  final bool onlineLyricsAvailable;

  const _NoLyricsState({
    required this.onAddLyrics,
    required this.onlineLyricsAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final addLyrics = onAddLyrics;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(spec.pageGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 52,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppCapabilities.lyricWorkbench ? '这个工程还没有歌词' : '这首歌还没有歌词',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              addLyrics == null
                  ? '可以继续普通播放，有时间轴的歌词才能进入 KTV 模式。'
                  : '可以联网获取歌词，或粘贴纯文本歌词作为参考（静态显示、手动滚动）；'
                        '有时间轴的歌词才能进入 KTV 模式。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
            if (addLyrics != null) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (onlineLyricsAvailable)
                    FilledButton.icon(
                      key: const ValueKey('player-fetch-lyrics'),
                      onPressed: () => addLyrics(LyricsSourceChoice.online),
                      icon: const Icon(Icons.travel_explore_rounded),
                      label: const Text('联网获取歌词'),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('player-paste-lyrics'),
                    onPressed: () => addLyrics(LyricsSourceChoice.paste),
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('粘贴歌词'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('player-import-lyrics-file'),
                    onPressed: () => addLyrics(LyricsSourceChoice.file),
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('导入歌词文件'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatTime(Duration value) {
  final minutes = value.inMinutes.toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
