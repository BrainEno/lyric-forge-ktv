import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/services/project_deletion_service.dart';

/// `12.3 MB`-style size for the deletion dialog.
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

/// What the working folders hold, e.g.
/// `识别文件和分离的音轨（120 MB），含 2 段演唱录音`.
String projectFilesLabel(ProjectDeletionCheck check) {
  final size = projectFileSizeLabel(check.removableBytes);
  final takes = check.recordings > 0 ? '，含 ${check.recordings} 段演唱录音' : '';
  return '识别文件和分离的音轨（$size）$takes';
}

/// Asks before deleting [projects] (D-063). Returns whether to remove their
/// working folders too, or null when the user keeps them.
///
/// [checks] are the projects' [ProjectDeletionService.check] results, in the
/// same order.
Future<bool?> confirmProjectDeletion(
  BuildContext context, {
  required List<ProjectManifest> projects,
  required List<ProjectDeletionCheck> checks,
  String? keepNote,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _ProjectDeleteDialog(
      projects: projects,
      checks: checks,
      keepNote: keepNote,
    ),
  );
}

class _ProjectDeleteDialog extends StatefulWidget {
  const _ProjectDeleteDialog({
    required this.projects,
    required this.checks,
    this.keepNote,
  });

  final List<ProjectManifest> projects;
  final List<ProjectDeletionCheck> checks;
  final String? keepNote;

  @override
  State<_ProjectDeleteDialog> createState() => _ProjectDeleteDialogState();
}

class _ProjectDeleteDialogState extends State<_ProjectDeleteDialog> {
  bool _removeFiles = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final single = widget.projects.length == 1;
    final withFiles = widget.checks.where((check) => check.hasFiles).toList();
    final bytes = withFiles.fold<int>(0, (sum, c) => sum + c.removableBytes);
    final recordings = withFiles.fold<int>(0, (sum, c) => sum + c.recordings);
    final filesLabel = projectFilesLabel(
      ProjectDeletionCheck(removableBytes: bytes, recordings: recordings),
    );
    final hasLyrics = widget.projects.any((project) => project.hasLyrics);

    return AlertDialog(
      key: const ValueKey('project_delete_dialog'),
      title: Text(
        single
            ? '删除工程“${widget.projects.single.name}”？'
            : '删除 ${widget.projects.length} 个工程？',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.keepNote != null) ...[
              Text(widget.keepNote!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (!single)
              for (final project in widget.projects.take(8))
                Text(
                  '· ${project.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            if (widget.projects.length > 8)
              Text(
                '…等 ${widget.projects.length} 个',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            if (!single) const SizedBox(height: AppSpacing.sm),
            Text(
              hasLyrics
                  ? '工程里的歌词、识别结果和校对记录会一起删除，不能撤销。歌曲的音频文件不会删除。'
                  : '工程会被删除，不能撤销。歌曲的音频文件不会删除。',
              style: theme.textTheme.bodyMedium,
            ),
            if (withFiles.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                key: const ValueKey('project_delete_files'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _removeFiles,
                onChanged: (value) =>
                    setState(() => _removeFiles = value ?? true),
                title: const Text('同时删除工程文件'),
                subtitle: Text(filesLabel),
              ),
              if (recordings > 0 && _removeFiles)
                Text(
                  '演唱录音也会删除。',
                  key: const ValueKey('project_delete_recordings_warning'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('project_delete_cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('project_delete_confirm'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () =>
              Navigator.pop(context, withFiles.isNotEmpty && _removeFiles),
          child: const Text('删除'),
        ),
      ],
    );
  }
}
