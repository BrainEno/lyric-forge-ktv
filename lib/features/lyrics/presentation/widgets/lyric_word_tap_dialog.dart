import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_tap_sync_session.dart';
import '../../domain/services/lyric_timing_shift_service.dart';
import '../../domain/services/lyric_word_tap_session.dart';
import 'lyric_batch_text_edit.dart';
import 'lyric_tap_controls.dart';
import 'lyric_tap_sync_dialog.dart';

/// User-facing text of word-by-word tap-to-sync.
class LyricWordTapStrings {
  const LyricWordTapStrings._();

  static const String actionTitle = '逐字打轴（卡拉 OK）';
  static const String actionDetail = '每个字开唱时按一下空格，得到真实逐字时间，用于逐字 LRC 和 ASS 导出';
  static const String intro =
      '从选中的行开始，每唱到一个字（英文按单词）就按一下空格（或点下面的大按钮），'
      '一行的字按完后自动进入下一行。'
      '“按住”模式下按下开始、松开结束，换气和拖腔都能准确记录。'
      '按错了按退格撤回，R 重打本行，← 后退 3 秒。'
      '只有整行按完的行才会更新；只改时间，不改文字。结果可撤销，保存后才写盘。';
  static const String keys =
      '空格 打点 · Enter 结束本字 · 退格 撤回 · R 重打本行 · ← 后退 3 秒 · P 播放/暂停';

  static String applied(int rows) => '已为 $rows 行逐字打轴（未写入磁盘）';

  static String partial(int line) => '第 $line 行没有按完，保持原样。';
}

/// Shows word-by-word tap-to-sync starting at [startIndex]. Returns the
/// confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricWordTapDialog(
  BuildContext context, {
  required LyricDocument document,
  required int startIndex,
  required LyricTapSyncTransport transport,
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LyricWordTapDialog(
      document: document,
      startIndex: startIndex,
      transport: transport,
    ),
  );
}

/// Word-by-word tap-to-sync (逐字打轴): the user plays the song and presses a
/// key as each character (or Latin word) is sung.
class LyricWordTapDialog extends StatefulWidget {
  const LyricWordTapDialog({
    super.key,
    required this.document,
    required this.startIndex,
    required this.transport,
    this.now,
  });

  final LyricDocument document;
  final int startIndex;
  final LyricTapSyncTransport transport;

  /// Monotonic time source for position extrapolation; tests pass a fake.
  final Duration Function()? now;

  /// Lead-in before the row being timed when (re)starting.
  static const Duration preRoll = Duration(seconds: 2);

  /// Seek distance of the "back" action.
  static const Duration backStep = Duration(seconds: 3);

  static const List<double> speeds = [0.5, 0.75, 1.0];
  static const List<int> latenciesMs = [0, 80, 150];

  @override
  State<LyricWordTapDialog> createState() => _LyricWordTapDialogState();
}

