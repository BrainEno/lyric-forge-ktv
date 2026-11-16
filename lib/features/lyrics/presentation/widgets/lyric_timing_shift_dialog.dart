import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_timing_shift_service.dart';
import 'lyric_batch_text_edit.dart';

/// User-facing text of the timing shift tool.
class LyricTimingShiftStrings {
  const LyricTimingShiftStrings._();

  static const String actionTitle = '平移 / 伸缩时间轴';
  static const String actionDetail = '整段时间提前或推后；两点校准修正速度不一致的时间轴';
  static const String intro =
      '只调整所选范围内各行的开始和结束时间，文字和其他行不变。'
      '“平移”让范围内所有时间加减同一个值；'
      '“两点校准”把两行钉到新的开始时间，中间各行按比例拉伸，'
      '适合换了音频版本、或后半段越来越偏的情况。结果可撤销，保存后才写盘。';

  static String applied(int rows) => '已调整 $rows 行的时间（未写入磁盘）';

  static String failure(LyricTimingShiftFailure failure) => switch (failure) {
    LyricTimingShiftFailure.invalidRange => '行范围无效，请检查起止行号。',
    LyricTimingShiftFailure.invalidAnchor => '校准行号超出范围。',
    LyricTimingShiftFailure.anchorsCoincide => '两个校准行的原开始时间相同，请换一行。',
    LyricTimingShiftFailure.implausibleScale =>
      '两个目标时间的间隔与原间隔相差超过一倍或顺序颠倒，请检查输入。',
    LyricTimingShiftFailure.noChange => '当前设置不会改变任何时间。',
  };
}

/// Shows the timing shift tool. Returns the confirmed edit, or null.
///
/// [playhead] is the paused playhead on the document timeline (global offset
/// already removed); when given, the tool offers it as a target time.
Future<LyricBatchTextEdit?> showLyricTimingShiftDialog(
  BuildContext context, {
  required LyricDocument document,
  int? selectedIndex,
  Duration? audioDuration,
  Duration? playhead,
  ValueChanged<int>? onPreviewLine,
  LyricTimingShiftService service = const LyricTimingShiftService(),
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricTimingShiftDialog(
      document: document,
      selectedIndex: selectedIndex,
      audioDuration: audioDuration,
      playhead: playhead,
      onPreviewLine: onPreviewLine,
      service: service,
    ),
  );
}

class LyricTimingShiftDialog extends StatefulWidget {
  const LyricTimingShiftDialog({
    super.key,
    required this.document,
    this.selectedIndex,
    this.audioDuration,
    this.playhead,
    this.onPreviewLine,
    this.service = const LyricTimingShiftService(),
  });

  final LyricDocument document;
  final int? selectedIndex;
  final Duration? audioDuration;
  final Duration? playhead;
  final ValueChanged<int>? onPreviewLine;
  final LyricTimingShiftService service;

  /// How many changed rows the preview lists.
  static const int previewLimit = 8;

  @override
  State<LyricTimingShiftDialog> createState() => _LyricTimingShiftDialogState();
}

class _LyricTimingShiftDialogState extends State<LyricTimingShiftDialog> {
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _offset;
  late final TextEditingController _fromRow;
  late final TextEditingController _fromTime;
  late final TextEditingController _toRow;
  late final TextEditingController _toTime;
  LyricTimingShiftMode _mode = LyricTimingShiftMode.offset;

  LyricTimingShiftResult? _result;
  String? _inputError;

  List<LyricLine> get _lines => widget.document.lines;

  @override
  void initState() {
    super.initState();
    final count = _lines.length;
    final selected = widget.selectedIndex;
    final firstIndex = selected != null && selected > 0 && selected < count
        ? selected
        : 0;
    _first = TextEditingController(text: '${firstIndex + 1}');
    _last = TextEditingController(text: '$count');
    _offset = TextEditingController(text: '0.00');
    _fromRow = TextEditingController(text: '${firstIndex + 1}');
    _fromTime = TextEditingController(
      text: formatLyricTimeInput(_lines[firstIndex].startTime),
    );
    _toRow = TextEditingController(text: '$count');
    _toTime = TextEditingController(
      text: formatLyricTimeInput(_lines[count - 1].startTime),
    );
    for (final controller in _controllers) {
      controller.addListener(_recompute);
    }
    _computeResult();
  }

  List<TextEditingController> get _controllers => [
    _first,
    _last,
    _offset,
    _fromRow,
    _fromTime,
    _toRow,
    _toTime,
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _row(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < 1 || value > _lines.length) return null;
    return value - 1;
  }

  void _recompute() => setState(_computeResult);

  void _computeResult() {
    final shift = _buildShift();
    if (shift == null) {
      _result = null;
      return;
    }
    _inputError = null;
    _result = widget.service.apply(
      widget.document,
      shift,
      audioDuration: widget.audioDuration,
    );
  }

