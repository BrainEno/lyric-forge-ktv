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
        title: const Text('批量导入'),
        backgroundColor: AppColors.bgBase,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.md,
                AppSpacing.screenPadding,
                AppSpacing.xxxl,
              ),
              children: [
                const _ImportHero(),
                const SizedBox(height: AppSpacing.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 680;
                    final chooseFiles = _ImportActionCard(
                      icon: Icons.library_music_outlined,
                      title: '选择音频',
                      subtitle: '一次选择多首歌曲，适合从不同位置挑选文件',
                      actionLabel: '选择文件',
                      enabled: !_isPicking,
                      onTap: _pickFiles,
                    );
                    final chooseFolder = _ImportActionCard(
                      icon: Icons.folder_copy_outlined,
                      title: '扫描音乐文件夹',
                      subtitle: '递归查找整个文件夹中的支持格式，适合整批导入',
                      actionLabel: '选择文件夹',
                      enabled: !_isPicking,
                      onTap: _pickDirectory,
                    );

                    if (compact) {
                      return Column(
                        children: [
                          chooseFiles,
                          const SizedBox(height: AppSpacing.sm),
                          chooseFolder,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: chooseFiles),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: chooseFolder),
                      ],
                    );
                  },
                ),
                if (_isPicking) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const LinearProgressIndicator(minHeight: 2),
                ],
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
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
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
                          : const Icon(Icons.playlist_add_rounded),
                      label: Text(
                        _isEnqueueing
                            ? '正在加入队列...'
                            : '加入后台解析队列 · ${_selectedPaths.length} 首',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                const TranscriptionQueuePanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportHero extends StatelessWidget {
  const _ImportHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.accent.withAlpha(24),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.accent,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '批量导入与歌词解析',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '选择歌曲后交给后台队列逐首创建工程和生成歌词。离开此页面不会中断任务，单首失败也不会卡住后面的歌曲。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _FeaturePill(icon: Icons.queue_music_rounded, label: '逐首处理'),
                    _FeaturePill(icon: Icons.pause_rounded, label: '可暂停 / 恢复'),
                    _FeaturePill(icon: Icons.save_outlined, label: '进度持久化'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _ImportActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final bool enabled;
  final VoidCallback onTap;

  const _ImportActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        hoverColor: AppColors.hoverOverlay,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            border: Border.all(color: AppColors.borderMuted),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: Icon(
                  icon,
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textDisabled,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    actionLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                ],
              ),
            ],
          ),
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
    const previewLimit = 12;
    final preview = paths.take(previewLimit).toList(growable: false);
    final hiddenCount = paths.length - preview.length;
    final totalBytes = paths.fold<int>(0, (total, path) {
      final file = File(path);
      return total + (file.existsSync() ? file.lengthSync() : 0);
    });

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.playlist_add_check_rounded,
                size: 20,
                color: AppColors.accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '准备加入队列',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      '${paths.length} 首 · ${_formatBytes(totalBytes)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onClear, child: const Text('清空')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgBase,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            child: Column(
              children: [
                for (var index = 0; index < preview.length; index++) ...[
                  _SelectedPathTile(
                    path: preview[index],
                    onRemove: () => onRemove(preview[index]),
                  ),
                  if (index != preview.length - 1)
                    const Divider(
                      height: 1,
                      indent: 44,
                      color: AppColors.borderMuted,
                    ),
                ],
              ],
            ),
          ),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '另外 $hiddenCount 首已选中，为保持页面紧凑暂不展开；加入队列时会全部处理。',
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
      padding: const EdgeInsets.only(
        left: AppSpacing.sm,
        top: 6,
        bottom: 6,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _formatBytes(size),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: '移除',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 17),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
