import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/diagnostics/app_diagnostics.dart';
import '../../../../core/diagnostics/diagnostics_report.dart';
import '../../../../core/diagnostics/operation_timings.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// Saves [bytes] under a user-chosen name; returns the path, or null when the
/// user cancelled.
typedef DiagnosticsFileSaver =
    Future<String?> Function({
      required String fileName,
      required Uint8List bytes,
    });

Future<String?> _saveWithFilePicker({
  required String fileName,
  required Uint8List bytes,
}) => FilePicker.platform.saveFile(
  dialogTitle: '导出诊断包',
  fileName: fileName,
  type: FileType.custom,
  allowedExtensions: const ['txt'],
  bytes: bytes,
);

/// Human labels for the operations [OperationTimings] records.
const Map<String, String> diagnosticsOperationLabels = {
  'transcription.transcribe': '歌词识别',
  'ktv.startRecording': 'KTV 开始录音',
  'ktv.stopRecording': 'KTV 结束录音',
  'ktv.exportMix': 'KTV 导出混音',
};

/// "诊断与日志": local log files, crash records, operation timings and a
/// redacted report the user can export or copy when asking for help.
class DiagnosticsSettingsCard extends StatefulWidget {
  final AppDiagnostics diagnostics;
  final DiagnosticsFileSaver saveFile;

  const DiagnosticsSettingsCard({
    super.key,
    required this.diagnostics,
    this.saveFile = _saveWithFilePicker,
  });

  @override
  State<DiagnosticsSettingsCard> createState() =>
      _DiagnosticsSettingsCardState();
}

enum _Busy { none, export, copy, clear }

class _DiagnosticsSettingsCardState extends State<DiagnosticsSettingsCard> {
  DiagnosticsSummary? _summary;
  _Busy _busy = _Busy.none;
  String? _message;
  bool _messageIsError = false;

