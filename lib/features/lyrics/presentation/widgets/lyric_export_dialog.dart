import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_export_encoder.dart';
import '../../domain/services/lyric_timeline_repair_planner.dart';
import 'lyric_batch_text_edit.dart';

/// What the user chose in the export dialog.
class LyricExportRequest {
  final LyricExportFormat format;
  final LyricExportOptions options;

  const LyricExportRequest({required this.format, required this.options});
}

/// Shows the export dialog. Returns the chosen format and options, or null.
Future<LyricExportRequest?> showLyricExportDialog(
  BuildContext context, {
  required LyricDocument document,
  LyricExportFormat initialFormat = LyricExportFormat.lrc,
  LyricExportOptions initialOptions = const LyricExportOptions(
    lrcEndMarkers: true,
  ),
  Duration? audioDuration,
  LyricExportMetadata metadata = const LyricExportMetadata(),
}) {
  return showDialog<LyricExportRequest>(
    context: context,
    builder: (_) => LyricExportDialog(
      document: document,
      initialFormat: initialFormat,
      initialOptions: initialOptions,
      audioDuration: audioDuration,
      metadata: metadata,
    ),
  );
}

/// Format picker with a live preview of the file's first lines.
///
/// Before a timed export it also says how many rows have timeline problems,
/// because a subtitle file with overlapping cues is the most common reason a
/// karaoke video shows two lines at once.
class LyricExportDialog extends StatefulWidget {
  const LyricExportDialog({
    super.key,
    required this.document,
    this.initialFormat = LyricExportFormat.lrc,
    this.initialOptions = const LyricExportOptions(lrcEndMarkers: true),
    this.audioDuration,
    this.metadata = const LyricExportMetadata(),
    this.encoder = const LyricExportEncoder(),
    this.planner = const LyricTimelineRepairPlanner(),
  });

  final LyricDocument document;
  final LyricExportFormat initialFormat;
  final LyricExportOptions initialOptions;
  final Duration? audioDuration;
  final LyricExportMetadata metadata;
  final LyricExportEncoder encoder;
  final LyricTimelineRepairPlanner planner;

  /// How many lines of the encoded file the preview shows.
  static const int previewLines = 12;

  /// How early an ASS row appears when the lead-in switch is on.
  static const Duration assLeadIn = Duration(seconds: 1);

  @override
  State<LyricExportDialog> createState() => _LyricExportDialogState();
}

class _LyricExportDialogState extends State<LyricExportDialog> {
  late LyricExportFormat _format = widget.initialFormat;
  late bool _endMarkers = widget.initialOptions.lrcEndMarkers;
  late bool _paragraphs = widget.initialOptions.paragraphsAtPauses;
  late bool _assLeadIn = widget.initialOptions.assLeadIn > Duration.zero;
  late final int _timelineRows = widget.planner
      .plan(widget.document, audioDuration: widget.audioDuration)
      .problemRowCount;
  late final int _wordTimedRows = widget.encoder.wordTiming.usableRowCount(
    widget.document,
  );
  late final int _emptyRows = widget.document.lines
      .where((line) => LyricExportEncoder.singleLine(line.text).isEmpty)
      .length;

  LyricExportOptions get _options => LyricExportOptions(
    lrcEndMarkers: _endMarkers,
    paragraphsAtPauses: _paragraphs,
    pauseThreshold: widget.initialOptions.pauseThreshold,
    paragraphGap: widget.initialOptions.paragraphGap,
    assLeadIn: _assLeadIn ? LyricExportDialog.assLeadIn : Duration.zero,
  );

  String _preview() {
    final encoded = widget.encoder.encode(
      widget.document,
      _format,
      options: _options,
      metadata: widget.metadata,
    );
    var lines = encoded.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    // The ASS script and style header is the same for every song; the
    // preview starts at the events so the timed rows are what is shown.
    final events = lines.indexOf('[Events]');
    if (_format == LyricExportFormat.ass && events > 0) {
      lines = ['…（已省略脚本信息和样式）', ...lines.sublist(events)];
    }
    if (lines.length <= LyricExportDialog.previewLines) return lines.join('\n');
    return [
      ...lines.take(LyricExportDialog.previewLines),
      '…（共 ${lines.length} 行）',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exportedRows = widget.document.lines.length - _emptyRows;
    return LyricBatchEditDialogFrame(
      title: '导出歌词',
      confirmKey: const ValueKey('lyric_export_confirm'),
      confirmIcon: Icons.download_rounded,
      confirmLabel: '导出 .${_format.extension}',
      onConfirm: exportedRows == 0
          ? null
          : () => Navigator.of(
              context,
            ).pop(LyricExportRequest(format: _format, options: _options)),
      children: [
        for (final format in LyricExportFormat.values)
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              key: ValueKey('lyric_export_format_${format.name}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              selected: format == _format,
              leading: Icon(
                format == _format
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
              ),
              title: Text(format.label),
              subtitle: Text(format.description),
              onTap: () => setState(() => _format = format),
            ),
          ),
        if (_format == LyricExportFormat.lrc)
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              key: const ValueKey('lyric_export_end_markers'),
              contentPadding: EdgeInsets.zero,
              value: _endMarkers,
              onChanged: (value) => setState(() => _endMarkers = value),
              title: const Text('间奏处清屏'),
              subtitle: const Text('在较长停顿前写入行尾时间，播放器在间奏时不再停留上一句'),
            ),
          ),
        if (_format == LyricExportFormat.plainText)
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              key: const ValueKey('lyric_export_paragraphs'),
              contentPadding: EdgeInsets.zero,
              value: _paragraphs,
              onChanged: (value) => setState(() => _paragraphs = value),
              title: const Text('按间奏分段'),
              subtitle: const Text('停顿 4 秒以上时空一行'),
            ),
          ),
        if (_format == LyricExportFormat.ass)
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              key: const ValueKey('lyric_export_ass_lead_in'),
              contentPadding: EdgeInsets.zero,
              value: _assLeadIn,
              onChanged: (value) => setState(() => _assLeadIn = value),
              title: const Text('提前 1 秒显示下一句'),
              subtitle: const Text('不早于上一句结束；提前的部分不填色，便于演唱者预读'),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        if (_format.syllableTimed && _wordTimedRows == 0)
          const LyricBatchNote(
            '逐字时间按每行的开始、结束时间和字数比例估算，不是逐字识别结果；'
            '长音、拖腔处会有偏差，可在 Aegisub 等工具中细调。',
          )
        else if (_format.syllableTimed)
          LyricBatchNote(
            '$_wordTimedRows 行使用识别或逐字打点得到的真实逐字时间'
            '${_wordTimedRows < exportedRows ? '，其余行按字数比例估算' : ''}。',
          ),
        if (_format.timed && _timelineRows > 0)
          LyricBatchNote(
            '有 $_timelineRows 行时间轴存在问题（重叠、缺结束时间或顺序颠倒），'
            '导出后可能出现两句同时显示。建议先用「校对 → 检查时间轴」修复。',
            warning: true,
          ),
        if (_emptyRows > 0) LyricBatchNote('$_emptyRows 个空行不会导出。'),
        if (exportedRows == 0) const LyricBatchNote('没有可导出的歌词。', warning: true),
        const SizedBox(height: AppSpacing.sm),
        Text('预览', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Container(
          key: const ValueKey('lyric_export_preview'),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.bgBase,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          ),
          child: SelectableText(
            _preview(),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
