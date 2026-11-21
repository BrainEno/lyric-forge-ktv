import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/vocal_check_record.dart';
import '../../domain/services/lyric_span_rerecognition.dart';
import '../../domain/services/lyric_vocal_check_actions.dart';
import '../../domain/services/lyric_vocal_gap_batch.dart';
import 'lyric_batch_text_edit.dart';
import 'lyric_missed_repeat_dialog.dart' show LyricSpanPreview;
import 'lyric_span_recognition_dialog.dart' show LyricSpanRecognitionStrings;
import 'lyric_vocal_gap_dialog.dart' show LyricVocalCheckStrings;

/// User-facing text of the batch gap recogniser (D-046).
class LyricVocalGapBatchStrings {
  const LyricVocalGapBatchStrings._();

  static const String title = '全部识别有人声没歌词的段落';
  static const String intro =
      '依次识别人声检查找到的每一处有人声却没有歌词的地方（前后各多 0.3 秒，不会碰到相邻的行），'
      '全部识别完后一次确认插入；已有的行不受影响。可以取消勾选不想要的段落。'
      '首次运行需要加载模型，可能要等几十秒。插入后可撤销，保存后才写盘。';
  static const String fallbackLabel = '识别不出时换另一个引擎再试一次';
  static const String stopped = '已停止，剩下的段落没有识别。';
  static const String nothingFound = '这一段没有识别出歌词';

  static String dismissEmptyLabel(int count) => '把没有识别出歌词的 $count 处标记为“这里没有歌词”';

  static String progress(int current, int total) => '正在识别第 $current / $total 处…';

  static String summary({
    required int found,
    required int empty,
    required int failed,
    required int skipped,
    required int waiting,
  }) => [
    '$found 处识别出歌词',
    if (empty > 0) '$empty 处没有识别出',
    if (failed > 0) '$failed 处识别失败',
    if (skipped > 0) '$skipped 处无法单独识别',
    if (waiting > 0) '$waiting 处还没有识别',
  ].join('，');

  static String confirmLabel({required int rows, required int gaps, required int dismissed}) {
    if (rows == 0 && dismissed == 0) return '没有可插入的歌词';
    return [
      if (rows > 0) '插入 $rows 行（$gaps 处）',
      if (dismissed > 0) '标记 $dismissed 处没有歌词',
    ].join('，');
  }

  static String message(LyricVocalGapBatchResult result) {
    final parts = [
      if (result.insertedCount > 0)
        '已在 ${result.filledGaps} 处插入 ${result.insertedCount} 行',
      if (result.dismissedGaps > 0) '已标记 ${result.dismissedGaps} 处没有歌词',
    ];
    return '${parts.join('，')}（未写入磁盘）';
  }

  static String fallbackNote(String engineLabel) => '第一个引擎没有识别出，由 $engineLabel 识别';

  static String rerunLabel(int count) => '再识别没有结果的 $count 处';
}

/// Where one stretch of the batch stands.
enum LyricVocalGapBatchStatus {
  /// Too short or too long to send on its own.
  skipped,
  waiting,
  running,
  found,
  empty,
  failed,

  /// The user stopped the run while this stretch was being recognised.
  stopped,
}

/// Shows the batch recogniser for [spans]. Returns the confirmed edit, or
/// null.
Future<LyricBatchTextEdit?> showLyricVocalGapBatchDialog(
  BuildContext context, {
  required LyricDocument document,
  required List<LyricVocalCheckSpan> spans,
  required String projectId,
  required LyricSpanRecognizer recognizer,
  Duration? audioDuration,
  LyricSpanPreview? onPreviewSpan,
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LyricVocalGapBatchDialog(
      document: document,
      spans: spans,
      projectId: projectId,
      recognizer: recognizer,
      audioDuration: audioDuration,
      onPreviewSpan: onPreviewSpan,
    ),
  );
}

class _GapState {
  _GapState(this.item)
    : status = item.isSendable
          ? LyricVocalGapBatchStatus.waiting
          : LyricVocalGapBatchStatus.skipped;

  final LyricVocalGapBatchItem item;
  LyricVocalGapBatchStatus status;
  LyricVocalGapInsertion? insertion;
  String? engineLabel;
  String? error;
  bool fellBack = false;
  bool selected = false;

  int get rowCount => insertion?.newLines.length ?? 0;

