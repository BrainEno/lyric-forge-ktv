import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/proofreading/forced_alignment_language.dart';
import '../../domain/proofreading/forced_alignment_proofread_service.dart';
import '../../domain/services/lyric_span_rerecognition.dart';
import '../lyric_review_strings.dart';
import 'lyric_batch_text_edit.dart';
import 'lyric_missed_repeat_dialog.dart' show LyricSpanPreview;

/// User-facing text of "re-run this stretch".
class LyricSpanRecognitionStrings {
  const LyricSpanRecognitionStrings._();

  static const String actionTitle = '重新识别这一段';
  static const String actionDetail = '只把选中的几行重新识别或重新对齐；用另一个引擎找回识别错的、漏掉的歌词';
  static const String intro =
      '整首识别偶尔会把一段唱错、重复或漏掉，其余部分却没问题。'
      '这里只把选中的几行对应的音频剪出来重新处理，其他行和手动修改都不受影响。'
      '“重新识别”给出新的文字和时间，替换选中的行；换一个引擎往往能找回识别错的句子。'
      '“按现有文字重新对齐”保留文字，只让对齐器重新计算这些行和逐字的时间，'
      '适合改过文字后逐字时间丢失的行。'
      '向前、向后延伸可以给识别器一点上下文；选“到上一行/到下一行”可以识别两行之间漏掉的歌词。'
      '首次运行需要加载模型，可能要等几十秒。结果先预览，确认后才替换，可撤销，保存后才写盘。';

  static const String noRecognizer = '没有可用的本地识别运行时，无法重新识别。请先在转写设置中准备运行环境。';
  static const String noAudio = '本工程没有音频，无法重新识别。';

  static String modeLabel(LyricSpanMode mode) => switch (mode) {
    LyricSpanMode.recognizeQwen => 'Qwen3-ASR 重新识别',
    LyricSpanMode.recognizeWhisper => 'Whisper 重新识别',
    LyricSpanMode.realign => '按现有文字重新对齐',
  };

  static String reachLabel(LyricSpanReach reach, {required bool lead}) =>
      switch (reach) {
        LyricSpanReach.none => '不延伸',
        LyricSpanReach.half => '0.5 秒',
        LyricSpanReach.one => '1 秒',
        LyricSpanReach.two => '2 秒',
        LyricSpanReach.neighbour => lead ? '到上一行' : '到下一行',
      };

  static String windowFailure(LyricSpanWindowFailure failure) =>
      switch (failure) {
        LyricSpanWindowFailure.invalidRange => '行范围无效。',
        LyricSpanWindowFailure.tooShort => '这一段太短（不到 0.5 秒），请多选几行或向前后延伸。',
        LyricSpanWindowFailure.tooLong => '这一段超过 90 秒，请少选几行；更长的范围建议整首重新识别。',
      };

  static String realignmentFailure(
    LyricSpanRealignment plan,
  ) => switch (plan.status) {
    LyricSpanRealignmentStatus.ready => '',
    LyricSpanRealignmentStatus.noSpans => '对齐器没有返回可用的时间。',
    LyricSpanRealignmentStatus.nothingToAlign => '选中的行没有可对齐的文字。',
    LyricSpanRealignmentStatus.textMismatch =>
      '对齐结果与第 ${(plan.failedIndex ?? plan.window.first) + 1} 行的文字对不上，未修改任何时间。',
    LyricSpanRealignmentStatus.incomplete =>
      '对齐器在第 ${(plan.failedIndex ?? plan.window.last) + 1} 行之前就停止了，未修改任何时间。',
  };

  static String clock(Duration value) {
    final negative = value.isNegative;
    final abs = negative ? -value : value;
    final seconds = (abs.inMilliseconds % 60000) / 1000;
    return '${negative ? '-' : ''}${abs.inMinutes}:'
        '${seconds.toStringAsFixed(1).padLeft(4, '0')}';
  }

  static String seconds(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(1);
}

/// Shows "re-run this stretch". Returns the confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricSpanRecognitionDialog(
  BuildContext context, {
  required LyricDocument document,
  required String projectId,
  required LyricSpanRecognizer recognizer,
  int? selectedIndex,
  Set<int> protectedIndices = const {},
  Duration? audioDuration,
  LyricSpanPreview? onPreviewSpan,
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LyricSpanRecognitionDialog(
      document: document,
      projectId: projectId,
      recognizer: recognizer,
      selectedIndex: selectedIndex,
      protectedIndices: protectedIndices,
      audioDuration: audioDuration,
      onPreviewSpan: onPreviewSpan,
    ),
  );
}

