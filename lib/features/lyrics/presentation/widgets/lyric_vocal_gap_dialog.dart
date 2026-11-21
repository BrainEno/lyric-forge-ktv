import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/vocal_check_record.dart';
import '../../domain/services/lyric_span_rerecognition.dart';
import '../../domain/services/lyric_vocal_check_actions.dart';
import 'lyric_batch_text_edit.dart';
import 'lyric_missed_repeat_dialog.dart' show LyricSpanPreview;
import 'lyric_span_recognition_dialog.dart' show LyricSpanRecognitionStrings;

/// User-facing text of the vocal check's one-click follow-ups (D-045).
class LyricVocalCheckStrings {
  const LyricVocalCheckStrings._();

  static const String gapTitle = '识别有人声没歌词的段落';
  static const String gapDetail = '人声检查听到有人唱、却没有歌词的地方，一键识别后插入';
  static const String gapIntro =
      '人声检查在这些地方听到有人在唱，但草稿里没有歌词，多半是整首识别漏掉了。'
      '打开后会自动把这一段（前后各多 0.3 秒，不会碰到相邻的行）重新识别一次；'
      '确认后把结果作为新行插入，已有的行不受影响。'
      '如果识别不出来，可以换一个引擎再试，或者试听后标记“这里没有歌词”（例如哼唱、和声采样）。'
      '首次运行需要加载模型，可能要等几十秒。插入后可撤销，保存后才写盘。';
  static const String noGaps = '没有需要识别的段落：人声检查没有发现有人声却没有歌词的地方，或者都已经补上了。';

  static const String restoreTitle = '恢复人声检查删除的行';
  static const String restoreDetail = '把识别后因为没人唱而被删掉的行放回原来的时间';
  static const String restoreIntro =
      '识别完成后，人声检查删掉了这些行：在它们的时间里分离出的人声几乎是静音，'
      '多半是识别模型在前奏、间奏或尾奏里编出来的。'
      '如果试听后发现确实有人在唱（例如很轻的气声），勾选后恢复：行会按原来的时间放回，'
      '并当作手动确认过的行，之后的批量整理不会再改它们。恢复可撤销，保存后才写盘。';
  static const String noRemoved = '没有可恢复的行：人声检查没有删除任何行，或者都已经恢复了。';

  static const String dismissLabel = '这里没有歌词';

  static String engineLabel(LyricSpanEngine engine) => switch (engine) {
    LyricSpanEngine.qwen => 'Qwen3-ASR',
    LyricSpanEngine.whisper => 'Whisper',
  };

  static String windowFailure(LyricVocalGapWindowFailure failure) =>
      switch (failure) {
        LyricVocalGapWindowFailure.tooShort =>
          '这一段夹在两行之间，不到 0.5 秒，无法单独识别；可以试听后手动补写。',
        LyricVocalGapWindowFailure.tooLong => '这一段超过 90 秒，建议整首重新识别。',
      };

  static String span(LyricVocalCheckSpan span) =>
      '${LyricSpanRecognitionStrings.clock(span.start)}–'
      '${LyricSpanRecognitionStrings.clock(span.end)}';

  static String insertedMessage(int count, LyricVocalCheckSpan at) =>
      '已在 ${span(at)} 插入 $count 行（未写入磁盘）';

  static String dismissedMessage(LyricVocalCheckSpan at) =>
      '已标记 ${span(at)} 没有歌词，不再提示（未写入磁盘）';

  static String restoredMessage(int count, {int overlapping = 0}) =>
      '已恢复 $count 行被人声检查删除的歌词'
      '${overlapping > 0 ? '，其中 $overlapping 行和已有的行时间重叠，请检查' : ''}'
      '（未写入磁盘）';
}

/// Shows the gap recogniser, starting at [initialSpan] (or the first open
/// stretch). Returns the confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricVocalGapDialog(
  BuildContext context, {
  required LyricDocument document,
  required List<LyricVocalCheckSpan> spans,
  required String projectId,
  required LyricSpanRecognizer recognizer,
  LyricVocalCheckSpan? initialSpan,
  Duration? audioDuration,
  LyricSpanPreview? onPreviewSpan,
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LyricVocalGapDialog(
      document: document,
      spans: spans,
      projectId: projectId,
      recognizer: recognizer,
      initialSpan: initialSpan,
      audioDuration: audioDuration,
      onPreviewSpan: onPreviewSpan,
    ),
  );
}