  /// The shift described by the inputs, or null with [_inputError] set.
  LyricTimingShift? _buildShift() {
    final first = _row(_first);
    final last = _row(_last);
    if (first == null || last == null || first > last) {
      _inputError = '请输入 1–${_lines.length} 之间的起止行号，且起始行不晚于结束行。';
      return null;
    }
    switch (_mode) {
      case LyricTimingShiftMode.offset:
        final delta = parseLyricTimeInput(_offset.text);
        if (delta == null) {
          _inputError = '偏移量格式不正确，例如 1.5、-0.25 或 -0:01.20。';
          return null;
        }
        return LyricTimingShift.offset(
          firstIndex: first,
          lastIndex: last,
          delta: delta,
        );
      case LyricTimingShiftMode.twoPoint:
        final fromRow = _row(_fromRow);
        final toRow = _row(_toRow);
        final fromTime = parseLyricTimeInput(_fromTime.text);
        final toTime = parseLyricTimeInput(_toTime.text);
        if (fromRow == null || toRow == null) {
          _inputError = '请输入有效的校准行号。';
          return null;
        }
        if (fromTime == null ||
            toTime == null ||
            fromTime.isNegative ||
            toTime.isNegative) {
          _inputError = '目标时间格式不正确，例如 1:23.45 或 83.45。';
          return null;
        }
        return LyricTimingShift.twoPoint(
          firstIndex: first,
          lastIndex: last,
          fromIndex: fromRow,
          fromTarget: fromTime,
          toIndex: toRow,
          toTarget: toTime,
        );
    }
  }

  void _nudgeOffset(int milliseconds) {
    final current = parseLyricTimeInput(_offset.text) ?? Duration.zero;
    final next = current + Duration(milliseconds: milliseconds);
    _offset.text = (next.inMilliseconds / 1000).toStringAsFixed(2);
  }

  /// Sets the offset so the first row of the range starts at the playhead.
  void _offsetToPlayhead() {
    final playhead = widget.playhead;
    final first = _row(_first);
    if (playhead == null || first == null) return;
    final delta = playhead - _lines[first].startTime;
    _offset.text = (delta.inMilliseconds / 1000).toStringAsFixed(2);
  }

  void _setScope({required int first, required int last}) {
    _first.text = '${first + 1}';
    _last.text = '${last + 1}';
  }

  void _confirm() {
    final result = _result;
    final document = result?.document;
    if (result == null || document == null) return;
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: document,
        label: LyricTimingShiftStrings.actionTitle,
        message: LyricTimingShiftStrings.applied(result.changedIndices.length),
        selectedLineIndex: result.changedIndices.first,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final ready = result != null && result.isSuccess;
    final selected = widget.selectedIndex;

    return LyricBatchEditDialogFrame(
      title: LyricTimingShiftStrings.actionTitle,
      confirmKey: const ValueKey('timing_shift_confirm'),
      confirmIcon: Icons.timer_outlined,
      confirmLabel: ready ? '调整 ${result.changedIndices.length} 行' : '调整时间',
      onConfirm: ready ? _confirm : null,
      children: [
        const LyricBatchNote(LyricTimingShiftStrings.intro),
        const SizedBox(height: AppSpacing.md),
        Text('范围', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('第'),
            _NumberField(
              key: const ValueKey('timing_shift_first'),
              controller: _first,
              label: '起始行',
            ),
            const Text('行 到 第'),
            _NumberField(
              key: const ValueKey('timing_shift_last'),
              controller: _last,
              label: '结束行',
            ),
            const Text('行'),
            ActionChip(
              key: const ValueKey('timing_shift_scope_all'),
              label: const Text('全部'),
              onPressed: () => _setScope(first: 0, last: _lines.length - 1),
            ),
            if (selected != null && selected >= 0 && selected < _lines.length)
              ActionChip(
                key: const ValueKey('timing_shift_scope_from_selected'),
                label: Text('从第 ${selected + 1} 行到末尾'),
                onPressed: () =>
                    _setScope(first: selected, last: _lines.length - 1),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SegmentedButton<LyricTimingShiftMode>(
          key: const ValueKey('timing_shift_mode'),
          segments: const [
            ButtonSegment(
              value: LyricTimingShiftMode.offset,
              icon: Icon(Icons.swap_horiz_rounded),
              label: Text('平移'),
            ),
            ButtonSegment(
              value: LyricTimingShiftMode.twoPoint,
              icon: Icon(Icons.straighten_rounded),
              label: Text('两点校准'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (value) {
            _mode = value.first;
            _recompute();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_mode == LyricTimingShiftMode.offset)
          _offsetInputs()
        else
          _twoPointInputs(),
        const SizedBox(height: AppSpacing.md),
        ..._preview(theme, result),
      ],
    );
  }

  Widget _offsetInputs() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: TextField(
            key: const ValueKey('timing_shift_offset'),
            controller: _offset,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: '偏移（秒）',
              helperText: '负数 = 提前',
              isDense: true,
            ),
          ),
        ),
        for (final step in const [-1000, -100, 100, 1000])
          ActionChip(
            key: ValueKey('timing_shift_nudge_$step'),
            label: Text(
              '${step > 0 ? '+' : '-'}${(step.abs() / 1000).toStringAsFixed(1)} s',
            ),
            onPressed: () => _nudgeOffset(step),
          ),
        if (widget.playhead != null)
          ActionChip(
            key: const ValueKey('timing_shift_offset_playhead'),
            avatar: const Icon(Icons.my_location_rounded, size: 16),
            label: const Text('起始行对齐到播放头'),
            onPressed: _offsetToPlayhead,
          ),
      ],
    );
  }

  Widget _twoPointInputs() {
    Widget anchor({
      required String title,
      required Key rowKey,
      required Key timeKey,
      required TextEditingController row,
      required TextEditingController time,
    }) {
      final index = _row(row);
      final playhead = widget.playhead;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title),
          _NumberField(key: rowKey, controller: row, label: '行号'),
          SizedBox(
            width: 130,
            child: TextField(
              key: timeKey,
              controller: time,
              decoration: InputDecoration(
                labelText: '新的开始时间',
                helperText: index == null
                    ? null
                    : '原 ${formatLyricTimeInput(_lines[index].startTime)}',
                isDense: true,
              ),
            ),
          ),
          if (playhead != null)
            IconButton(
              tooltip: '使用播放头 ${formatLyricTimeInput(playhead)}',
              onPressed: () => time.text = formatLyricTimeInput(playhead),
              icon: const Icon(Icons.my_location_rounded),
            ),
          if (index != null && widget.onPreviewLine != null)
            IconButton(
              tooltip: '试听第 ${index + 1} 行',
              onPressed: () => widget.onPreviewLine!(index),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LyricBatchNote('选两行相距较远、听得清楚的句首作为校准点，效果最好。'),
        const SizedBox(height: AppSpacing.xs),
        anchor(
          title: '校准点 1：第',
          rowKey: const ValueKey('timing_shift_from_row'),
          timeKey: const ValueKey('timing_shift_from_time'),
          row: _fromRow,
          time: _fromTime,
        ),
        const SizedBox(height: AppSpacing.xs),
        anchor(
          title: '校准点 2：第',
          rowKey: const ValueKey('timing_shift_to_row'),
          timeKey: const ValueKey('timing_shift_to_time'),
          row: _toRow,
          time: _toTime,
        ),
      ],
    );
  }