class LyricSpanRecognitionDialog extends StatefulWidget {
  const LyricSpanRecognitionDialog({
    super.key,
    required this.document,
    required this.projectId,
    required this.recognizer,
    this.selectedIndex,
    this.protectedIndices = const {},
    this.audioDuration,
    this.onPreviewSpan,
    this.planner = const LyricSpanRerecognitionPlanner(),
  });

  final LyricDocument document;
  final String projectId;
  final LyricSpanRecognizer recognizer;
  final int? selectedIndex;
  final Set<int> protectedIndices;
  final Duration? audioDuration;
  final LyricSpanPreview? onPreviewSpan;
  final LyricSpanRerecognitionPlanner planner;

  /// How many rows each side of the preview lists.
  static const int previewLimit = 12;

  @override
  State<LyricSpanRecognitionDialog> createState() =>
      _LyricSpanRecognitionDialogState();
}

class _LyricSpanRecognitionDialogState
    extends State<LyricSpanRecognitionDialog> {
  late int _first;
  late int _last;
  LyricSpanReach _lead = LyricSpanReach.half;
  LyricSpanReach _tail = LyricSpanReach.half;
  LyricSpanMode _mode = LyricSpanMode.recognizeQwen;

  bool _running = false;
  int _runToken = 0;
  String? _error;
  LyricSpanReplacement? _replacement;
  LyricSpanRealignment? _realignment;
  String? _engineLabel;
  bool _textOnly = false;

  List<LyricLine> get _lines => widget.document.lines;
  Duration get _offset => widget.document.globalOffset ?? Duration.zero;

  @override
  void initState() {
    super.initState();
    final selected = widget.selectedIndex;
    _first = selected != null && selected >= 0 && selected < _lines.length
        ? selected
        : 0;
    _last = _first;
  }

  @override
  void dispose() {
    // Closing the dialog abandons a running request.
    if (_running) unawaited(widget.recognizer.cancel());
    super.dispose();
  }

  LyricSpanWindowResult get _window => widget.planner.window(
    widget.document,
    first: _first,
    last: _last,
    lead: _lead,
    tail: _tail,
    audioDuration: widget.audioDuration,
  );

  /// Any change to what is run makes the shown result stale.
  void _change(VoidCallback update) => setState(() {
    update();
    _runToken++;
    _running = false;
    _error = null;
    _replacement = null;
    _realignment = null;
    _engineLabel = null;
    _textOnly = false;
  });

  Future<void> _run() async {
    final windowResult = _window;
    final window = windowResult.window;
    if (window == null || windowResult.failure != null) return;
    final audio = window.onAudio(_offset);
    final token = ++_runToken;
    final mode = _mode;
    setState(() {
      _running = true;
      _error = null;
      _replacement = null;
      _realignment = null;
    });
    try {
      final engine = mode.engine;
      if (engine != null) {
        final result = await widget.recognizer.recognize(
          projectId: widget.projectId,
          start: audio.start,
          end: audio.end,
          engine: engine,
        );
        if (!mounted || token != _runToken) return;
        final replacement = widget.planner.replacement(
          widget.document,
          window: window,
          recognized: [for (final line in result.lines) _toDocument(line)],
          protectedIndices: widget.protectedIndices,
        );
        setState(() {
          _replacement = replacement;
          _engineLabel = result.engineLabel;
          _textOnly = false;
          if (replacement.isEmpty) _error = '这一段没有识别出歌词。';
        });
      } else {
        final text = widget.planner.alignmentText(widget.document, window);
        if (text.isEmpty) {
          setState(() => _error = '选中的行没有可对齐的文字。');
          return;
        }
        final language = ForcedAlignmentLanguage.resolve(
          widget.document.language,
        );
        final spans = await widget.recognizer.align(
          projectId: widget.projectId,
          start: audio.start,
          end: audio.end,
          text: text,
          language: language,
        );
        if (!mounted || token != _runToken) return;
        final realignment = widget.planner.realignment(
          widget.document,
          window: window,
          spans: [
            for (final span in spans)
              ForcedAlignedSpan(
                text: span.text,
                start: span.start - _offset,
                end: span.end - _offset,
              ),
          ],
        );
        setState(() {
          _realignment = realignment;
          if (!realignment.isReady) {
            _error = LyricSpanRecognitionStrings.realignmentFailure(
              realignment,
            );
          }
        });
      }
    } on LyricSpanRecognitionException catch (error) {
      if (!mounted || token != _runToken) return;
      setState(() => _error = error.cancelled ? '已取消。' : error.message);
    } on ForcedAlignmentLanguageResolutionException catch (error) {
      if (!mounted || token != _runToken) return;
      setState(
        () => _error = LyricReviewStrings.forcedAlignmentLanguageError(error),
      );
    } finally {
      if (mounted && token == _runToken) setState(() => _running = false);
    }
  }

  Future<void> _cancelRun() async {
    _runToken++;
    setState(() {
      _running = false;
      _error = '已取消。';
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
    final replacement = _replacement;
    final realignment = _realignment;
    final rows = '${_first + 1}–${_last + 1}';
    if (replacement != null && !replacement.isEmpty) {
      final textOnly = _textOnly && replacement.canReplaceTextOnly;
      Navigator.of(context).pop(
        LyricBatchTextEdit(
          document: replacement.applyTo(widget.document, textOnly: textOnly),
          label: LyricSpanRecognitionStrings.actionTitle,
          message: textOnly
              ? '已替换第 $rows 行的文字，时间不变（未写入磁盘）'
              : '第 $rows 行已替换为 ${replacement.newLines.length} 行'
                    '（${_engineLabel ?? '重新识别'}，未写入磁盘）',
          selectedLineIndex: _first,
        ),
      );
    } else if (realignment != null && realignment.isReady) {
      Navigator.of(context).pop(
        LyricBatchTextEdit(
          document: realignment.applyTo(widget.document),
          label: '重新对齐这一段',
          message:
              '已重新对齐第 $rows 行的时间，'
              '${realignment.changedCount(widget.document)} 行有变化（未写入磁盘）',
          selectedLineIndex: _first,
        ),
      );
    }
  }

  String get _confirmLabel {
    final replacement = _replacement;
    final realignment = _realignment;
    if (_running) return '正在处理…';
    if (replacement != null && !replacement.isEmpty) {
      if (_textOnly && replacement.canReplaceTextOnly) {
        return '只替换 ${replacement.oldLines.length} 行的文字';
      }
      return '替换为 ${replacement.newLines.length} 行';
    }
    if (realignment != null && realignment.isReady) {
      return '更新 ${realignment.rows.length} 行的时间';
    }
    return '请先运行';
  }

  bool get _canConfirm =>
      !_running &&
      ((_replacement != null && !_replacement!.isEmpty) ||
          (_realignment?.isReady ?? false));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final windowResult = _window;
    final window = windowResult.window;
    final failure = windowResult.failure;
    final protectedInRange = [
      for (var index = _first; index <= _last; index++)
        if (widget.protectedIndices.contains(index)) index,
    ].length;

    return LyricBatchEditDialogFrame(
      title: LyricSpanRecognitionStrings.actionTitle,
      confirmKey: const ValueKey('span_recognition_confirm'),
      confirmIcon: Icons.published_with_changes_rounded,
      confirmLabel: _confirmLabel,
      onConfirm: _canConfirm ? _confirm : null,
      children: [
        const LyricBatchNote(LyricSpanRecognitionStrings.intro),
        const SizedBox(height: AppSpacing.sm),
        _RowStepper(
          key: const ValueKey('span_first_row'),
          label: '从第',
          value: _first,
          canDecrease: !_running && _first > 0,
          canIncrease: !_running && _first < _last,
          onChanged: (value) => _change(() => _first = value),
        ),
        _RowStepper(
          key: const ValueKey('span_last_row'),
          label: '到第',
          value: _last,
          canDecrease: !_running && _last > _first,
          canIncrease: !_running && _last < _lines.length - 1,
          onChanged: (value) => _change(() => _last = value),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ReachPicker(
              key: const ValueKey('span_lead'),
              label: '向前延伸',
              lead: true,
              value: _lead,
              onChanged: _running
                  ? null
                  : (value) => _change(() => _lead = value),
            ),
            _ReachPicker(
              key: const ValueKey('span_tail'),
              label: '向后延伸',
              lead: false,
              value: _tail,
              onChanged: _running
                  ? null
                  : (value) => _change(() => _tail = value),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (window != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  '处理范围 ${LyricSpanRecognitionStrings.clock(window.start)}–'
                  '${LyricSpanRecognitionStrings.clock(window.end)}'
                  '（${LyricSpanRecognitionStrings.seconds(window.length)} 秒，'
                  '${window.rowCount} 行）',
                  key: const ValueKey('span_window_summary'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (widget.onPreviewSpan != null && failure == null)
                IconButton(
                  tooltip: '试听这一段',
                  onPressed: () =>
                      widget.onPreviewSpan!(_first, window.start, window.end),
                  icon: const Icon(Icons.hearing_rounded),
                ),
            ],
          ),
        if (failure != null)
          LyricBatchNote(
            LyricSpanRecognitionStrings.windowFailure(failure),
            warning: true,
          ),
        if (protectedInRange > 0)
          LyricBatchNote(
            '选中的行里有 $protectedInRange 行手动编辑过，替换后这些修改会被新结果覆盖。',
            warning: true,
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final mode in LyricSpanMode.values)
              ChoiceChip(
                key: ValueKey('span_mode_${mode.name}'),
                label: Text(LyricSpanRecognitionStrings.modeLabel(mode)),
                selected: _mode == mode,
                onSelected: _running
                    ? null
                    : (_) => _change(() => _mode = mode),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_running) ...[
              AppInlineLoading(
                message: _mode == LyricSpanMode.realign ? '正在重新对齐…' : '正在重新识别…',
              ),
              TextButton(
                key: const ValueKey('span_cancel_run'),
                onPressed: _cancelRun,
                child: const Text('停止'),
              ),
            ] else
              FilledButton.tonalIcon(
                key: const ValueKey('span_run'),
                onPressed: failure == null && window != null ? _run : null,
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: Text(
                  _replacement != null || _realignment != null || _error != null
                      ? '再运行一次'
                      : (_mode == LyricSpanMode.realign ? '开始对齐' : '开始识别'),
                ),
              ),
          ],
        ),
        if (_error case final error?) ...[
          const SizedBox(height: AppSpacing.xs),
          LyricBatchNote(
            error,
            warning: true,
            key: const ValueKey('span_error'),
          ),
        ],
        const Divider(height: AppSpacing.lg),
        if (_replacement case final replacement? when !replacement.isEmpty)
          ..._replacementPreview(theme, replacement)
        else if (_realignment case final realignment? when realignment.isReady)
          ..._realignmentPreview(theme, realignment)
        else
          ..._currentRows(theme),
      ],
    );
  }

  List<Widget> _currentRows(ThemeData theme) {
    final count = _last - _first + 1;
    final shown = count < LyricSpanRecognitionDialog.previewLimit
        ? count
        : LyricSpanRecognitionDialog.previewLimit;
    return [
      Text('当前的行', style: theme.textTheme.labelLarge),
      for (var index = _first; index < _first + shown; index++)
        _TimedText(
          index: index,
          start: _lines[index].startTime,
          end: _lines[index].endTime,
          text: _lines[index].text,
          muted: false,
        ),
      if (count > shown) LyricBatchNote('另有 ${count - shown} 行未列出。'),
    ];
  }

  List<Widget> _replacementPreview(
    ThemeData theme,
    LyricSpanReplacement replacement,
  ) {
    final percent = (replacement.similarity * 100).round();
    final oldShown = replacement.oldLines.take(
      LyricSpanRecognitionDialog.previewLimit,
    );
    final newShown = replacement.newLines.take(
      LyricSpanRecognitionDialog.previewLimit,
    );
    return [
      Text(
        '${_engineLabel ?? '重新识别'}：${replacement.oldLines.length} 行 → '
        '${replacement.newLines.length} 行，文字相似度 $percent%',
        key: const ValueKey('span_result_summary'),
        style: theme.textTheme.titleSmall,
      ),
      if (!replacement.changesText)
        const LyricBatchNote('新结果与当前文字相同；替换只会更新时间和逐字时间。'),
      if (replacement.clippedCount > 0)
        LyricBatchNote('有 ${replacement.clippedCount} 段识别结果落在范围边缘、太短，已舍弃。'),
      if (replacement.protectedCount > 0)
        LyricBatchNote(
          '其中 ${replacement.protectedCount} 行手动编辑过，替换会覆盖这些修改。',
          warning: true,
        ),
      const SizedBox(height: AppSpacing.xs),
      Text('当前', style: theme.textTheme.labelLarge),
      for (final (offset, line) in oldShown.indexed)
        _TimedText(
          index: replacement.window.first + offset,
          start: line.startTime,
          end: line.endTime,
          text: line.text,
          muted: true,
        ),
      const SizedBox(height: AppSpacing.xs),
      Text('重新识别', style: theme.textTheme.labelLarge),
      for (final line in newShown)
        _TimedText(
          start: line.startTime,
          end: line.endTime,
          text: line.text,
          muted: false,
        ),
      if (replacement.newLines.length > LyricSpanRecognitionDialog.previewLimit)
        LyricBatchNote(
          '另有 ${replacement.newLines.length - LyricSpanRecognitionDialog.previewLimit} 行未列出。',
        ),
      if (replacement.canReplaceTextOnly && replacement.changesText)
        CheckboxListTile(
          key: const ValueKey('span_text_only'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _textOnly,
          onChanged: (value) => setState(() => _textOnly = value ?? false),
          title: const Text('只替换文字，保留原来的时间'),
          subtitle: const Text('行数相同时可用；文字有变化的行会丢掉逐字时间。'),
        ),
    ];
  }

  List<Widget> _realignmentPreview(
    ThemeData theme,
    LyricSpanRealignment realignment,
  ) {
    final changed = realignment.changedCount(widget.document);
    return [
      Text(
        '对齐了 ${realignment.rows.length} 行，其中 $changed 行的时间有变化',
        key: const ValueKey('span_result_summary'),
        style: theme.textTheme.titleSmall,
      ),
      for (final row in realignment.rows.take(
        LyricSpanRecognitionDialog.previewLimit,
      ))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            '${row.index + 1}  '
            '${LyricSpanRecognitionStrings.clock(_lines[row.index].startTime)}–'
            '${LyricSpanRecognitionStrings.clock(_lines[row.index].endTime)} → '
            '${LyricSpanRecognitionStrings.clock(row.start)}–'
            '${LyricSpanRecognitionStrings.clock(row.end)}  '
            '${row.words.length} 个字词  ${_lines[row.index].text.trim()}',
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }
}

class _RowStepper extends StatelessWidget {
  const _RowStepper({
    super.key,
    required this.label,
    required this.value,
    required this.canDecrease,
    required this.canIncrease,
    required this.onChanged,
  });

  final String label;
  final int value;
  final bool canDecrease;
  final bool canIncrease;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label),
        IconButton(
          tooltip: '$label上一行',
          onPressed: canDecrease ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        Text('${value + 1}', style: Theme.of(context).textTheme.titleSmall),
        IconButton(
          tooltip: '$label下一行',
          onPressed: canIncrease ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
        const Text('行'),
      ],
    );
  }
}

class _ReachPicker extends StatelessWidget {
  const _ReachPicker({
    super.key,
    required this.label,
    required this.lead,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool lead;
  final LyricSpanReach value;
  final ValueChanged<LyricSpanReach>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label '),
        DropdownButton<LyricSpanReach>(
          value: value,
          onChanged: onChanged == null
              ? null
              : (reach) {
                  if (reach != null) onChanged!(reach);
                },
          items: [
            for (final reach in LyricSpanReach.values)
              DropdownMenuItem(
                value: reach,
                child: Text(
                  LyricSpanRecognitionStrings.reachLabel(reach, lead: lead),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TimedText extends StatelessWidget {
  const _TimedText({
    this.index,
    required this.start,
    required this.end,
    required this.text,
    required this.muted,
  });

  /// Row number to show; null for a row that does not exist yet.
  final int? index;
  final Duration start;
  final Duration end;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '${index == null ? '' : '${index! + 1}  '}'
              '${LyricSpanRecognitionStrings.clock(start)}–'
              '${LyricSpanRecognitionStrings.clock(end)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text.trim().isEmpty ? '（空行）' : text.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: muted ? AppColors.textSecondary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
