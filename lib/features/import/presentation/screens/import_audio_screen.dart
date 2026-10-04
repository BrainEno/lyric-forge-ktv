import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/presentation/widgets/transcription_queue_panel.dart';

/// Batch import entry point.
///
/// Users may select many files or an entire folder. Selection itself is cheap;
/// actual project creation and transcription are handled by the persistent
/// background queue so closing this page does not stop processing.
class ImportAudioScreen extends StatefulWidget {
  const ImportAudioScreen({super.key});

  @override
  State<ImportAudioScreen> createState() => _ImportAudioScreenState();
}

class _ImportAudioScreenState extends State<ImportAudioScreen> {
  final List<String> _selectedPaths = <String>[];
  bool _isPicking = false;
  bool _isEnqueueing = false;

  Future<void> _pickFiles() async {
    await _runPicker(() async {
      final paths = await ServiceLocatorGlobal.I.audioLibraryImportService
          .pickAudioFiles();
      _mergeSelection(paths);
    });
  }

  Future<void> _pickDirectory() async {
    await _runPicker(() async {
      final paths = await ServiceLocatorGlobal.I.audioLibraryImportService
          .pickAudioDirectory();
      _mergeSelection(paths);
      if (mounted && paths.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所选文件夹里没有找到支持的音频文件')),
        );
      }
    });
  }

  Future<void> _runPicker(Future<void> Function() action) async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('无法读取音频文件：$error'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _mergeSelection(Iterable<String> paths) {
    if (!mounted) return;
    setState(() {
      final existing = _selectedPaths.toSet();
      for (final path in paths) {
        if (existing.add(path)) _selectedPaths.add(path);
      }
    });
  }

  Future<void> _enqueue() async {
    if (_selectedPaths.isEmpty || _isEnqueueing) return;
    setState(() => _isEnqueueing = true);
    try {
      final added = await ServiceLocatorGlobal.I.transcriptionQueue
          .enqueuePaths(_selectedPaths);
      if (!mounted) return;
      setState(_selectedPaths.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added == 0
                ? '这些音频已经在队列中，未重复添加'
                : '已将 $added 首音频加入后台解析队列',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isEnqueueing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('导入与解析'),
        backgroundColor: AppColors.bgBase,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              '批量导入音频',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '可一次选择多首歌曲，或直接选择整个音乐文件夹。加入队列后会逐首创建工程、识别歌词；单首失败不会阻塞后面的歌曲。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: _isPicking ? null : _pickFiles,
                  icon: const Icon(Icons.audio_file_outlined),
                  label: const Text('选择音频'),
                ),
                OutlinedButton.icon(
                  onPressed: _isPicking ? null : _pickDirectory,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('选择文件夹'),
                ),
              ],
            ),
            if (_selectedPaths.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _SelectionPanel(
                paths: _selectedPaths,
                onRemove: (path) {
                  setState(() => _selectedPaths.remove(path));
                },
                onClear: () => setState(_selectedPaths.clear),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _isEnqueueing ? null : _enqueue,
                icon: _isEnqueueing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.pureWhite,
                        ),
                      )
                    : const Icon(Icons.playlist_add),
                label: Text(
                  _isEnqueueing
                      ? '正在加入...'
                      : '加入后台解析队列（${_selectedPaths.length}）',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            const TranscriptionQueuePanel(),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SelectionPanel extends StatelessWidget {
  final List<String> paths;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  const _SelectionPanel({
    required this.paths,
    required this.onRemove,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    const previewLimit = 50;
    final preview = paths.take(previewLimit).toList(growable: false);
    final hiddenCount = paths.length - preview.length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '已选择 ${paths.length} 首',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(onPressed: onClear, child: const Text('清空')),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final path in preview)
            _SelectedPathTile(path: path, onRemove: () => onRemove(path)),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '还有 $hiddenCount 首未展开显示，仍会全部加入队列',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectedPathTile extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;

  const _SelectedPathTile({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final fileName = path.split(Platform.pathSeparator).last;
    final size = file.existsSync() ? file.lengthSync() : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          const Icon(Icons.music_note, size: 18, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatSize(size),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: '移除',
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