  List<Widget> _preview(ThemeData theme, LyricTimingShiftResult? result) {
    if (result == null) {
      return [LyricBatchNote(_inputError ?? '', warning: true)];
    }
    final failure = result.failure;
    if (failure != null) {
      return [
        LyricBatchNote(
          LyricTimingShiftStrings.failure(failure),
          warning: failure != LyricTimingShiftFailure.noChange,
        ),
      ];
    }
    final document = result.document!;
    final changed = result.changedIndices;
    final shown = changed.length.clamp(0, LyricTimingShiftDialog.previewLimit);
    final scalePercent = ((result.scale - 1) * 100).toStringAsFixed(1);
    return [
      Text(
        [
          '将调整 ${changed.length} 行',
          if (_mode == LyricTimingShiftMode.twoPoint)
            '速度系数 ${result.scale.toStringAsFixed(4)}'
                '（${result.scale >= 1 ? '+' : ''}$scalePercent%）',
          if (result.clampedCount > 0) '${result.clampedCount} 行被限制在 0:00 或音频末尾',
        ].join('，'),
        key: const ValueKey('timing_shift_summary'),
        style: theme.textTheme.titleSmall,
      ),
      if (result.introducedIssues.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xs),
        LyricBatchNote(
          '调整后会新增 ${result.introducedIssues.length} 处时间冲突，例如：'
          '${result.introducedIssues.first.message}'
          '应用后可用“检查时间轴”修复。',
          warning: true,
        ),
      ],
      if (result.resolvedIssues.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xs),
        LyricBatchNote('同时消除 ${result.resolvedIssues.length} 处原有时间冲突。'),
      ],
      const SizedBox(height: AppSpacing.xs),
      for (var position = 0; position < shown; position++)
        _ShiftPreviewRow(
          index: changed[position],
          before: _lines[changed[position]],
          after: document.lines[changed[position]],
        ),
      if (changed.length > shown)
        LyricBatchNote('…另有 ${changed.length - shown} 行按同样规则调整。'),
    ];
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense: true,
          hintText: label,
          semanticCounterText: label,
        ),
      ),
    );
  }
}

class _ShiftPreviewRow extends StatelessWidget {
  const _ShiftPreviewRow({
    required this.index,
    required this.before,
    required this.after,
  });

  final int index;
  final LyricLine before;
  final LyricLine after;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = before.text.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '第 ${index + 1} 行  ',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            TextSpan(
              text:
                  '${formatLyricTimeInput(before.startTime)} → '
                  '${formatLyricTimeInput(after.startTime)}',
            ),
            if (text.isNotEmpty)
              TextSpan(
                text: '  $text',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
