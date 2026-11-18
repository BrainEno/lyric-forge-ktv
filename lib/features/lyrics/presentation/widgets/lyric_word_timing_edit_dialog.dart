import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/diagnostics/best_effort.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_timing_shift_service.dart';
import '../../domain/services/lyric_word_timing_editor.dart';
import 'lyric_batch_text_edit.dart';
import 'lyric_tap_controls.dart';
import 'lyric_tap_sync_dialog.dart';

/// User-facing text of word timing fine-tuning.
class LyricWordTimingEditStrings {
  const LyricWordTimingEditStrings._();

  static const String actionTitle = '逐字微调';
  static const String intro =
      '选中一个字，调整它的开始和结束；相邻两个字首尾相接时一起移动，不会留下空隙或重叠。'
      '可以试听这个字，或把开始、结束设为当前播放位置。'
      '歌词文字不会改变；结果可撤销，保存后才写盘。';
  static const String estimated = '这一行还没有逐字时间，先按字数估算；调整后会保存为这一行的逐字时间。';
  static const String keys =
      '←/→ 选字 · A/D 开始 · J/L 结束 · Q/E 整体移动（按住 Shift 每次 50 毫秒，否则 10 毫秒）'
      ' · [ / ] 设为播放位置 · 空格 试听 · 退格 撤销';

  static String applied(int line) => '已微调第 $line 行的逐字时间（未写入磁盘）';

  static String clock(Duration value) => formatLyricTimeInput(value);

  static String seconds(Duration value) =>
      '${(value.inMilliseconds / 1000).toStringAsFixed(2)} 秒';
}

/// Shows word timing fine-tuning for row [index]. Returns the confirmed
/// edit, or null. Without a [transport] the playback actions are hidden.
Future<LyricBatchTextEdit?> showLyricWordTimingEditDialog(
  BuildContext context, {
  required LyricDocument document,
  required int index,
  LyricTapSyncTransport? transport,
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricWordTimingEditDialog(
      document: document,
      index: index,
      transport: transport,
    ),
  );
}

class LyricWordTimingEditDialog extends StatefulWidget {
  const LyricWordTimingEditDialog({
    super.key,
    required this.document,
    required this.index,
    this.transport,
    this.now,
    this.editor = const LyricWordTimingEditor(),
  });

  final LyricDocument document;
  final int index;
  final LyricTapSyncTransport? transport;

  /// Monotonic time source for position extrapolation; tests pass a fake.
  final Duration Function()? now;
  final LyricWordTimingEditor editor;

  /// Nudge steps.
  static const Duration fineStep = Duration(milliseconds: 10);
  static const Duration coarseStep = Duration(milliseconds: 50);

  /// How much is played around a word when auditioning it.
  static const Duration playBefore = Duration(milliseconds: 300);
  static const Duration playAfter = Duration(milliseconds: 200);

  /// An audition is stopped only when playback is at most this far past it.
  static const Duration stopWindow = Duration(seconds: 2);

  @override
  State<LyricWordTimingEditDialog> createState() =>
      _LyricWordTimingEditDialogState();
}

class _LyricWordTimingEditDialogState extends State<LyricWordTimingEditDialog> {
  late final LyricLine _line = widget.document.lines[widget.index];
  late final ({List<LyricWordTiming> words, bool estimated}) _initial = widget
      .editor
      .start(_line);
  late List<LyricWordTiming> _words = _initial.words;
  final List<List<LyricWordTiming>> _history = [];
  final FocusNode _focus = FocusNode(debugLabel: 'LyricWordTimingEdit');
  int _selected = 0;
  bool _fitRow = false;
  LyricTapClock? _clock;
  StreamSubscription<PlaybackState>? _subscription;
  Duration? _stopAt;

  /// The last word may not run into the next row.
  late final Duration? _ceiling = () {
    final next = widget.index + 1;
    if (next >= widget.document.lines.length) return null;
    final start = widget.document.lines[next].startTime;
    return start > _line.startTime ? start : null;
  }();

  LyricWordTimingEditor get _editor => widget.editor;

  @override
  void initState() {
    super.initState();
    final transport = widget.transport;
    if (transport == null) return;
    _clock = LyricTapClock(
      initial: transport.currentState(),
      offset: widget.document.globalOffset ?? Duration.zero,
      now: widget.now,
    );
    _subscription = transport.states.listen(_onState);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    final transport = widget.transport;
    if (transport != null && (_clock?.state.isPlaying ?? false)) {
      unawaited(_pause(transport, '关闭时暂停试听'));
    }
    _focus.dispose();
    super.dispose();
  }

  void _onState(PlaybackState state) {
    if (!mounted) return;
    final clock = _clock!;
    setState(() => clock.report(state));
    // The audition stops once playback passes the word. A position far
    // beyond it means the user played elsewhere; the stop is dropped then.
    final stopAt = _stopAt;
    if (stopAt == null || !state.isPlaying) return;
    final position = clock.toTimeline(state.position);
    if (position < stopAt) return;
    _stopAt = null;
    if (position - stopAt <= LyricWordTimingEditDialog.stopWindow) {
      unawaited(_pause(widget.transport!, '试听到词尾后暂停'));
    }
  }