  bool get canRunAgain =>
      status == LyricVocalGapBatchStatus.empty ||
      status == LyricVocalGapBatchStatus.failed ||
      status == LyricVocalGapBatchStatus.stopped ||
      status == LyricVocalGapBatchStatus.waiting;

  void reset() {
    status = LyricVocalGapBatchStatus.waiting;
    insertion = null;
    engineLabel = null;
    error = null;
    fellBack = false;
    selected = false;
  }
}

/// What one recognition attempt produced.
class _Attempt {
  const _Attempt({this.insertion, this.engineLabel, this.error});

  final LyricVocalGapInsertion? insertion;
  final String? engineLabel;
  final LyricSpanRecognitionException? error;

  bool get found {
    final insertion = this.insertion;
    return insertion != null && !insertion.isEmpty;
  }
}

/// Recognises every open stretch one after another as soon as it opens,
/// then inserts the chosen results in one edit (D-046). A stretch the first
/// engine hears nothing in is tried once with the other engine.
class LyricVocalGapBatchDialog extends StatefulWidget {
  const LyricVocalGapBatchDialog({
    super.key,
    required this.document,
    required this.spans,
    required this.projectId,
    required this.recognizer,
    this.audioDuration,
    this.onPreviewSpan,
    this.batch = const LyricVocalGapBatch(),
  });

  final LyricDocument document;
  final List<LyricVocalCheckSpan> spans;
  final String projectId;
  final LyricSpanRecognizer recognizer;
  final Duration? audioDuration;
  final LyricSpanPreview? onPreviewSpan;
  final LyricVocalGapBatch batch;

  @override
  State<LyricVocalGapBatchDialog> createState() =>
      _LyricVocalGapBatchDialogState();
}

class _LyricVocalGapBatchDialogState extends State<LyricVocalGapBatchDialog> {
  late final List<_GapState> _gaps;
  LyricSpanEngine _engine = LyricSpanEngine.qwen;
  bool _fallback = true;
  bool _dismissEmpty = false;
  bool _running = false;
  int _runToken = 0;
  int? _current;
  int _queueTotal = 0;
  String? _notice;

  Duration get _offset => widget.document.globalOffset ?? Duration.zero;

