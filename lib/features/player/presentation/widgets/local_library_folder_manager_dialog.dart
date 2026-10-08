import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/services/audio_library_import_service.dart';

Future<void> showLocalLibraryFolderManagerDialog(
  BuildContext context, {
  required LocalMediaLibraryRepository library,
  required AudioLibraryImportService importer,
  required Future<void> Function() onLibraryChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _LocalLibraryFolderManagerDialog(
      library: library,
      importer: importer,
      onLibraryChanged: onLibraryChanged,
    ),
  );
}

class _LocalLibraryFolderManagerDialog extends StatefulWidget {
  final LocalMediaLibraryRepository library;
  final AudioLibraryImportService importer;
  final Future<void> Function() onLibraryChanged;

  const _LocalLibraryFolderManagerDialog({
    required this.library,
    required this.importer,
    required this.onLibraryChanged,
  });

  @override
  State<_LocalLibraryFolderManagerDialog> createState() =>
      _LocalLibraryFolderManagerDialogState();
}

class _LocalLibraryFolderManagerDialogState
    extends State<_LocalLibraryFolderManagerDialog> {
  List<String> _roots = const [];
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    try {
      final roots = await widget.library.getRoots();
      if (!mounted) return;
      setState(() {
        _roots = roots;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取音乐文件夹失败：$error';
      });
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _addFolder() => _run(() async {
        final selection = await widget.importer.pickAudioDirectorySelection();
        if (selection == null) return;
        // Production importer callbacks already persist root + discovered files.
        // Keep this fallback for alternate importer implementations.
        if (selection.rootPath.trim().isNotEmpty &&
            !(await widget.library.getRoots()).any(
              (value) => _sameDirectory(value, selection.rootPath),
            )) {
          await widget.library.addRoot(selection.rootPath);
          if (selection.audioPaths.isNotEmpty) {
            await widget.library.addPaths(selection.audioPaths);
          }
        }
        await _loadRoots();
        await widget.onLibraryChanged();
      });

  Future<void> _syncNow() => _run(() async {
        await widget.library.refreshFromRoots(widget.importer.supportedExtensions);
        await widget.onLibraryChanged();
        await _loadRoots();
      });

  Future<void> _removeRoot(String root) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('停止监控这个文件夹？'),
        content: Text(
          'Elysium Player 将不再自动扫描：\n\n$root\n\n'
          '磁盘上的音乐文件不会被删除，已经加入音乐库的歌曲也会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('停止监控'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.library.removeRoot(root);
      await _loadRoots();
      await widget.onLibraryChanged();
    });
  }

  bool _sameDirectory(String a, String b) {
    final left = Directory(a).absolute.path;
    final right = Directory(b).absolute.path;
    return Platform.isWindows
        ? left.toLowerCase() == right.toLowerCase()
        : left == right;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.folder_special_rounded),
          SizedBox(width: AppSpacing.sm),
          Text('音乐文件夹'),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '这些文件夹会在应用启动和回到前台时自动扫描。自动扫描会限频，避免大型音乐库反复占用磁盘。',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_working) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _roots.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                          child: Center(
                            child: Text(
                              '还没有受监控的音乐文件夹',
                              style: TextStyle(color: AppColors.textTertiary),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _roots.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final root = _roots[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.folder_rounded),
                              title: Text(
                                root,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                tooltip: '停止监控',
                                onPressed: _working ? null : () => _removeRoot(root),
                                icon: const Icon(Icons.remove_circle_outline_rounded),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        OutlinedButton.icon(
          onPressed: _working ? null : _syncNow,
          icon: const Icon(Icons.sync_rounded),
          label: const Text('立即同步'),
        ),
        FilledButton.icon(
          onPressed: _working ? null : _addFolder,
          icon: const Icon(Icons.create_new_folder_rounded),
          label: const Text('添加文件夹'),
        ),
      ],
    );
  }
}
