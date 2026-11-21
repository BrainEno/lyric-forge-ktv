import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../lyrics/domain/online/online_lyric_query.dart';
import '../../../lyrics/domain/online/song_lyrics_lookup.dart';
import '../../../lyrics/domain/services/lyric_file_import_service.dart';
import '../../../lyrics/domain/text/chinese_script_converter.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/lyric_timing.dart';

/// How the preview reaches the song that is playing, so the user can hear
/// whether the fetched timestamps line up.
///
/// Kept as plain callbacks rather than the player services: the preview is
/// opened from the library (a song that may not be playing yet) and from the
/// project player (a song that already is), and both answer the same four
/// questions differently.
class SongLyricsPreviewPlayback {
  /// Playback position updates of the app player.
  final Stream<Duration> positionStream;

  /// The position right now, before the stream says anything.
  final Duration Function() currentPosition;

  /// Whether the app player is on this song; positions of another song mean
  /// nothing to the preview.
  final bool Function() isCurrentSong;

  final Future<void> Function(Duration position) seek;

  /// Starts this song when it is not the one playing; null when the caller
  /// cannot (the project player always is on its song).
  final Future<void> Function()? playSong;

  final Future<void> Function()? togglePlayPause;

  const SongLyricsPreviewPlayback({
    required this.positionStream,
    required this.currentPosition,
    required this.isCurrentSong,
    required this.seek,
    this.playSong,
    this.togglePlayPause,
  });
}

/// What the user decided in the preview.
class SongLyricsChoice {
  final SongLyricsOption option;

  /// The lyrics to save: timed (with the user's shift applied) or plain.
  final LyricImportResult result;

  const SongLyricsChoice({required this.option, required this.result});

  bool get timed => result.document.isTimed;
}

/// Searches the lyric sites for one song and lets the user check the timing
/// before anything is saved.
///
/// Returns null when the user cancels or nothing usable was found.
Future<SongLyricsChoice?> showSongLyricsPreviewDialog(
  BuildContext context, {
  required SongLyricsLookup lookup,
  required OnlineLyricQuery query,
  SongLyricsPreviewPlayback? playback,
}) {
  return showDialog<SongLyricsChoice>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SongLyricsPreviewDialog(
      lookup: lookup,
      query: query,
      playback: playback,
    ),
  );
}

/// The script the preview converts the lyric to; null keeps it as found.
enum _ScriptChoice {
  keep('原样', null),
  simplified('简体', ChineseScriptTarget.simplified),
  traditional('繁體', ChineseScriptTarget.traditionalTaiwan);

  const _ScriptChoice(this.label, this.target);

  final String label;
  final ChineseScriptTarget? target;
}

class SongLyricsPreviewDialog extends StatefulWidget {
  final SongLyricsLookup lookup;
  final OnlineLyricQuery query;
  final SongLyricsPreviewPlayback? playback;

  const SongLyricsPreviewDialog({
    super.key,
    required this.lookup,
    required this.query,
    this.playback,
  });

  /// One nudge of the whole lyric, in either direction.
  static const Duration offsetStep = Duration(milliseconds: 500);

  @override
  State<SongLyricsPreviewDialog> createState() =>
      _SongLyricsPreviewDialogState();
}

class _SongLyricsPreviewDialogState extends State<SongLyricsPreviewDialog> {
  static const double _estimatedRowExtent = 40;

  late final TextEditingController _title;
  late final TextEditingController _artist;
  final ScrollController _lines = ScrollController();
  StreamSubscription<Duration>? _positionSubscription;

