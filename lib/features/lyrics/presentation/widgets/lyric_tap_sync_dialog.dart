import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_tap_sync_session.dart';
import '../../domain/services/lyric_timing_shift_service.dart';
import 'lyric_batch_text_edit.dart';
import 'lyric_tap_controls.dart';

/// User-facing text of tap-to-sync.
class LyricTapSyncStrings {
  const LyricTapSyncStrings._();

  static const String actionTitle = '打轴（边听边标时间）';
  static const String actionDetail = '播放歌曲，每句开唱时按空格，逐行重打开始时间';
  static const String intro =
      '从选中的行开始，每句开唱时按一下空格（或点下面的大按钮），'
      '该行的开始时间就记在这一刻，并自动换到下一行。'
      '“按住”模式下按下开始、松开结束，间奏会留空。'
      '按错了按退格撤回，← 后退 3 秒重打。只改时间，不改文字；结果可撤销，保存后才写盘。';
  static const String keys = '空格 打点 · Enter 结束本行 · 退格 撤回 · ← 后退 3 秒 · P 播放/暂停';

  static String applied(int rows, int shifted) => shifted == 0
      ? '已为 $rows 行打轴（未写入磁盘）'
      : '已为 $rows 行打轴，后续 $shifted 行随之平移（未写入磁盘）';
}

/// The playback controls tap-to-sync needs, so the dialog can be driven by
/// the app's audio player or by a test double.
class LyricTapSyncTransport {
  const LyricTapSyncTransport({
    required this.currentState,
    required this.states,
    required this.play,
    required this.pause,
    required this.seek,
    this.setSpeed,
  });

  factory LyricTapSyncTransport.fromAudio(AudioPlayerService audio) =>
      LyricTapSyncTransport(
        currentState: () => audio.currentState,
        states: audio.stateStream,
        play: audio.play,
        pause: audio.pause,
        seek: audio.seek,
        setSpeed: audio.setSpeed,
      );

  final PlaybackState Function() currentState;
  final Stream<PlaybackState> states;
  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function(Duration position) seek;

  /// Null hides the speed choice.
  final Future<void> Function(double speed)? setSpeed;
}

/// Shows tap-to-sync starting at [startIndex]. Returns the confirmed edit,
/// or null.
Future<LyricBatchTextEdit?> showLyricTapSyncDialog(
  BuildContext context, {
  required LyricDocument document,
  required int startIndex,
  required LyricTapSyncTransport transport,
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LyricTapSyncDialog(
      document: document,
      startIndex: startIndex,
      transport: transport,
    ),
  );
}

/// Tap-to-sync (打轴): the user plays the song and presses a key as each row
/// begins.
///
/// The press time is read from the player's last reported position plus the
/// time elapsed since that report (scaled by the playback speed), because
/// players only report the position a few times per second and a stale
/// value would put every row up to a quarter of a second late. An optional
/// reaction-time compensation is subtracted on top.
class LyricTapSyncDialog extends StatefulWidget {
  const LyricTapSyncDialog({
    super.key,
    required this.document,
    required this.startIndex,
    required this.transport,
    this.now,
  });

  final LyricDocument document;
  final int startIndex;
  final LyricTapSyncTransport transport;

  /// Monotonic time source for position extrapolation; defaults to a
  /// stopwatch started with the dialog. Tests pass a fake.
  final Duration Function()? now;

  /// Lead-in when the session starts paused at its first row.
  static const Duration preRoll = Duration(seconds: 3);

  /// Seek distance of the "back" action.
  static const Duration backStep = Duration(seconds: 3);

  /// Where an undo resumes, before the row to be re-timed.
  static const Duration undoPreRoll = Duration(seconds: 2);

  /// Extrapolation never runs further than this past the last report.
  static const Duration maxExtrapolation = Duration(milliseconds: 600);

  static const List<double> speeds = [0.5, 0.75, 1.0];
  static const List<int> latenciesMs = [0, 80, 150];

  @override
  State<LyricTapSyncDialog> createState() => _LyricTapSyncDialogState();
}