class _LyricWordTapDialogState extends State<LyricWordTapDialog>
    with LyricTapTransportFeedback<LyricWordTapDialog> {
  late final LyricWordTapSession _session = LyricWordTapSession(
    lines: widget.document.lines,
    startIndex: widget.startIndex,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'LyricWordTap');
  late final LyricTapClock _clock = LyricTapClock(
    initial: widget.transport.currentState(),
    offset: widget.document.globalOffset ?? Duration.zero,
    now: widget.now,
  );
  StreamSubscription<PlaybackState>? _subscription;
  late final double _initialSpeed;
  LyricTapSyncMode _mode = LyricTapSyncMode.tap;
  int _latencyMs = 0;
  bool _pressMarked = false;
  bool _wasPlaying = false;

  PlaybackState get _state => _clock.state;

  @override
  void initState() {
    super.initState();
    _initialSpeed = _state.speed;
    _subscription = widget.transport.states.listen((state) {
      if (!mounted) return;
      setState(() => _clock.report(state));
    });
    if (!_state.isPlaying && _session.rows.isNotEmpty) {
      final line = widget.document.lines[_session.rows.first.lineIndex];
      unawaited(_seekBefore(line.startTime));
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    if (_state.isPlaying) restoreTransport('暂停', widget.transport.pause);
    final setSpeed = widget.transport.setSpeed;
    if (setSpeed != null && _state.speed != _initialSpeed) {
      restoreTransport('恢复播放速度', () => setSpeed(_initialSpeed));
    }
    _focus.dispose();
    super.dispose();
  }

  Duration _pressTime() => _clock.pressTime(latencyMs: _latencyMs);

  Future<void> _seek(Duration audioPosition) =>
      runTransport('跳转', () => widget.transport.seek(audioPosition));

  Future<void> _seekBefore(Duration timeline) =>
      _seek(_clock.toAudio(timeline - LyricWordTapDialog.preRoll));

  Future<void> _togglePlay() => _state.isPlaying
      ? runTransport('暂停', widget.transport.pause)
      : runTransport('播放', widget.transport.play);

  void _press() {
    _pressMarked = false;
    if (!_state.isPlaying) {
      unawaited(_togglePlay());
      return;
    }
    setState(() => _pressMarked = _session.press(_pressTime()));
  }

  void _release({bool explicit = false}) {
    if (!explicit && (_mode != LyricTapSyncMode.hold || !_pressMarked)) return;
    _pressMarked = false;
    setState(() => _session.release(_pressTime()));
  }

  void _undo() {
    Duration? start;
    setState(() => start = _session.undo());
    final value = start;
    if (value != null) unawaited(_seekBefore(value));
  }

  /// Drops the presses of the row being timed (or of the last row, when
  /// the cursor is at the start of a row) and seeks back before it.
  void _redoRow() {
    if (_session.isEmpty) return;
    var row = _session.cursorRow;
    if (_session.timedUnitsIn(row) == 0 && row > 0) row--;
    final start = _session.rowStart(row);
    if (start == null) return;
    setState(() => _session.rewindTo(start));
    unawaited(_seekBefore(start));
  }

  void _back() {
    var target = _clock.audioNow() - LyricWordTapDialog.backStep;
    if (target.isNegative) target = Duration.zero;
    setState(() => _session.rewindTo(_clock.toTimeline(target)));
    unawaited(_seek(target));
  }

  Future<void> _setSpeed(double speed) async {
    final setSpeed = widget.transport.setSpeed;
    if (setSpeed == null) return;
    await runTransport('切换播放速度', () => setSpeed(speed));
    if (mounted) _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        _wasPlaying = _state.isPlaying;
        _press();
      } else if (event is KeyUpEvent && _wasPlaying) {
        _release();
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) {
      return _handledKeys.contains(key)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _release(explicit: true);
    } else if (key == LogicalKeyboardKey.backspace) {
      _undo();
    } else if (key == LogicalKeyboardKey.keyR) {
      _redoRow();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _back();
    } else if (key == LogicalKeyboardKey.keyP) {
      unawaited(_togglePlay());
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static final Set<LogicalKeyboardKey> _handledKeys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.backspace,
    LogicalKeyboardKey.keyR,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.keyP,
  };

  void _confirm() {
    final result = _session.apply(widget.document);
    if (!result.changed) return;
    final partial = result.partialIndex;
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: result.document,
        label: LyricWordTapStrings.actionTitle,
        message: [
          LyricWordTapStrings.applied(result.timedIndices.length),
          if (partial != null) LyricWordTapStrings.partial(partial + 1),
        ].join(' '),
        selectedLineIndex: result.timedIndices.last,
      ),
    );
  }

  /// One action wired to a button, keeping keyboard focus on the dialog.
  VoidCallback _withFocus(VoidCallback action) => () {
    action();
    _focus.requestFocus();
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session;
    final rows = session.rows;
    final completed = session.completedRowCount;
    final position = _clock.toTimeline(_state.position);

    if (rows.isEmpty) {
      return LyricBatchEditDialogFrame(
        title: LyricWordTapStrings.actionTitle,
        confirmIcon: Icons.touch_app_rounded,
        confirmLabel: '没有可打轴的行',
        onConfirm: null,
        children: const [LyricBatchNote('从选中行往后没有可演唱的文字。')],
      );
    }

    final cursorRow = session.cursorRow;
    final current = rows[cursorRow];
    final timedHere = session.timedUnitsIn(cursorRow);
    final cursorUnit = session.cursorUnit;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LyricBatchEditDialogFrame(
        title: LyricWordTapStrings.actionTitle,
        confirmKey: const ValueKey('word_tap_confirm'),
        confirmIcon: Icons.touch_app_rounded,
        confirmLabel: completed == 0 ? '还没有按完一行' : '应用 $completed 行',
        onConfirm: completed == 0 ? null : _confirm,
        children: [
          const LyricBatchNote(LyricWordTapStrings.intro),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              IconButton.filledTonal(
                key: const ValueKey('word_tap_play'),
                tooltip: _state.isPlaying ? '暂停（P）' : '播放（P）',
                onPressed: _withFocus(() => unawaited(_togglePlay())),
                icon: Icon(
                  _state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                key: const ValueKey('word_tap_back'),
                tooltip: '后退 3 秒并撤掉之后的打点（←）',
                onPressed: _withFocus(_back),
                icon: const Icon(Icons.replay_rounded),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                formatLyricTimeInput(position),
                key: const ValueKey('word_tap_position'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                '已完成 $completed 行 · 共 ${rows.length} 行',
                key: const ValueKey('word_tap_progress'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          LyricTapTransportError(message: transportError),
          const SizedBox(height: AppSpacing.sm),
          Container(
            key: const ValueKey('word_tap_rows'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.bgBase,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cursorRow > 0 || session.isComplete)
                  Text(
                    _rowLabel(
                      session.isComplete ? cursorRow : cursorRow - 1,
                      done: true,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                if (session.isComplete)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      '所有行都已逐字打轴。',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: LyricWordTapUnits(
                      key: const ValueKey('word_tap_current'),
                      lineNumber: current.lineIndex + 1,
                      units: current.units,
                      timed: timedHere,
                      cursor: cursorUnit,
                    ),
                  ),
                for (
                  var next = cursorRow + 1;
                  next < rows.length && next <= cursorRow + 2;
                  next++
                )
                  Text(
                    rows[next].units.join(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LyricTapPad(
            padKey: const ValueKey('word_tap_pad'),
            label: !_state.isPlaying
                ? '开始播放（空格）'
                : session.isComplete
                ? '全部打完，可以应用了'
                : '唱到「${current.units[cursorUnit!].trim()}」时按下（空格）',
            enabled: !_state.isPlaying || !session.isComplete,
            onDown: () {
              _wasPlaying = _state.isPlaying;
              _press();
            },
            onUp: () {
              if (_wasPlaying) _release();
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('word_tap_end_unit'),
                onPressed: session.hasOpenUnit
                    ? _withFocus(() => _release(explicit: true))
                    : null,
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('结束本字（Enter）'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('word_tap_undo'),
                onPressed: session.isEmpty ? null : _withFocus(_undo),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('撤回（退格）'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('word_tap_redo_row'),
                onPressed: session.isEmpty ? null : _withFocus(_redoRow),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('重打本行（R）'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const LyricBatchNote(LyricWordTapStrings.keys),
          const SizedBox(height: AppSpacing.sm),
          Text('设置', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<LyricTapSyncMode>(
            key: const ValueKey('word_tap_mode'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: LyricTapSyncMode.tap,
                label: Text('轻点：只标开始'),
              ),
              ButtonSegment(
                value: LyricTapSyncMode.hold,
                label: Text('按住：按下开始、松开结束'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (value) {
              setState(() => _mode = value.first);
              _focus.requestFocus();
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.transport.setSpeed != null) ...[
                const Text('播放速度'),
                for (final speed in LyricWordTapDialog.speeds)
                  ChoiceChip(
                    key: ValueKey('word_tap_speed_$speed'),
                    label: Text('${speed}x'),
                    selected: (_state.speed - speed).abs() < 0.01,
                    onSelected: (_) => unawaited(_setSpeed(speed)),
                  ),
              ],
              const Text('反应补偿'),
              for (final latency in LyricWordTapDialog.latenciesMs)
                ChoiceChip(
                  key: ValueKey('word_tap_latency_$latency'),
                  label: Text(latency == 0 ? '不补偿' : '$latency ms'),
                  selected: _latencyMs == latency,
                  onSelected: (_) {
                    setState(() => _latencyMs = latency);
                    _focus.requestFocus();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _rowLabel(int rowPosition, {required bool done}) {
    final row = _session.rows[rowPosition];
    final start = _session.rowStart(rowPosition);
    return [
      '第 ${row.lineIndex + 1} 行',
      if (done && start != null) formatLyricTimeInput(start),
      row.units.join().trim(),
    ].join(' · ');
  }
}

/// The row being timed, unit by unit: timed units in the accent colour,
/// the next one underlined, the rest plain.
class LyricWordTapUnits extends StatelessWidget {
  const LyricWordTapUnits({
    super.key,
    required this.lineNumber,
    required this.units,
    required this.timed,
    required this.cursor,
  });

  final int lineNumber;
  final List<String> units;
  final int timed;
  final int? cursor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.titleLarge;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '第 $lineNumber 行  ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.accent,
            ),
          ),
          for (var index = 0; index < units.length; index++)
            TextSpan(
              text: units[index],
              style: index < timed
                  ? base?.copyWith(color: AppColors.accent)
                  : index == cursor
                  ? base?.copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.accent,
                      decorationThickness: 2,
                      fontWeight: FontWeight.w800,
                    )
                  : base?.copyWith(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
