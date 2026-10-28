import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/character_diff_service.dart';

Future<void> showReferenceAlignmentResultComparison(
  BuildContext context, {
  required LyricDocument before,
  required LyricDocument after,
  required ValueChanged<int>? onPreviewLine,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final spec = AppResponsive.of(sheetContext);
      return FractionallySizedBox(
        heightFactor: spec.isShort ? 0.98 : 0.90,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Material(
              color: AppColors.bgElevated,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _AlignmentComparisonSheet(
                before: before,
                after: after,
                onPreviewLine: onPreviewLine,
              ),
            ),
          ),
        ),
      );
    },
  );
}

enum _ChangeKind { corrected, inserted, removed }

class _LineChange {
  final _ChangeKind kind;
  final int? beforeIndex;
  final int? afterIndex;
  final LyricLine? beforeLine;
  final LyricLine? afterLine;

  const _LineChange({
    required this.kind,
    required this.beforeIndex,
    required this.afterIndex,
    required this.beforeLine,
    required this.afterLine,
  });
}

class _AlignmentComparisonSheet extends StatelessWidget {
  static const _diffService = CharacterDiffService();

  final LyricDocument before;
  final LyricDocument after;
  final ValueChanged<int>? onPreviewLine;

  const _AlignmentComparisonSheet({
    required this.before,
    required this.after,
    required this.onPreviewLine,
  });

  String _key(LyricLine line, int index) =>
      line.id == null ? 'legacy-index:$index' : 'line-id:${line.id}';

  List<_LineChange> _changes() {
    final remainingOld = <String, int>{};
    for (var i = 0; i < before.lines.length; i++) {
      remainingOld[_key(before.lines[i], i)] = i;
    }
    final changes = <_LineChange>[];
    for (var i = 0; i < after.lines.length; i++) {
      final line = after.lines[i];
      final oldIndex = remainingOld.remove(_key(line, i));
      if (oldIndex == null) {
        changes.add(
          _LineChange(
            kind: _ChangeKind.inserted,
            beforeIndex: null,
            afterIndex: i,
            beforeLine: null,
            afterLine: line,
          ),
        );
        continue;
      }
      final old = before.lines[oldIndex];
      if (old.text != line.text ||
          old.startTime != line.startTime ||
          old.endTime != line.endTime) {
        changes.add(
          _LineChange(
            kind: _ChangeKind.corrected,
            beforeIndex: oldIndex,
            afterIndex: i,
            beforeLine: old,
            afterLine: line,
          ),
        );
      }
    }
    for (final item in remainingOld.entries) {
      changes.add(
        _LineChange(
          kind: _ChangeKind.removed,
          beforeIndex: item.value,
          afterIndex: null,
          beforeLine: before.lines[item.value],
          afterLine: null,
        ),
      );
    }
    return changes;
  }

  String _time(LyricLine? line) {
    if (line == null) return '—';
    final ms = line.startTime.inMilliseconds;
    final minutes = (ms ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
    final centiseconds = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$centiseconds';
  }

  @override
  Widget build(BuildContext context) {
    final changes = _changes();
    final corrected = changes
        .where((c) => c.kind == _ChangeKind.corrected)
        .length;
    final inserted = changes
        .where((c) => c.kind == _ChangeKind.inserted)
        .length;
    final timeOnly = changes
        .where(
          (c) =>
              c.beforeLine != null &&
              c.afterLine != null &&
              c.beforeLine!.text == c.afterLine!.text &&
              (c.beforeLine!.startTime != c.afterLine!.startTime ||
                  c.beforeLine!.endTime != c.afterLine!.endTime),
        )
        .length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本次逐行对比',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '变化 $corrected 行 · 补全 $inserted 行'
                      '${timeOnly > 0 ? ' · 仅时间变化 $timeOnly 行' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: changes.isEmpty
              ? const Center(child: Text('本次校对没有改变文字或时间轴。'))
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: changes.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => _LineChangeCard(
                    change: changes[index],
                    timeLabel: _time,
                    diffService: _diffService,
                    onPreview: onPreviewLine,
                  ),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '显示本次应用时的快照；试听复用当前播放会话，不会自动保存。',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineChangeCard extends StatelessWidget {
  final _LineChange change;
  final String Function(LyricLine?) timeLabel;
  final CharacterDiffService diffService;
  final ValueChanged<int>? onPreview;

  const _LineChangeCard({
    required this.change,
    required this.timeLabel,
    required this.diffService,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final old = change.beforeLine;
    final current = change.afterLine;
    final index = change.afterIndex ?? change.beforeIndex ?? 0;
    final title = switch (change.kind) {
      _ChangeKind.corrected => '文字修正',
      _ChangeKind.inserted => '补全新增',
      _ChangeKind.removed => '移除',
    };
    final timingChanged =
        old != null &&
        current != null &&
        (old.startTime != current.startTime || old.endTime != current.endTime);
    final diff = diffService.diff(old?.text ?? '', current?.text ?? '');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '第 ${index + 1} 行 · $title',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (current != null && change.afterIndex != null)
                OutlinedButton.icon(
                  onPressed: onPreview == null
                      ? null
                      : () => onPreview!(change.afterIndex!),
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: const Text('试听这一行'),
                ),
            ],
          ),
          if (old != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _DiffRow(label: '校对前', segments: diff, showInsertions: false),
          ],
          const SizedBox(height: AppSpacing.xs),
          _DiffRow(label: '校对后', segments: diff, showInsertions: true),
          if (timingChanged) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '时间：${timeLabel(old)} → ${timeLabel(current)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ] else if (current != null && old == null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '估算开始时间：${timeLabel(current)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  final String label;
  final List<CharacterDiffSegment> segments;
  final bool showInsertions;

  const _DiffRow({
    required this.label,
    required this.segments,
    required this.showInsertions,
  });

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    for (final segment in segments) {
      if (showInsertions && segment.type == CharacterDiffType.delete) continue;
      if (!showInsertions && segment.type == CharacterDiffType.insert) continue;
      final changed = !segment.isEqual;
      final color = !changed
          ? AppColors.textPrimary
          : showInsertions
          ? AppColors.accentHover
          : AppColors.error;
      spans.add(
        TextSpan(
          text: segment.text,
          style: TextStyle(
            color: color,
            backgroundColor: changed
                ? (showInsertions ? AppColors.accent : AppColors.error)
                      .withAlpha(30)
                : null,
            fontWeight: changed ? FontWeight.w700 : FontWeight.normal,
            decoration: !showInsertions && changed
                ? TextDecoration.lineThrough
                : null,
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ),
        Expanded(
          child: spans.isEmpty
              ? const Text(
                  '（空）',
                  style: TextStyle(color: AppColors.textTertiary),
                )
              : Text.rich(
                  TextSpan(children: spans),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
        ),
      ],
    );
  }
}