class _LyricTapSyncDialogState extends State<LyricTapSyncDialog> {
  late final LyricTapSyncSession _session = LyricTapSyncSession(
    lineCount: widget.document.lines.length,
    startIndex: widget.startIndex < 0
        ? 0
        : (widget.startIndex > widget.document.lines.length
              ? widget.document.lines.length
              : widget.startIndex),
  );
  final FocusNode _focus = FocusNode(debugLabel: 'LyricTapSync');
  late final LyricTapClock _clock = LyricTapClock(
    initial: widget.transport.currentState(),
    offset: _offset,
    now: widget.now,
    maxExtrapolation: LyricTapSyncDialog.maxExtrapolation,
  );
  StreamSubscription<PlaybackState>? _subscription;
  late final double _initialSpeed;
  LyricTapSyncMode _mode = LyricTapSyncMode.tap;
  bool _shiftFollowing = false;
  int _latencyMs = 0;
  bool _pressMarked = false;
  bool _wasPlaying = false;

  Duration get _offset => widget.document.globalOffset ?? Duration.zero;

  PlaybackState get _state => _clock.state;

  @override
  void initState() {
    super.initState();
    _initialSpeed = _state.speed;
    _subscription = widget.transport.states.listen((state) {
      if (!mounted) return;
      setState(() => _clock.report(state));
    });
    if (!_state.isPlaying && !_session.isComplete) {
      final first = widget.document.lines[_session.cursor].startTime + _offset;
      final target = first - LyricTapSyncDialog.preRoll;
      unawaited(_seek(target.isNegative ? Duration.zero : target));
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    if (_state.isPlaying) unawaited(_ignoreErrors(widget.transport.pause()));
    final setSpeed = widget.transport.setSpeed;
    if (setSpeed != null && _state.speed != _initialSpeed) {
      unawaited(_ignoreErrors(setSpeed(_initialSpeed)));
    }
    _focus.dispose();
    super.dispose();
  }

  static Future<void> _ignoreErrors(Future<void> future) =>
      future.catchError((Object _) {});

  Duration _audioNow() => _clock.audioNow();

  /// The press time on the document timeline, reaction time removed.
  Duration _pressTime() => _clock.pressTime(latencyMs: _latencyMs);

  Future<void> _seek(Duration audioPosition) async {
    try {
      await widget.transport.seek(audioPosition);
    } catch (_) {
      // The player reports its own errors; tap-sync keeps its state.
    }
  }

  Future<void> _togglePlay() async {
    try {
      if (_state.isPlaying) {
        await widget.transport.pause();
      } else {
        await widget.transport.play();
      }
    } catch (_) {}
  }

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
    if (value == null) return;
    final target = value + _offset - LyricTapSyncDialog.undoPreRoll;
    unawaited(_seek(target.isNegative ? Duration.zero : target));
  }

  void _back() {
    var target = _audioNow() - LyricTapSyncDialog.backStep;
    if (target.isNegative) target = Duration.zero;
    final timeline = target - _offset;
    setState(
      () => _session.rewindTo(timeline.isNegative ? Duration.zero : timeline),
    );
    unawaited(_seek(target));
  }

  Future<void> _setSpeed(double speed) async {
    final setSpeed = widget.transport.setSpeed;
    if (setSpeed == null) return;
    try {
      await setSpeed(speed);
    } catch (_) {}
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
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.keyP,
  };