  SongLyricsLookupResult? _result;
  Object? _error;
  bool _loading = false;
  int _selected = 0;
  Duration _offset = Duration.zero;
  _ScriptChoice _script = _ScriptChoice.keep;
  Duration _position = Duration.zero;
  int? _activeIndex;
  bool _followPlayback = true;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.query.title);
    _artist = TextEditingController(text: widget.query.artist);
    final playback = widget.playback;
    if (playback != null) {
      _position = playback.currentPosition();
      _positionSubscription = playback.positionStream.listen(_onPosition);
    }
    _loading = true;
    _runSearch();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _title.dispose();
    _artist.dispose();
    _lines.dispose();
    super.dispose();
  }

  SongLyricsOption? get _option {
    final options = _result?.options ?? const <SongLyricsOption>[];
    if (options.isEmpty) return null;
    return options[_selected.clamp(0, options.length - 1).toInt()];
  }

  /// The lyric as it would be saved with timing: shifted and converted.
  LyricImportResult? get _timedPreview {
    final timed = _option?.timed;
    if (timed == null) return null;
    return scriptConvertedImportResult(
      shiftedImportResult(timed, _offset),
      _script.target,
    );
  }

  LyricImportResult? get _plainPreview {
    final plain = _option?.plain;
    if (plain == null) return null;
    return scriptConvertedImportResult(plain, _script.target);
  }

  bool get _playbackIsThisSong => widget.playback?.isCurrentSong() ?? false;

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _runSearch();
  }

  Future<void> _runSearch() async {
    final generation = ++_searchGeneration;
    final query = OnlineLyricQuery(
      title: _title.text.trim(),
      artist: _artist.text.trim(),
      duration: widget.query.duration,
    );
    try {
      final result = await widget.lookup.find(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _result = result;
        _selected = 0;
        _offset = Duration.zero;
        _loading = false;
        _activeIndex = _computeActiveIndex();
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _onPosition(Duration position) {
    if (!mounted) return;
    _position = position;
    final index = _computeActiveIndex();
    if (index == _activeIndex) return;
    setState(() => _activeIndex = index);
    _scheduleFollow();
  }

  int? _computeActiveIndex() {
    if (!_playbackIsThisSong) return null;
    final document = _option?.timed?.document;
    if (document == null) return null;
    return document.activeLineIndex(_position, extraOffset: _offset);
  }

  void _scheduleFollow() {
    if (!_followPlayback) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final index = _activeIndex;
      if (!mounted || index == null || !_lines.hasClients) return;
      final position = _lines.position;
      final target =
          (index * _estimatedRowExtent - position.viewportDimension * 0.35)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
      if ((_lines.offset - target).abs() < _estimatedRowExtent / 2) return;
      _lines.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _select(int index) {
    setState(() {
      _selected = index;
      _offset = Duration.zero;
      _activeIndex = _computeActiveIndex();
    });
    if (_lines.hasClients) _lines.jumpTo(0);
  }

  void _nudge(Duration delta) {
    setState(() {
      _offset += delta;
      _activeIndex = _computeActiveIndex();
    });
    _scheduleFollow();
  }

  Future<void> _seekToLine(LyricDocument document, LyricLine line) async {
    final playback = widget.playback;
    if (playback == null) return;
    if (!_playbackIsThisSong) {
      final playSong = playback.playSong;
      if (playSong == null) return;
      await playSong();
    }
    await playback.seek(document.effectiveStart(line, extraOffset: _offset));
  }

  Future<void> _playThisSong() async {
    final playSong = widget.playback?.playSong;
    if (playSong == null) return;
    await playSong();
    if (!mounted) return;
    setState(() => _activeIndex = _computeActiveIndex());
  }

  void _choose(LyricImportResult result) {
    final option = _option;
    if (option == null) return;
    Navigator.of(context).pop(SongLyricsChoice(option: option, result: result));
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final media = MediaQuery.of(context);
    final width = spec.isCompact
        ? (spec.width - spec.pageGutter * 2).clamp(280.0, 560.0).toDouble()
        : 640.0;
    final height = (media.size.height - spec.pageGutter * 2 - 180)
        .clamp(240.0, 640.0)
        .toDouble();
    final option = _option;
    final timed = _timedPreview;
    final plain = _plainPreview;

    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      insetPadding: EdgeInsets.all(spec.pageGutter),
      title: const Text('联网获取歌词'),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _QueryFields(
              title: _title,
              artist: _artist,
              loading: _loading,
              onSearch: _search,
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _body(context, option, timed, plain)),
          ],
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (option != null && timed != null && plain != null) ...[
          TextButton(
            key: const ValueKey('song-lyrics-use-plain'),
            onPressed: () => _choose(plain),
            child: const Text('只用文字（去掉时间戳）'),
          ),
          FilledButton.icon(
            key: const ValueKey('song-lyrics-use-timed'),
            onPressed: () => _choose(timed),
            icon: const Icon(Icons.check_rounded),
            label: const Text('采用（带时间轴）'),
          ),
        ] else if (option != null && plain != null)
          FilledButton.icon(
            key: const ValueKey('song-lyrics-use-plain'),
            onPressed: () => _choose(plain),
            icon: const Icon(Icons.check_rounded),
            label: const Text('采用纯文本歌词'),
          ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    SongLyricsOption? option,
    LyricImportResult? timed,
    LyricImportResult? plain,
  ) {
    if (_loading) {
      return const _Message(
        icon: Icons.travel_explore_rounded,
        title: '正在查找歌词',
        detail: '正在从 LRCLIB、网易云音乐、酷狗音乐查找，只会发送歌名、歌手和时长。',
        busy: true,
      );
    }
    final error = _error;
    if (error != null) {
      return _Message(
        icon: Icons.wifi_off_rounded,
        title: '查找失败',
        detail: '$error',
      );
    }
    final result = _result;
    if (result == null || option == null || plain == null) {
      final offline = result?.allSourcesFailed == true;
      final reasons = [
        for (final entry in (result?.failures ?? const {}).entries)
          '${entry.key.label}：${entry.value}',
      ].join('\n');
      return _Message(
        icon: Icons.search_off_rounded,
        title: offline ? '连不上歌词网站' : '没有找到这首歌的歌词',
        detail: offline
            ? '请检查网络或代理设置后重试。\n$reasons'
            : '可以改一下歌名或歌手再搜，或者关闭后选择“粘贴歌词文本”。',
      );
    }

    final document = (timed ?? plain).document;
    final header = <Widget>[
      _OptionPicker(
        key: ValueKey('song-lyrics-options-$_searchGeneration'),
        options: result.options,
        selected: _selected,
        onSelected: _select,
      ),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final note in option.notes)
            Chip(visualDensity: VisualDensity.compact, label: Text(note)),
          for (final choice in _ScriptChoice.values)
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              selected: _script == choice,
              label: Text(choice.label),
              onSelected: (_) => setState(() => _script = choice),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      if (timed != null) ...[
        _TimingHint(
          durationMismatch: option.durationMismatch,
          playbackAvailable: widget.playback != null,
        ),
        if (widget.playback != null)
          _PlaybackRow(
            playingThisSong: _playbackIsThisSong,
            canPlaySong: widget.playback?.playSong != null,
            offset: _offset,
            followPlayback: _followPlayback,
            onPlaySong: _playThisSong,
            onTogglePlay: widget.playback?.togglePlayPause,
            onEarlier: () => _nudge(-SongLyricsPreviewDialog.offsetStep),
            onLater: () => _nudge(SongLyricsPreviewDialog.offsetStep),
            onResetOffset: _offset == Duration.zero
                ? null
                : () => _nudge(-_offset),
            onFollowChanged: (value) =>
                setState(() => _followPlayback = value),
          ),
      ] else
        Text(
          '这份歌词没有时间轴。保存后播放器会显示静态歌词，需要手动滚动查看。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      const SizedBox(height: AppSpacing.xs),
    ];
    final lines = _PreviewLines(
      controller: _lines,
      document: document,
      timed: timed != null,
      activeIndex: timed == null ? null : _activeIndex,
      onTapLine: timed == null || widget.playback == null
          ? null
          : (line) => _seekToLine(document, line),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // On a short window the controls would leave the list no room, so
        // everything scrolls together and the list keeps a usable height.
        if (constraints.maxHeight < 420) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...header,
                SizedBox(height: _shortListHeight, child: lines),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [...header, Expanded(child: lines)],
        );
      },
    );
  }

  static const double _shortListHeight = 220;
}

class _QueryFields extends StatelessWidget {
  final TextEditingController title;
  final TextEditingController artist;
  final bool loading;
  final VoidCallback onSearch;

  const _QueryFields({
    required this.title,
    required this.artist,
    required this.loading,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            key: const ValueKey('song-lyrics-title'),
            controller: title,
            enabled: !loading,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: const InputDecoration(labelText: '歌名', isDense: true),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: TextField(
            key: const ValueKey('song-lyrics-artist'),
            controller: artist,
            enabled: !loading,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: const InputDecoration(labelText: '歌手', isDense: true),
          ),
        ),
        IconButton(
          tooltip: '重新搜索',
          onPressed: loading ? null : onSearch,
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    );
  }
}

class _OptionPicker extends StatelessWidget {
  final List<SongLyricsOption> options;
  final int selected;
  final ValueChanged<int> onSelected;

  const _OptionPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '找到 ${options.length} 个版本',
        isDense: true,
      ),
      items: [
        for (var index = 0; index < options.length; index++)
          DropdownMenuItem(
            value: index,
            child: Text(
              '${options[index].candidate.displayName}'
              '${options[index].hasTiming ? '' : '（纯文本）'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) onSelected(value);
      },
    );
  }
}