/// Recognises one stretch of singing that has no row and inserts the
/// result (D-045). Recognition starts as soon as the dialog opens and again
/// whenever the user moves to another stretch or engine.
class LyricVocalGapDialog extends StatefulWidget {
  const LyricVocalGapDialog({
    super.key,
    required this.document,
    required this.spans,
    required this.projectId,
    required this.recognizer,
    this.initialSpan,
    this.audioDuration,
    this.onPreviewSpan,
    this.actions = const LyricVocalCheckActions(),
  });

  final LyricDocument document;

  /// The stretches still without lyrics, in timeline order; not empty.
  final List<LyricVocalCheckSpan> spans;
  final String projectId;
  final LyricSpanRecognizer recognizer;
  final LyricVocalCheckSpan? initialSpan;
  final Duration? audioDuration;
  final LyricSpanPreview? onPreviewSpan;
  final LyricVocalCheckActions actions;

  @override
  State<LyricVocalGapDialog> createState() => _LyricVocalGapDialogState();
}

class _LyricVocalGapDialogState extends State<LyricVocalGapDialog> {
  late int _position;
  LyricSpanEngine _engine = LyricSpanEngine.qwen;

  bool _running = false;
  int _runToken = 0;
  String? _error;
  LyricVocalGapInsertion? _insertion;
  String? _engineLabel;

  Duration get _offset => widget.document.globalOffset ?? Duration.zero;
  LyricVocalCheckSpan get _span => widget.spans[_position];

  LyricVocalGapWindowResult get _window => widget.actions.window(
    widget.document,
    _span,
    audioDuration: widget.audioDuration,
  );

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSpan;
    final found = initial == null ? -1 : widget.spans.indexOf(initial);
    _position = found < 0 ? 0 : found;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  @override
  void dispose() {
    // Closing the dialog abandons a running request.
    if (_running) unawaited(widget.recognizer.cancel());
    super.dispose();
  }

  /// Moves to another stretch or engine and recognises it right away.
  void _switchTo({int? position, LyricSpanEngine? engine}) {
    final wasRunning = _running;
    setState(() {
      _position = position ?? _position;
      _engine = engine ?? _engine;
      _runToken++;
      _running = false;
      _error = null;
      _insertion = null;
      _engineLabel = null;
    });
    if (wasRunning) unawaited(widget.recognizer.cancel());
    unawaited(_run());
  }

  Future<void> _run() async {
    final windowResult = _window;
    final window = windowResult.window;
    if (window == null || !windowResult.isUsable) return;
    final audio = window.onAudio(_offset);
    final token = ++_runToken;
    setState(() {
      _running = true;
      _error = null;
      _insertion = null;
    });
    try {
      final result = await widget.recognizer.recognize(
        projectId: widget.projectId,
        start: audio.start,
        end: audio.end,
        engine: _engine,
      );
      if (!mounted || token != _runToken) return;
      final insertion = widget.actions.insertion(
        window,
        recognized: [for (final line in result.lines) _toDocument(line)],
      );
      setState(() {
        _insertion = insertion;
        _engineLabel = result.engineLabel;
        if (insertion.isEmpty) {
          _error = '这一段没有识别出歌词。可以换一个引擎再试，或者试听后标记“这里没有歌词”。';
        }
      });
    } on LyricSpanRecognitionException catch (error) {
      if (!mounted || token != _runToken) return;
      setState(() => _error = error.cancelled ? '已停止。' : error.message);
    } finally {
      if (mounted && token == _runToken) setState(() => _running = false);
    }
  }

  Future<void> _stop() async {
    _runToken++;
    setState(() {
      _running = false;
      _error = '已停止。';
    });
    await widget.recognizer.cancel();
  }

  LyricLine _toDocument(LyricLine line) => line.copyWith(
    startTime: line.startTime - _offset,
    endTime: line.endTime - _offset,
    words: [
      for (final word in line.words)
        LyricWordTiming(
          text: word.text,
          start: word.start - _offset,
          end: word.end - _offset,
        ),
    ],
  );