  /// A pause that fails leaves the song playing, which the user hears and
  /// can stop; it must not break the word editor.
  static Future<void> _pause(LyricTapSyncTransport transport, String why) =>
      bestEffort(
        'lyrics.word',
        why,
        transport.pause,
        impact: BestEffortImpact.degraded,
      );

  void _edit(List<LyricWordTiming> next, {int? select}) {
    if (identical(next, _words) ||
        LyricWordTimingEditor.sameWords(next, _words)) {
      return;
    }
    setState(() {
      _history.add(_words);
      _words = next;
      if (select != null) _selected = select;
      if (_selected >= _words.length) _selected = _words.length - 1;
    });
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      _words = _history.removeLast();
      if (_selected >= _words.length) _selected = _words.length - 1;
    });
  }

  void _select(int index) {
    if (index < 0 || index >= _words.length) return;
    setState(() => _selected = index);
  }

  void _nudgeStart(Duration delta) => _edit(
    _editor.moveStart(_words, _selected, _words[_selected].start + delta),
  );

  void _nudgeEnd(Duration delta) => _edit(
    _editor.moveEnd(
      _words,
      _selected,
      _words[_selected].end + delta,
      ceiling: _ceiling,
    ),
  );

  void _shift(Duration delta) =>
      _edit(_editor.shift(_words, _selected, delta, ceiling: _ceiling));

  void _startAtPlayhead() {
    final clock = _clock;
    if (clock == null) return;
    _edit(_editor.moveStart(_words, _selected, clock.pressTime()));
  }

  void _endAtPlayhead() {
    final clock = _clock;
    if (clock == null) return;
    _edit(
      _editor.moveEnd(_words, _selected, clock.pressTime(), ceiling: _ceiling),
    );
  }

  void _merge() => _edit(_editor.mergeWithNext(_words, _selected));

  void _split() => _edit(_editor.split(_words, _selected));

  Future<void> _play() async {
    final transport = widget.transport;
    final clock = _clock;
    if (transport == null || clock == null || _words.isEmpty) return;
    if (clock.state.isPlaying) {
      _stopAt = null;
      await _pause(transport, '暂停试听');
      return;
    }
    final word = _words[_selected];
    var from = word.start - LyricWordTimingEditDialog.playBefore;
    if (from.isNegative) from = Duration.zero;
    _stopAt = word.end + LyricWordTimingEditDialog.playAfter;
    try {
      await transport.seek(clock.toAudio(from));
      await transport.play();
    } catch (_) {
      _stopAt = null;
    }
  }

  bool get _changed =>
      _fitRow ||
      (_initial.estimated && _words.isNotEmpty) ||
      !LyricWordTimingEditor.sameWords(_words, _initial.words);

  void _confirm() {
    if (!_changed || _words.isEmpty) return;
    final line = _editor.apply(_line, _words, fitRow: _fitRow);
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: _editor.replaceRow(widget.document, widget.index, line),
        label: LyricWordTimingEditStrings.actionTitle,
        message: LyricWordTimingEditStrings.applied(widget.index + 1),
        selectedLineIndex: widget.index,
      ),
    );
  }

  VoidCallback _withFocus(VoidCallback action) => () {
    action();
    _focus.requestFocus();
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_words.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final step = HardwareKeyboard.instance.isShiftPressed
        ? LyricWordTimingEditDialog.coarseStep
        : LyricWordTimingEditDialog.fineStep;
    final back = -step;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _select(_selected - 1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _select(_selected + 1);
    } else if (key == LogicalKeyboardKey.keyA) {
      _nudgeStart(back);
    } else if (key == LogicalKeyboardKey.keyD) {
      _nudgeStart(step);
    } else if (key == LogicalKeyboardKey.keyJ) {
      _nudgeEnd(back);
    } else if (key == LogicalKeyboardKey.keyL) {
      _nudgeEnd(step);
    } else if (key == LogicalKeyboardKey.keyQ) {
      _shift(back);
    } else if (key == LogicalKeyboardKey.keyE) {
      _shift(step);
    } else if (key == LogicalKeyboardKey.bracketLeft) {
      _startAtPlayhead();
    } else if (key == LogicalKeyboardKey.bracketRight) {
      _endAtPlayhead();
    } else if (key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) unawaited(_play());
    } else if (key == LogicalKeyboardKey.backspace) {
      _undo();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = _words;
    final line = _line;
    final text = line.text.trim();

    if (words.isEmpty) {
      return LyricBatchEditDialogFrame(
        title: LyricWordTimingEditStrings.actionTitle,
        confirmIcon: Icons.tune_rounded,
        confirmLabel: '没有可微调的字',
        onConfirm: null,
        children: [
          LyricBatchNote(
            text.isEmpty
                ? '第 ${widget.index + 1} 行没有文字。'
                : '第 ${widget.index + 1} 行没有可演唱的文字，或还没有有效的时间。',
          ),
        ],
      );
    }

    final word = words[_selected];
    final hasAudio = _clock != null;
    final playing = _clock?.state.isPlaying ?? false;
    final row = _editor.apply(line, words, fitRow: _fitRow);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LyricBatchEditDialogFrame(
        title: LyricWordTimingEditStrings.actionTitle,
        confirmKey: const ValueKey('word_edit_confirm'),
        confirmIcon: Icons.tune_rounded,
        confirmLabel: _changed ? '应用' : '还没有改动',
        onConfirm: _changed ? _confirm : null,
        children: [
          const LyricBatchNote(LyricWordTimingEditStrings.intro),
          if (_initial.estimated) ...[
            const SizedBox(height: AppSpacing.xs),
            const LyricBatchNote(
              LyricWordTimingEditStrings.estimated,
              key: ValueKey('word_edit_estimated'),
              warning: true,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            '第 ${widget.index + 1} 行 · '
            '${LyricWordTimingEditStrings.clock(row.startTime)} → '
            '${LyricWordTimingEditStrings.clock(row.endTime)}',
            key: const ValueKey('word_edit_row'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(text, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var index = 0; index < words.length; index++)
                ChoiceChip(
                  key: ValueKey('word_edit_chip_$index'),
                  label: Text(words[index].text),
                  selected: index == _selected,
                  onSelected: (_) => _withFocus(() => _select(index))(),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '「${word.text}」 ${LyricWordTimingEditStrings.clock(word.start)} → '
            '${LyricWordTimingEditStrings.clock(word.end)} · '
            '${LyricWordTimingEditStrings.seconds(word.end - word.start)}',
            key: const ValueKey('word_edit_selected'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _NudgeRow(
            label: '开始',
            keyPrefix: 'word_edit_start',
            onNudge: (delta) => _withFocus(() => _nudgeStart(delta))(),
            playheadKey: const ValueKey('word_edit_start_playhead'),
            onPlayhead: hasAudio ? _withFocus(_startAtPlayhead) : null,
          ),
          _NudgeRow(
            label: '结束',
            keyPrefix: 'word_edit_end',
            onNudge: (delta) => _withFocus(() => _nudgeEnd(delta))(),
            playheadKey: const ValueKey('word_edit_end_playhead'),
            onPlayhead: hasAudio ? _withFocus(_endAtPlayhead) : null,
          ),
          _NudgeRow(
            label: '整体',
            keyPrefix: 'word_edit_shift',
            onNudge: (delta) => _withFocus(() => _shift(delta))(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (hasAudio)
                OutlinedButton.icon(
                  key: const ValueKey('word_edit_play'),
                  onPressed: _withFocus(() => unawaited(_play())),
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 18,
                  ),
                  label: Text(playing ? '停止（空格）' : '试听本字（空格）'),
                ),
              OutlinedButton.icon(
                key: const ValueKey('word_edit_merge'),
                onPressed: _selected + 1 < words.length
                    ? _withFocus(_merge)
                    : null,
                icon: const Icon(Icons.merge_rounded, size: 18),
                label: const Text('与下一个合并'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('word_edit_split'),
                onPressed: _editor.wordTiming.sungCount(word.text) > 1
                    ? _withFocus(_split)
                    : null,
                icon: const Icon(Icons.call_split_rounded, size: 18),
                label: const Text('拆开'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('word_edit_undo'),
                onPressed: _history.isEmpty ? null : _withFocus(_undo),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('撤销（退格）'),
              ),
            ],
          ),
          SwitchListTile(
            key: const ValueKey('word_edit_fit'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('行时间贴合第一个字的开始和最后一个字的结束'),
            subtitle: const Text('关闭时只在字超出本行时延长行时间'),
            value: _fitRow,
            onChanged: (value) {
              setState(() => _fitRow = value);
              _focus.requestFocus();
            },
          ),
          const LyricBatchNote(LyricWordTimingEditStrings.keys),
        ],
      ),
    );
  }
}

/// One line of nudge buttons: −50, −10, +10, +50 ms and an optional
/// "set to the playhead".
class _NudgeRow extends StatelessWidget {
  const _NudgeRow({
    required this.label,
    required this.keyPrefix,
    required this.onNudge,
    this.playheadKey,
    this.onPlayhead,
  });

  final String label;
  final String keyPrefix;
  final ValueChanged<Duration> onNudge;
  final Key? playheadKey;
  final VoidCallback? onPlayhead;

  static const List<int> steps = [-50, -10, 10, 50];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 36, child: Text(label)),
          for (final step in steps)
            OutlinedButton(
              key: ValueKey('${keyPrefix}_$step'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              onPressed: () => onNudge(Duration(milliseconds: step)),
              child: Text(step > 0 ? '+$step' : '$step'),
            ),
          if (playheadKey != null && onPlayhead != null)
            TextButton(
              key: playheadKey,
              onPressed: onPlayhead,
              child: const Text('设为播放位置'),
            ),
        ],
      ),
    );
  }
}
