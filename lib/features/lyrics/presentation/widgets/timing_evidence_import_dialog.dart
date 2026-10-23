import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../project/domain/models/lyric_document.dart';

/// Imports an independent timed ASR document as evidence, never as lyrics to
/// apply directly. Confidence values are preserved from the source JSON.
Future<LyricDocument?> showTimingEvidenceImportDialog(
  BuildContext context,
) {
  return showDialog<LyricDocument>(
    context: context,
    builder: (_) => const _TimingEvidenceImportDialog(),
  );
}

class _TimingEvidenceImportDialog extends StatefulWidget {
  const _TimingEvidenceImportDialog();

  @override
  State<_TimingEvidenceImportDialog> createState() =>
      _TimingEvidenceImportDialogState();
}

class _TimingEvidenceImportDialogState
    extends State<_TimingEvidenceImportDialog> {
  String? _path;
  String? _error;
  bool _busy = false;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择独立 ASR 时间证据 JSON',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty || !mounted) return;
      setState(() {
        _path = path;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '无法打开文件选择器：$error');
    }
  }

  Future<void> _import() async {
    final path = _path;
    if (path == null) {
      setState(() => _error = '请选择独立 ASR 导出的 JSON 文件');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final decoded = jsonDecode(await File(path).readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON 顶层必须是对象');
      }
      final root = decoded['lyricDocument'] is Map<String, dynamic>
          ? decoded['lyricDocument'] as Map<String, dynamic>
          : decoded;
      if (root['lines'] is! List) {
        throw const FormatException('找不到 lines 数组；请选择歌词文档或工程 manifest JSON');
      }
      final document = LyricDocument.fromJson(root);
      if (document.lines.isEmpty) {
        throw const FormatException('时间证据没有歌词行');
      }
      for (var index = 0; index < document.lines.length; index++) {
        final line = document.lines[index];
        if (line.text.trim().isEmpty ||
            line.startTime.isNegative ||
            line.endTime <= line.startTime ||
            line.confidence < 0 ||
            line.confidence > 100) {
          throw FormatException('第 ${index + 1} 行的文字、时间或置信度无效');
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(document);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '无法导入时间证据：$error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入独立 ASR 时间证据'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择另一轮 ASR 生成的 Lyric Forge JSON 文档或工程 manifest。'
              '系统只使用其中的文字、时间戳和置信度来提出校时建议；'
              '不会直接覆盖当前歌词，也不会把参考歌词时间当作证据。',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(
                _path == null
                    ? '选择 JSON 文件'
                    : _path!.split(Platform.pathSeparator).last,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('跳过校时'),
        ),
        FilledButton(
          onPressed: _busy ? null : _import,
          child: Text(_busy ? '正在读取…' : '导入并生成校时建议'),
        ),
      ],
    );
  }
}