class _TimingHint extends StatelessWidget {
  final bool durationMismatch;
  final bool playbackAvailable;

  const _TimingHint({
    required this.durationMismatch,
    required this.playbackAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (durationMismatch)
          Text(
            '这份歌词对应的录音和你的歌曲时长不同，可能是别的版本，时间轴很可能对不上。',
            style: style?.copyWith(color: AppColors.warning),
          ),
        Text(
          playbackAvailable
              ? '播放歌曲，看高亮行是否跟着演唱走；点任意一行可跳到那里试听。'
                    '整体快了或慢了可以用“提前/推后”微调，对不上就选“只用文字”。'
              : '保存前无法试听；时间轴对不上时，可以选“只用文字”。',
          style: style,
        ),
      ],
    );
  }
}

class _PlaybackRow extends StatelessWidget {
  final bool playingThisSong;
  final bool canPlaySong;
  final Duration offset;
  final bool followPlayback;
  final Future<void> Function() onPlaySong;
  final Future<void> Function()? onTogglePlay;
  final VoidCallback onEarlier;
  final VoidCallback onLater;
  final VoidCallback? onResetOffset;
  final ValueChanged<bool> onFollowChanged;

  const _PlaybackRow({
    required this.playingThisSong,
    required this.canPlaySong,
    required this.offset,
    required this.followPlayback,
    required this.onPlaySong,
    required this.onTogglePlay,
    required this.onEarlier,
    required this.onLater,
    required this.onResetOffset,
    required this.onFollowChanged,
  });