  @override
  void initState() {
    super.initState();
    final plan = widget.batch.plan(
      widget.document,
      widget.spans,
      audioDuration: widget.audioDuration,
    );
    _gaps = [for (final item in plan.items) _GapState(item)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_runQueue());
    });
  }

  @override
  void dispose() {
    // Closing the dialog abandons the running request.
    if (_running) unawaited(widget.recognizer.cancel());
    super.dispose();
  }

  Future<void> _runQueue() async {
    final queue = [
      for (final (index, gap) in _gaps.indexed)
        if (gap.item.isSendable && gap.canRunAgain) index,
    ];
    if (queue.isEmpty) return;
    final token = ++_runToken;
    setState(() {
      _running = true;
      _queueTotal = queue.length;
      _notice = null;
      for (final index in queue) {
        _gaps[index].reset();
      }
    });
    try {
      for (final (position, index) in queue.indexed) {
        final gap = _gaps[index];
        setState(() {
          _current = position + 1;
          gap.status = LyricVocalGapBatchStatus.running;
        });
        var attempt = await _attempt(gap.item.window!, _engine);
        if (!mounted || token != _runToken) return;
        if (!attempt.found && _fallback && _shouldFallBack(attempt.error)) {
          final retry = await _attempt(
            gap.item.window!,
            lyricOtherSpanEngine(_engine),
          );
          if (!mounted || token != _runToken) return;
          if (retry.found) {
            attempt = retry;
            gap.fellBack = true;
          }
        }
        final error = attempt.error;
        setState(() {
          gap
            ..insertion = attempt.insertion
            ..engineLabel = attempt.engineLabel
            ..error = error?.message
            ..status = attempt.found
                ? LyricVocalGapBatchStatus.found
                : error == null
                ? LyricVocalGapBatchStatus.empty
                : error.cancelled
                ? LyricVocalGapBatchStatus.stopped
                : LyricVocalGapBatchStatus.failed
            ..selected = attempt.found;
        });
        // A busy runtime or a cancel ends the run: every later stretch would
        // fail the same way.
        if (error != null && (error.busy || error.cancelled)) {
          setState(
            () => _notice = error.cancelled
                ? LyricVocalGapBatchStrings.stopped
                : error.message,
          );
          return;
        }
      }
    } finally {
      if (mounted && token == _runToken) {
        setState(() {
          _running = false;
          _current = null;
        });
      }
    }
  }

  static bool _shouldFallBack(LyricSpanRecognitionException? error) =>
      error == null || !(error.busy || error.cancelled);

  Future<_Attempt> _attempt(
    LyricVocalGapWindow window,
    LyricSpanEngine engine,
  ) async {
    final audio = window.onAudio(_offset);
    try {
      final result = await widget.recognizer.recognize(
        projectId: widget.projectId,
        start: audio.start,
        end: audio.end,
        engine: engine,
      );
      return _Attempt(
        insertion: widget.batch.actions.insertion(
          window,
          recognized: LyricVocalCheckActions.toDocumentTimeline(
            result.lines,
            _offset,
          ),
        ),
        engineLabel: result.engineLabel,
      );
    } on LyricSpanRecognitionException catch (error) {
      return _Attempt(error: error);
    }
  }

  Future<void> _stop() async {
    _runToken++;
    setState(() {
      for (final gap in _gaps) {
        if (gap.status == LyricVocalGapBatchStatus.running) {
          gap.status = LyricVocalGapBatchStatus.stopped;
        }
      }
      _running = false;
      _current = null;
      _notice = LyricVocalGapBatchStrings.stopped;
    });
    await widget.recognizer.cancel();
  }

  List<_GapState> _with(LyricVocalGapBatchStatus status) => [
    for (final gap in _gaps)
      if (gap.status == status) gap,
  ];

  List<_GapState> get _chosen => [
    for (final gap in _gaps)
      if (gap.status == LyricVocalGapBatchStatus.found && gap.selected) gap,
  ];

  int get _dismissCount =>
      _dismissEmpty ? _with(LyricVocalGapBatchStatus.empty).length : 0;

  void _confirm() {
    final result = widget.batch.apply(
      widget.document,
      insertions: [for (final gap in _chosen) gap.insertion!],
      dismiss: _dismissEmpty
          ? [for (final gap in _with(LyricVocalGapBatchStatus.empty)) gap.item.span]
          : const [],
    );
    if (result == null) return;
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: result.document,
        label: LyricVocalGapBatchStrings.title,
        message: LyricVocalGapBatchStrings.message(result),
        selectedLineIndex: result.insertedIndices.isEmpty
            ? null
            : result.insertedIndices.first,
      ),
    );
  }

  int _anchorRow(LyricVocalGapWindow window) {
    final last = widget.document.lines.length - 1;
    if (last < 0) return 0;
    return window.insertAt > last ? last : window.insertAt;
  }

  String _status(_GapState gap) => switch (gap.status) {
    LyricVocalGapBatchStatus.skipped => LyricVocalCheckStrings.windowFailure(
      gap.item.failure!,
    ),
    LyricVocalGapBatchStatus.waiting => '等待识别',
    LyricVocalGapBatchStatus.running => '正在识别…',
    LyricVocalGapBatchStatus.found =>
      '${gap.engineLabel ?? LyricVocalCheckStrings.engineLabel(_engine)}'
          ' 识别出 ${gap.rowCount} 行',
    LyricVocalGapBatchStatus.empty => LyricVocalGapBatchStrings.nothingFound,
    LyricVocalGapBatchStatus.failed => gap.error ?? '识别失败',
    LyricVocalGapBatchStatus.stopped => '已停止',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = _chosen;
    final rows = chosen.fold<int>(0, (sum, gap) => sum + gap.rowCount);
    final dismissCount = _dismissCount;
    final emptyCount = _with(LyricVocalGapBatchStatus.empty).length;
    final rerunCount = [
      for (final gap in _gaps)
        if (gap.item.isSendable && gap.canRunAgain) gap,
    ].length;
    final canConfirm = !_running && (rows > 0 || dismissCount > 0);

    return LyricBatchEditDialogFrame(
      title: LyricVocalGapBatchStrings.title,
      confirmKey: const ValueKey('vocal_gap_batch_confirm'),
      confirmIcon: Icons.playlist_add_rounded,
      confirmLabel: _running
          ? '正在识别…'
          : LyricVocalGapBatchStrings.confirmLabel(
              rows: rows,
              gaps: chosen.length,
              dismissed: dismissCount,
            ),
      onConfirm: canConfirm ? _confirm : null,
      children: [
        const LyricBatchNote(LyricVocalGapBatchStrings.intro),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final engine in LyricSpanEngine.values)
              ChoiceChip(
                key: ValueKey('vocal_gap_batch_engine_${engine.name}'),
                label: Text(LyricVocalCheckStrings.engineLabel(engine)),
                selected: _engine == engine,
                onSelected: _running
                    ? null
                    : (_) => setState(() => _engine = engine),
              ),
            if (_running)
              TextButton(
                key: const ValueKey('vocal_gap_batch_stop'),
                onPressed: _stop,
                child: const Text('停止'),
              )
            else if (rerunCount > 0)
              TextButton.icon(
                key: const ValueKey('vocal_gap_batch_rerun'),
                onPressed: _runQueue,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(LyricVocalGapBatchStrings.rerunLabel(rerunCount)),
              ),
          ],
        ),
        CheckboxListTile(
          key: const ValueKey('vocal_gap_batch_fallback'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: _fallback,
          onChanged: _running
              ? null
              : (value) => setState(() => _fallback = value ?? false),
          title: const Text(LyricVocalGapBatchStrings.fallbackLabel),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_running && _current != null)
          AppInlineLoading(
            key: const ValueKey('vocal_gap_batch_progress'),
            message: LyricVocalGapBatchStrings.progress(
              _current!,
              _queueTotal,
            ),
          )
        else
          Text(
            LyricVocalGapBatchStrings.summary(
              found: _with(LyricVocalGapBatchStatus.found).length,
              empty: emptyCount,
              failed: _with(LyricVocalGapBatchStatus.failed).length,
              skipped: _with(LyricVocalGapBatchStatus.skipped).length,
              waiting:
                  _with(LyricVocalGapBatchStatus.waiting).length +
                  _with(LyricVocalGapBatchStatus.stopped).length,
            ),
            key: const ValueKey('vocal_gap_batch_summary'),
            style: theme.textTheme.titleSmall,
          ),
        if (_notice case final notice?) ...[
          const SizedBox(height: AppSpacing.xs),
          LyricBatchNote(
            notice,
            warning: true,
            key: const ValueKey('vocal_gap_batch_notice'),
          ),
        ],
        const Divider(height: AppSpacing.lg),
        for (final (index, gap) in _gaps.indexed) _gapRow(theme, index, gap),
        if (emptyCount > 0)
          CheckboxListTile(
            key: const ValueKey('vocal_gap_batch_dismiss_empty'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _dismissEmpty,
            onChanged: _running
                ? null
                : (value) => setState(() => _dismissEmpty = value ?? false),
            title: Text(LyricVocalGapBatchStrings.dismissEmptyLabel(emptyCount)),
          ),
      ],
    );
  }

  Widget _gapRow(ThemeData theme, int index, _GapState gap) {
    final window = gap.item.window;
    final preview = widget.onPreviewSpan;
    final found = gap.status == LyricVocalGapBatchStatus.found;
    final warning =
        gap.status == LyricVocalGapBatchStatus.failed ||
        gap.status == LyricVocalGapBatchStatus.skipped;
    return Padding(
      key: ValueKey('vocal_gap_batch_row_$index'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                key: ValueKey('vocal_gap_batch_check_$index'),
                value: found && gap.selected,
                onChanged: found && !_running
                    ? (value) => setState(() => gap.selected = value ?? false)
                    : null,
              ),
              Text(
                LyricVocalCheckStrings.span(gap.item.span),
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _status(gap),
                  key: ValueKey('vocal_gap_batch_status_$index'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: warning
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              if (preview != null &&
                  window != null &&
                  widget.document.lines.isNotEmpty)
                IconButton(
                  key: ValueKey('vocal_gap_batch_preview_$index'),
                  tooltip: '试听这一段',
                  onPressed: () =>
                      preview(_anchorRow(window), window.start, window.end),
                  icon: const Icon(Icons.hearing_rounded, size: 18),
                ),
            ],
          ),
          if (found) ...[
            if (gap.fellBack)
              LyricBatchNote(
                LyricVocalGapBatchStrings.fallbackNote(gap.engineLabel ?? ''),
              ),
            for (final line in gap.insertion!.newLines)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.xxl,
                  top: AppSpacing.xs / 2,
                ),
                child: Text(
                  '${LyricSpanRecognitionStrings.clock(line.startTime)}  '
                  '${line.text}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: gap.selected ? null : AppColors.textTertiary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
