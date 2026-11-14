import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/repositories/local_store_integrity.dart';

/// User-facing description of a library/collection failure.
///
/// A write-protected store (#439) is explained in plain Chinese with the next
/// step; every other error keeps its own text so long-running failures are not
/// hidden behind a generic message.
String describeLocalLibraryError(Object error) {
  if (error is LocalStoreIncompleteException) {
    final issue = error.issue;
    return '${localStoreDisplayName(issue.kind)}文件有 '
        '${issue.unreadableRecords} 条记录无法读取，为保护原文件已暂停保存修改。'
        '请在“音乐库”页面使用“保留原文件并修复”。';
  }
  return '$error';
}

String localStoreDisplayName(LocalStoreKind kind) => switch (kind) {
  LocalStoreKind.mediaLibrary => '音乐库',
  LocalStoreKind.collections => '收藏与播放列表',
};

/// Asks before a partly readable store is rewritten. Returns `true` only when
/// the user explicitly confirmed.
Future<bool> confirmLocalStoreRepair(
  BuildContext context,
  LocalStoreLoadIssue issue,
) async {
  final name = localStoreDisplayName(issue.kind);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('修复$name文件？'),
      content: SingleChildScrollView(
        child: Text(
          '会先把原文件完整复制为同一文件夹中的 .incomplete 副本并校验，'
          '然后只保留可读取的 ${issue.readableRecords} 条记录，'
          '放弃无法读取的 ${issue.unreadableRecords} 条记录，并恢复保存。\n\n'
          '原文件副本不会被自动删除，可以稍后手动检查或恢复。\n'
          '原文件：${issue.storePath}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('保留副本并修复'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Explains which local stores loaded only partly and offers the repair.
class LocalStoreIntegrityBanner extends StatelessWidget {
  const LocalStoreIntegrityBanner({
    super.key,
    required this.issues,
    required this.onRepair,
    this.busy = false,
  });

  final List<LocalStoreLoadIssue> issues;
  final ValueChanged<LocalStoreLoadIssue> onRepair;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const ValueKey('local_store_integrity_banner'),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final issue in issues) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${localStoreDisplayName(issue.kind)}文件有 '
                          '${issue.unreadableRecords} 条记录无法读取',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '已显示可读取的 ${issue.readableRecords} 条记录；'
                          '为避免覆盖原文件，相关修改暂不保存。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            key: ValueKey(
                              'repair_local_store_${issue.kind.name}',
                            ),
                            onPressed: busy ? null : () => onRepair(issue),
                            icon: const Icon(Icons.build_rounded, size: 18),
                            label: const Text('保留原文件并修复'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (issue != issues.last) const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}