  @override
  Widget build(BuildContext context) {
    final toggle = onTogglePlay;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!playingThisSong && canPlaySong)
          FilledButton.tonalIcon(
            key: const ValueKey('song-lyrics-play-song'),
            onPressed: onPlaySong,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('播放这首歌来核对'),
          )
        else if (playingThisSong && toggle != null)
          IconButton.filledTonal(
            tooltip: '播放/暂停',
            onPressed: toggle,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        OutlinedButton(
          key: const ValueKey('song-lyrics-earlier'),
          onPressed: onEarlier,
          child: const Text('提前 0.5 秒'),
        ),
        OutlinedButton(
          key: const ValueKey('song-lyrics-later'),
          onPressed: onLater,
          child: const Text('推后 0.5 秒'),
        ),
        ActionChip(
          key: const ValueKey('song-lyrics-offset'),
          label: Text('偏移 ${formatLyricOffset(offset)}'),
          onPressed: onResetOffset,
          tooltip: onResetOffset == null ? null : '归零',
        ),
        FilterChip(
          selected: followPlayback,
          label: const Text('跟随播放'),
          onSelected: onFollowChanged,
        ),
      ],
    );
  }
}

/// "+0.5 秒" / "-1.0 秒" / "0 秒".
String formatLyricOffset(Duration offset) {
  if (offset == Duration.zero) return '0 秒';
  final seconds = offset.inMilliseconds / 1000;
  final sign = seconds > 0 ? '+' : '-';
  return '$sign${seconds.abs().toStringAsFixed(1)} 秒';
}

class _PreviewLines extends StatelessWidget {
  final ScrollController controller;
  final LyricDocument document;
  final bool timed;
  final int? activeIndex;
  final ValueChanged<LyricLine>? onTapLine;

  const _PreviewLines({
    required this.controller,
    required this.document,
    required this.timed,
    required this.activeIndex,
    required this.onTapLine,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final lines = document.lines;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Scrollbar(
        controller: controller,
        child: ListView.builder(
          key: const ValueKey('song-lyrics-preview-lines'),
          controller: controller,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            final line = lines[index];
            final active = activeIndex == index;
            final tap = onTapLine;
            return InkWell(
              onTap: tap == null ? null : () => tap(line),
              child: Container(
                color: active ? AppColors.accent.withAlpha(28) : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (timed)
                      SizedBox(
                        width: 52,
                        child: Text(
                          _formatStamp(document.effectiveStart(line)),
                          style: theme.labelSmall?.copyWith(
                            color: active
                                ? AppColors.accent
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        line.text,
                        style: theme.bodyMedium?.copyWith(
                          color: active
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static String _formatStamp(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final bool busy;

  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: AppSpacing.iconSizeLarge,
                child: CircularProgressIndicator(),
              )
            else
              Icon(
                icon,
                size: AppSpacing.iconSizeLarge,
                color: AppColors.textTertiary,
              ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