  void _confirm() {
    final result = _session.apply(
      widget.document,
      shiftFollowing: _shiftFollowing,
    );
    if (!result.changed) return;
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: result.document,
        label: LyricTapSyncStrings.actionTitle,
        message: LyricTapSyncStrings.applied(
          result.timedIndices.length,
          result.shiftedFollowingCount,
        ),
        selectedLineIndex: result.timedIndices.last,
      ),
    );
  }

  String _rowText(int index) {
    final text = widget.document.lines[index].text.trim();
    return text.isEmpty ? '（空行）' : text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session;
    final timed = session.marks.length;
    final remaining = widget.document.lines.length - session.cursor;
    final lastMark = session.isEmpty ? null : session.marks.last;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LyricBatchEditDialogFrame(
        title: LyricTapSyncStrings.actionTitle,
        confirmKey: const ValueKey('tap_sync_confirm'),
        confirmIcon: Icons.touch_app_rounded,
        confirmLabel: timed == 0 ? '还没有打点' : '应用 $timed 行',
        onConfirm: timed == 0 ? null : _confirm,
        children: [
          const LyricBatchNote(LyricTapSyncStrings.intro),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              IconButton.filledTonal(
                key: const ValueKey('tap_sync_play'),
                tooltip: _state.isPlaying ? '暂停（P）' : '播放（P）',
                onPressed: () {
                  unawaited(_togglePlay());
                  _focus.requestFocus();
                },
                icon: Icon(
                  _state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                key: const ValueKey('tap_sync_back'),
                tooltip: '后退 3 秒并撤掉之后的打点（←）',
                onPressed: () {
                  _back();
                  _focus.requestFocus();
                },
                icon: const Icon(Icons.replay_rounded),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                formatLyricTimeInput(
                  _state.position - _offset < Duration.zero
                      ? Duration.zero
                      : _state.position - _offset,
                ),
                key: const ValueKey('tap_sync_position'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                '已打 $timed 行 · 还剩 $remaining 行',
                key: const ValueKey('tap_sync_progress'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _RowPreview(
            previous: lastMark == null
                ? null
                : '第 ${lastMark.lineIndex + 1} 行 · '
                      '${formatLyricTimeInput(lastMark.start)}'
                      '${lastMark.end == null ? '' : ' → ${formatLyricTimeInput(lastMark.end!)}'}'
                      '  ${_rowText(lastMark.lineIndex)}',
            current: session.isComplete
                ? null
                : (session.cursor + 1, _rowText(session.cursor)),
            upcoming: [
              for (
                var index = session.cursor + 1;
                index < widget.document.lines.length &&
                    index <= session.cursor + 2;
                index++
              )
                _rowText(index),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LyricTapPad(
            padKey: const ValueKey('tap_sync_pad'),
            label: !_state.isPlaying
                ? '开始播放（空格）'
                : session.isComplete
                ? '全部打完，可以应用了'
                : _mode == LyricTapSyncMode.hold
                ? '按住演唱第 ${session.cursor + 1} 行（空格）'
                : '第 ${session.cursor + 1} 行开唱时按下（空格）',
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
                key: const ValueKey('tap_sync_end_row'),
                onPressed: session.openIndex == null
                    ? null
                    : () {
                        _release(explicit: true);
                        _focus.requestFocus();
                      },
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('结束本行（Enter）'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('tap_sync_undo'),
                onPressed: session.isEmpty
                    ? null
                    : () {
                        _undo();
                        _focus.requestFocus();
                      },
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('撤回（退格）'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const LyricBatchNote(LyricTapSyncStrings.keys),
          const SizedBox(height: AppSpacing.sm),
          Text('设置', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<LyricTapSyncMode>(
            key: const ValueKey('tap_sync_mode'),
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
                for (final speed in LyricTapSyncDialog.speeds)
                  ChoiceChip(
                    key: ValueKey('tap_sync_speed_$speed'),
                    label: Text('${speed}x'),
                    selected: (_state.speed - speed).abs() < 0.01,
                    onSelected: (_) => unawaited(_setSpeed(speed)),
                  ),
              ],
              const Text('反应补偿'),
              for (final latency in LyricTapSyncDialog.latenciesMs)
                ChoiceChip(
                  key: ValueKey('tap_sync_latency_$latency'),
                  label: Text(latency == 0 ? '不补偿' : '$latency ms'),
                  selected: _latencyMs == latency,
                  onSelected: (_) {
                    setState(() => _latencyMs = latency);
                    _focus.requestFocus();
                  },
                ),
            ],
          ),
          if (!session.isComplete)
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile.adaptive(
                key: const ValueKey('tap_sync_shift_following'),
                contentPadding: EdgeInsets.zero,
                value: _shiftFollowing,
                onChanged: (value) {
                  setState(() => _shiftFollowing = value);
                  _focus.requestFocus();
                },
                title: const Text('后面没打的行一起平移'),
                subtitle: const Text('按最后一行打点与原时间的差值整体移动，适合只重打前半段'),
              ),
            ),
        ],
      ),
    );
  }
}

class _RowPreview extends StatelessWidget {
  const _RowPreview({
    required this.previous,
    required this.current,
    required this.upcoming,
  });

  final String? previous;
  final (int, String)? current;
  final List<String> upcoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
    );
    final currentRow = current;
    return Container(
      key: const ValueKey('tap_sync_rows'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (previous != null)
            Text(
              previous!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          if (currentRow == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                '所有行都已打轴。',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.success,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '第 ${currentRow.$1} 行  ',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                    TextSpan(
                      text: currentRow.$2,
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                key: const ValueKey('tap_sync_current'),
              ),
            ),
          for (final text in upcoming)
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
