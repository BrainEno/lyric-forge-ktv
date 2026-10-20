import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/reference_alignment_restore_service.dart';

/// 备份恢复确认对话框；返回 true 表示用户点了"恢复并覆盖"。
Future<bool> showReferenceAlignmentBackupDialog(
  BuildContext context, {
  required ReferenceAlignmentBackupSummary summary,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => ReferenceAlignmentBackupDialog(summary: summary),
  );
  return confirmed ?? false;
}

/// 备份恢复的完整交互：探测备份 → 二次确认 → 生成恢复文档。
///
/// 取消或任一步失败返回 null 且不修改任何状态，失败原因用 SnackBar 说明；
/// 返回的文档不会自动保存，由调用方决定何时写盘。
Future<LyricDocument?> confirmReferenceAlignmentRestore(
  BuildContext context, {
  required LyricDocument document,
  ReferenceAlignmentRestoreService restoreService =
      const ReferenceAlignmentRestoreService(),
}) async {
  final probe = restoreService.probeBackup(document);
  if (probe is ReferenceAlignmentBackupAvailable) {
    final confirmed = await showReferenceAlignmentBackupDialog(
      context,
      summary: probe.summary,
    );
    if (confirmed && context.mounted) {
      final result = restoreService.restore(document);
      if (result is ReferenceAlignmentRestoreSuccess) return result.document;
      if (result is ReferenceAlignmentRestoreFailure) {
        _showRestoreIssue(context, result.issue);
      }
    }
    return null;
  }
  if (probe is ReferenceAlignmentBackupUnavailable) {
    _showRestoreIssue(context, probe.issue);
  }
  return null;
}

void _showRestoreIssue(
  BuildContext context,
  ReferenceAlignmentBackupIssue issue,
) {
  if (!context.mounted) return;
  final message = switch (issue) {
    ReferenceAlignmentBackupIssue.missing => '备份不可用：对齐前备份不存在或已被恢复，未修改当前歌词。',
    ReferenceAlignmentBackupIssue.invalidShape => '备份不可用：内容格式异常，未修改当前歌词。',
    ReferenceAlignmentBackupIssue.corruptDocument => '备份已损坏：无法解析歌词内容，未修改当前歌词。',
    ReferenceAlignmentBackupIssue.lineCountMismatch =>
      '备份不完整：记录行数与实际内容不一致，未修改当前歌词。',
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}

class ReferenceAlignmentBackupDialog extends StatelessWidget {
  final ReferenceAlignmentBackupSummary summary;

  const ReferenceAlignmentBackupDialog({super.key, required this.summary});

  String _sourceLabel() {
    return switch (summary.source) {
      'file' => '文件（file）',
      'paste' => '粘贴（paste）',
      _ => summary.source,
    };
  }

  String _createdAtLabel() {
    final created = summary.createdAt;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${created.year}-${two(created.month)}-${two(created.day)} '
        '${two(created.hour)}:${two(created.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final media = MediaQuery.of(context);
    final maxWidth = spec.isCompact ? 520.0 : 560.0;
    final maxHeight =
        (media.size.height -
                media.viewInsets.bottom -
                spec.pageGutter * 2 -
                160)
            .clamp(240.0, 520.0)
            .toDouble();

    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      insetPadding: EdgeInsets.all(spec.pageGutter),
      titlePadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        spec.pageGutter,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        0,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      actionsPadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        spec.pageGutter,
      ),
      title: const Text('恢复对齐前版本'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(20),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                  border: Border.all(color: AppColors.error.withAlpha(80)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        '将覆盖当前编辑中的歌词，恢复后不会自动保存。',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _SummaryRow(label: '备份时间', value: _createdAtLabel()),
              _SummaryRow(label: '来源', value: _sourceLabel()),
              if (summary.sourcePath != null)
                _SummaryRow(label: '来源文件', value: summary.sourcePath!),
              _SummaryRow(label: '格式', value: summary.format),
              _SummaryRow(label: '行数', value: '${summary.lineCount} 行'),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.pureWhite,
            minimumSize: const Size(0, 48),
          ),
          icon: const Icon(Icons.history_rounded, size: 18),
          label: const Text('恢复并覆盖'),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