  AppDiagnostics get _diagnostics => widget.diagnostics;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final summary = await _diagnostics.summary();
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (_) {
      // The card still works without the summary line.
    }
  }

  void _show(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  Future<void> _run(_Busy kind, Future<void> Function() action) async {
    if (_busy != _Busy.none) return;
    setState(() {
      _busy = kind;
      _message = null;
    });
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
      unawaited(_refresh());
    }
  }

  Future<void> _export() => _run(_Busy.export, () async {
    try {
      final report = await _diagnostics.buildReport();
      final bytes = Uint8List.fromList(utf8.encode(report.toText()));
      final path = await widget.saveFile(
        fileName: report.suggestedFileName,
        bytes: bytes,
      );
      if (path == null) return;
      _show('诊断包已导出：$path');
    } catch (error) {
      _diagnostics.logger.warning(
        'diagnostics',
        'Diagnostics export failed',
        error: error,
      );
      _show('导出失败：$error', error: true);
    }
  });

  Future<void> _copy() => _run(_Busy.copy, () async {
    try {
      final report = await _diagnostics.buildReport();
      // The clipboard copy is for pasting into an issue: text only.
      await Clipboard.setData(
        ClipboardData(text: report.toText(includeJson: false)),
      );
      _show('诊断信息已复制，可直接粘贴到问题反馈中');
    } catch (error) {
      _show('复制失败：$error', error: true);
    }
  });

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除诊断记录？'),
        content: const Text('将删除本机保存的日志文件、崩溃记录和本次运行的耗时数据。歌词、音频和工程不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(_Busy.clear, () async {
      try {
        await _diagnostics.clearAll();
        _show('诊断记录已清除');
      } catch (error) {
        _show('清除失败：$error', error: true);
      }
    });
  }

  Future<void> _setVerbose(bool value) async {
    await _diagnostics.setVerbose(value);
    await _refresh();
  }

  Future<void> _setStoreCrashes(bool value) async {
    await _diagnostics.setStoreCrashes(value);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _summary;
    final busy = _busy != _Busy.none;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.monitor_heart_outlined,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '诊断与日志',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '遇到问题时导出诊断包并附在反馈里。${DiagnosticsReport.privacyNotice}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            summary == null ? '正在读取诊断记录…' : _summaryLine(summary),
            key: const ValueKey('diagnostics-summary'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            key: const ValueKey('diagnostics-verbose'),
            contentPadding: EdgeInsets.zero,
            title: const Text('详细日志'),
            subtitle: const Text('额外记录调试信息，排查问题时开启，日志会增长得更快'),
            value: summary?.verbose ?? _diagnostics.verbose,
            onChanged: busy ? null : _setVerbose,
          ),
          SwitchListTile(
            key: const ValueKey('diagnostics-store-crashes'),
            contentPadding: EdgeInsets.zero,
            title: const Text('保存崩溃记录'),
            subtitle: const Text('应用出现未处理的错误时在本机保留摘要，最多 10 条'),
            value: summary?.storeCrashes ?? _diagnostics.storeCrashes,
            onChanged: busy ? null : _setStoreCrashes,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                key: const ValueKey('diagnostics-export'),
                onPressed: busy ? null : _export,
                icon: _busyIcon(_Busy.export, Icons.save_alt),
                label: const Text('导出诊断包'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('diagnostics-copy'),
                onPressed: busy ? null : _copy,
                icon: _busyIcon(_Busy.copy, Icons.copy_all_outlined),
                label: const Text('复制诊断信息'),
              ),
              TextButton.icon(
                key: const ValueKey('diagnostics-clear'),
                onPressed: busy ? null : _clear,
                icon: _busyIcon(_Busy.clear, Icons.delete_outline),
                label: const Text('清除记录'),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _message!,
              key: const ValueKey('diagnostics-message'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _messageIsError
                    ? theme.colorScheme.error
                    : AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _TimingsPanel(timings: _diagnostics.timings),
        ],
      ),
    );
  }

  Widget _busyIcon(_Busy kind, IconData icon) => _busy == kind
      ? const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(icon);

  static String _summaryLine(DiagnosticsSummary summary) {
    final parts = <String>[
      '日志 ${formatDiagnosticsBytes(summary.logFileBytes)}',
    ];
    if (summary.crashCount == 0) {
      parts.add('没有崩溃记录');
    } else {
      final last = summary.lastCrashAt?.toLocal();
      parts.add(
        '${summary.crashCount} 条崩溃记录'
        '${last == null ? '' : '（最近 ${_formatDate(last)}）'}',
      );
    }
    return parts.join(' · ');
  }

  static String _formatDate(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

/// Current-run timing summaries, updated whenever a measured operation ends.
class _TimingsPanel extends StatelessWidget {
  final OperationTimings timings;

  const _TimingsPanel({required this.timings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<void>(
      stream: timings.changes,
      builder: (context, _) {
        final operations = timings.operations;
        return ExpansionTile(
          key: const ValueKey('diagnostics-timings'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
          title: Text('操作耗时（本次运行）', style: theme.textTheme.titleSmall),
          subtitle: Text(
            operations.isEmpty
                ? '识别歌词或录制 KTV 后在这里查看耗时'
                : '中位数 / 最长 / 最近一次；实时倍率 = 处理时长 ÷ 歌曲时长',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          children: [
            for (final operation in operations)
              if (timings.summarize(operation) case final summary?)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    diagnosticsOperationLabels[operation] ?? operation,
                  ),
                  subtitle: Text(describeOperationSummary(summary)),
                ),
          ],
        );
      },
    );
  }
}

/// `3 次 · 中位 12.4 秒 · 最长 15.0 秒 · 最近 11.2 秒 · 实时倍率 0.41 · 失败 1`
String describeOperationSummary(OperationSummary summary) {
  final parts = <String>[
    '${summary.count} 次',
    '中位 ${formatDiagnosticsDuration(summary.median)}',
    '最长 ${formatDiagnosticsDuration(summary.max)}',
    '最近 ${formatDiagnosticsDuration(summary.last)}',
  ];
  final rtf = summary.medianRealTimeFactor;
  if (rtf != null) parts.add('实时倍率 ${rtf.toStringAsFixed(2)}');
  if (summary.failures > 0) parts.add('失败 ${summary.failures}');
  return parts.join(' · ');
}

String formatDiagnosticsDuration(Duration duration) {
  final ms = duration.inMilliseconds;
  if (ms < 1000) return '$ms 毫秒';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)} 秒';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes 分 $seconds 秒';
}

String formatDiagnosticsBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
