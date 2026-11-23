import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/services/project_deletion_service.dart';
import '../widgets/project_delete_dialog.dart';
import '../widgets/project_deletion_flow.dart';

/// 最近删除: deleted projects, restorable for
/// [ProjectDeletionService.retention] (D-064).
class ProjectTrashScreen extends StatefulWidget {
  const ProjectTrashScreen({
    super.key,
    required this.service,
    this.now = DateTime.now,
  });

  final ProjectDeletionService service;
  final DateTime Function() now;

  @override
  State<ProjectTrashScreen> createState() => _ProjectTrashScreenState();
}

class _ProjectTrashScreenState extends State<ProjectTrashScreen> {
  List<TrashedProject>? _entries;
  Object? _error;
  bool _busy = false;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.service.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.service.trashed();
      if (mounted) {
        setState(() {
          _entries = entries;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final message = await action();
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('操作失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _restore(TrashedProject entry) =>
      _run(() => restoreDeletedProjects(widget.service, [entry.id]));

  Future<void> _purge(TrashedProject entry) => _run(() async {
    final confirmed = await _confirm(
      title: '彻底删除“${entry.project.name}”？',
      body: entry.hasFiles
          ? '工程和它的文件（${projectFileSizeLabel(entry.bytes)}）会彻底删除，不能恢复。'
          : '工程会彻底删除，不能恢复。',
    );
    if (!confirmed) return null;
    await widget.service.purge(entry.id);
    return '已彻底删除';
  });

  Future<void> _purgeAll(int count) => _run(() async {
    final confirmed = await _confirm(
      title: '清空“最近删除”？',
      body: '$count 个工程会彻底删除，不能恢复。',
    );
    if (!confirmed) return null;
    final purged = await widget.service.purgeAll();
    return '已彻底删除 $purged 个工程';
  });

  Future<bool> _confirm({required String title, required String body}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('project_trash_confirm_dialog'),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('project_trash_confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final entries = _entries;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
        title: const Text('最近删除'),
        actions: [
          if (entries != null && entries.isNotEmpty)
            TextButton(
              key: const ValueKey('project_trash_empty'),
              onPressed: _busy ? null : () => _purgeAll(entries.length),
              child: const Text('清空'),
            ),
          SizedBox(width: spec.isCompact ? AppSpacing.xs : AppSpacing.sm),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: spec.contentMaxWidth),
          child: _body(spec, entries),
        ),
      ),
    );
  }

  Widget _body(AppLayoutSpec spec, List<TrashedProject>? entries) {
    final theme = Theme.of(context);
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('“最近删除”加载失败'),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final days = ProjectDeletionService.retention.inDays;
    final intro = Text(
      '删除的工程会在这里保留 $days 天，可以恢复；到期后自动彻底删除。',
      style: theme.textTheme.bodySmall?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
    if (entries.isEmpty) {
      return ListView(
        padding: EdgeInsets.all(spec.pageGutter),
        children: [
          intro,
          const SizedBox(height: AppSpacing.xl),
          Icon(
            Icons.delete_outline_rounded,
            size: AppSpacing.iconSizeLarge,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Center(
            key: ValueKey('project_trash_empty_state'),
            child: Text('“最近删除”是空的'),
          ),
        ],
      );
    }
    final now = widget.now();
    return ListView(
      padding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        AppSpacing.xl,
      ),
      children: [
        intro,
        const SizedBox(height: AppSpacing.md),
        for (final entry in entries)
          _TrashRow(
            key: ValueKey('project_trash_row_${entry.id}'),
            entry: entry,
            now: now,
            busy: _busy,
            onRestore: () => _restore(entry),
            onPurge: () => _purge(entry),
          ),
      ],
    );
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({
    super.key,
    required this.entry,
    required this.now,
    required this.busy,
    required this.onRestore,
    required this.onPurge,
  });

  final TrashedProject entry;
  final DateTime now;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = entry.project;
    final deleted = entry.deletedAt;
    final left = entry.daysLeft(now);
    final lines = project.lyricDocument?.lines.length ?? 0;
    final details = [
      if (project.artist?.trim().isNotEmpty ?? false) project.artist!.trim(),
      if (lines > 0) '$lines 行歌词',
      '${deleted.month}月${deleted.day}日删除',
      if (entry.hasFiles) '含工程文件 ${projectFileSizeLabel(entry.bytes)}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      color: AppColors.bgElevated,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              details,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            Text(
              '还剩 $left 天',
              style: theme.textTheme.labelSmall?.copyWith(
                color: left <= 3 ? AppColors.warning : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                FilledButton.tonalIcon(
                  key: ValueKey('project_trash_restore_${entry.id}'),
                  onPressed: busy ? null : onRestore,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('恢复'),
                ),
                TextButton(
                  key: ValueKey('project_trash_purge_${entry.id}'),
                  onPressed: busy ? null : onPurge,
                  child: const Text('彻底删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