  void _confirm() {
    final insertion = _insertion;
    if (insertion == null || insertion.isEmpty) return;
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: insertion.applyTo(widget.document),
        label: LyricVocalCheckStrings.gapTitle,
        message: LyricVocalCheckStrings.insertedMessage(
          insertion.newLines.length,
          _span,
        ),
        selectedLineIndex: insertion.window.insertAt,
      ),
    );
  }

  void _dismiss() {
    final document = widget.actions.dismiss(widget.document, _span);
    if (identical(document, widget.document)) return;
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: document,
        label: '标记没有歌词',
        message: LyricVocalCheckStrings.dismissedMessage(_span),
        selectedLineIndex: null,
      ),
    );
  }

  int get _anchorRow {
    final last = widget.document.lines.length - 1;
    final at = _window.window?.insertAt ?? 0;
    if (last < 0) return 0;
    return at > last ? last : at;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final windowResult = _window;
    final window = windowResult.window;
    final failure = windowResult.failure;
    final insertion = _insertion;
    final count = widget.spans.length;

    return LyricBatchEditDialogFrame(
      title: LyricVocalCheckStrings.gapTitle,
      confirmKey: const ValueKey('vocal_gap_confirm'),
      confirmIcon: Icons.playlist_add_rounded,
      confirmLabel: _running
          ? '正在识别…'
          : insertion != null && !insertion.isEmpty
          ? '插入 ${insertion.newLines.length} 行'
          : '没有可插入的歌词',
      onConfirm: !_running && insertion != null && !insertion.isEmpty
          ? _confirm
          : null,
      children: [
        const LyricBatchNote(LyricVocalCheckStrings.gapIntro),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            IconButton(
              key: const ValueKey('vocal_gap_previous'),
              tooltip: '上一处',
              onPressed: _position > 0
                  ? () => _switchTo(position: _position - 1)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '第 ${_position + 1} / $count 处 · '
                '${LyricVocalCheckStrings.span(_span)}',
                key: const ValueKey('vocal_gap_position'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton(
              key: const ValueKey('vocal_gap_next'),
              tooltip: '下一处',
              onPressed: _position < count - 1
                  ? () => _switchTo(position: _position + 1)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        if (window != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  '识别范围 ${LyricSpanRecognitionStrings.clock(window.start)}–'
                  '${LyricSpanRecognitionStrings.clock(window.end)}'
                  '（${LyricSpanRecognitionStrings.seconds(window.length)} 秒），'
                  '插入在第 ${window.insertAt + 1} 行之前',
                  key: const ValueKey('vocal_gap_window'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (widget.onPreviewSpan != null &&
                  widget.document.lines.isNotEmpty)
                IconButton(
                  key: const ValueKey('vocal_gap_preview'),
                  tooltip: '试听这一段',
                  onPressed: () => widget.onPreviewSpan!(
                    _anchorRow,
                    window.start,
                    window.end,
                  ),
                  icon: const Icon(Icons.hearing_rounded),
                ),
            ],
          ),
        if (failure != null)
          LyricBatchNote(
            LyricVocalCheckStrings.windowFailure(failure),
            warning: true,
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final engine in LyricSpanEngine.values)
              ChoiceChip(
                key: ValueKey('vocal_gap_engine_${engine.name}'),
                label: Text(LyricVocalCheckStrings.engineLabel(engine)),
                selected: _engine == engine,
                onSelected: failure != null || _engine == engine
                    ? null
                    : (_) => _switchTo(engine: engine),
              ),
            if (_running) ...[
              const AppInlineLoading(message: '正在识别…'),
              TextButton(
                key: const ValueKey('vocal_gap_stop'),
                onPressed: _stop,
                child: const Text('停止'),
              ),
            ] else if (failure == null)
              TextButton.icon(
                key: const ValueKey('vocal_gap_rerun'),
                onPressed: _run,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('再识别一次'),
              ),
          ],
        ),
        if (_error case final error?) ...[
          const SizedBox(height: AppSpacing.xs),
          LyricBatchNote(
            error,
            warning: true,
            key: const ValueKey('vocal_gap_error'),
          ),
        ],
        const Divider(height: AppSpacing.lg),
        if (insertion != null && !insertion.isEmpty) ...[
          Text(
            '${_engineLabel ?? LyricVocalCheckStrings.engineLabel(_engine)}'
            ' 识别出 ${insertion.newLines.length} 行',
            key: const ValueKey('vocal_gap_result'),
            style: theme.textTheme.titleSmall,
          ),
          if (insertion.clippedCount > 0)
            LyricBatchNote('有 ${insertion.clippedCount} 段识别结果落在范围边缘、太短，已舍弃。'),
          for (final line in insertion.newLines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
              child: Text(
                '${LyricSpanRecognitionStrings.clock(line.startTime)}–'
                '${LyricSpanRecognitionStrings.clock(line.endTime)}  '
                '${line.text}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('vocal_gap_dismiss'),
            onPressed: _running ? null : _dismiss,
            icon: const Icon(Icons.music_off_rounded, size: 18),
            label: const Text(LyricVocalCheckStrings.dismissLabel),
          ),
        ),
      ],
    );
  }
}
