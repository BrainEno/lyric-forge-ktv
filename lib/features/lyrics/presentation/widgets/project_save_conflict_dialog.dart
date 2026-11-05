import 'package:flutter/material.dart';

/// Resolution explicitly chosen after an optimistic project save detects a
/// newer persisted version.
enum ProjectSaveConflictChoice { keepEditing, reloadLatest, overwriteLatest }

/// Explains that the attempted save was rejected and leaves the choice to the
/// user instead of silently discarding either set of lyrics.
Future<ProjectSaveConflictChoice> showProjectSaveConflictDialog(
  BuildContext context, {
  required int latestRevision,
}) async {
  final choice = await showDialog<ProjectSaveConflictChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('工程已在其他位置更新'),
      content: Text(
        '本次保存未应用。工程当前版本为 $latestRevision；你的编辑仍保留在此页面。'
        '可以继续编辑、重新载入最新版（放弃当前修改），或明确选择用当前歌词覆盖最新版。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(ProjectSaveConflictChoice.keepEditing),
          child: const Text('继续编辑'),
        ),
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(ProjectSaveConflictChoice.reloadLatest),
          child: const Text('重新载入最新版'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(ProjectSaveConflictChoice.overwriteLatest),
          child: const Text('用当前歌词覆盖最新版'),
        ),
      ],
    ),
  );
  return choice ?? ProjectSaveConflictChoice.keepEditing;
}
