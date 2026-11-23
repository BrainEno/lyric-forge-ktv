import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/services/project_deletion_service.dart';

/// `12.3 MB`-style size.
String projectFileSizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

/// Asks before deleting several [projects] at once (D-063, D-064); true to
/// go ahead.
Future<bool> confirmProjectDeletion(
  BuildContext context, {
  required List<ProjectManifest> projects,
  String? keepNote,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _ProjectDeleteDialog(projects: projects, keepNote: keepNote),
  );
  return confirmed ?? false;
}

class _ProjectDeleteDialog extends StatelessWidget {
  const _ProjectDeleteDialog({required this.projects, this.keepNote});

  final List<ProjectManifest> projects;
  final String? keepNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final single = projects.length == 1;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    final days = ProjectDeletionService.retention.inDays;
    return AlertDialog(
      key: const ValueKey('project_delete_dialog'),
      title: Text(
        single
            ? '删除工程“${projects.single.name}”？'
            : '删除 ${projects.length} 个工程？',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (keepNote != null) ...[
              Text(keepNote!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (!single) ...[
              for (final project in projects.take(8))
                Text(
                  '· ${project.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: secondary,
                ),
              if (projects.length > 8)
                Text('…等 ${projects.length} 个', style: secondary),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              '删除的工程会先放进“最近删除”，$days 天内可以恢复，之后自动彻底删除。'
              '歌曲的音频文件不会删除。',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('project_delete_cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('project_delete_confirm'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    );
  }
}
