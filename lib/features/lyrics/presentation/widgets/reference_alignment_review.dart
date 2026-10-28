import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/reference_lyric_input.dart';
import '../../domain/services/character_diff_service.dart';
import '../../domain/services/lyric_alignment_service.dart';
import '../../domain/services/reference_alignment_batch_selector.dart';
import '../../domain/services/reference_timeline_completion_service.dart';

/// 逐行确认的结果；调用方只应写入用户明确采纳的行（或时间轴）。
class ReferenceAlignmentReviewDecision {
  final Set<int> acceptedReferenceIndices;

  /// 用户勾选要补入的漏行参考索引。
  final Set<int> acceptedMissingReferenceIndices;

  /// 用户对手动编辑行显式确认"仍要替换"的 ASR 行索引。
  final Set<int> overriddenAsrLineIndices;

  final bool applyReferenceTiming;

  const ReferenceAlignmentReviewDecision({
    required this.acceptedReferenceIndices,
    required this.acceptedMissingReferenceIndices,
    required this.overriddenAsrLineIndices,
    required this.applyReferenceTiming,
  });

  bool get hasChanges =>
      acceptedReferenceIndices.isNotEmpty ||
      acceptedMissingReferenceIndices.isNotEmpty ||
      applyReferenceTiming;
}

/// 打开逐行确认面板。返回 null 表示取消。
Future<ReferenceAlignmentReviewDecision?> showReferenceAlignmentReview(
  BuildContext context, {
  required LyricDocument document,
  required LyricAlignmentResult alignment,
  required ReferenceLyricInput input,
  required Set<int> manuallyEditedLineIndices,
  required String? timingUnavailableReason,
  double minimumSimilarity = 0.8,
}) {
  final timedLineCount = alignment.entries
      .where(
        (entry) =>
            entry.asrLineIndex != null &&
            entry.referenceHasTimestamp &&
            entry.startTime != null,
      )
      .length;

  return showModalBottomSheet<ReferenceAlignmentReviewDecision>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final spec = AppResponsive.of(sheetContext);
      return FractionallySizedBox(
        heightFactor: spec.isShort ? 0.98 : 0.92,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Material(
              color: AppColors.bgElevated,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ReferenceAlignmentReviewSheet(
                document: document,
                alignment: alignment,
                input: input,
                manuallyEditedLineIndices: manuallyEditedLineIndices,
                timingUnavailableReason: timingUnavailableReason,
                minimumSimilarity: minimumSimilarity,
                timedLineCount: timedLineCount,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ReferenceAlignmentReviewSheet extends StatefulWidget {
  final LyricDocument document;
  final LyricAlignmentResult alignment;
  final ReferenceLyricInput input;
  final Set<int> manuallyEditedLineIndices;
  final String? timingUnavailableReason;
  final double minimumSimilarity;
  final int timedLineCount;

  const ReferenceAlignmentReviewSheet({
    super.key,
    required this.document,
    required this.alignment,
    required this.input,
    required this.manuallyEditedLineIndices,
    required this.timingUnavailableReason,
    required this.minimumSimilarity,
    required this.timedLineCount,
  });

  @override
  State<ReferenceAlignmentReviewSheet> createState() =>
      _ReferenceAlignmentReviewSheetState();
}

class _ReferenceAlignmentReviewSheetState
    extends State<ReferenceAlignmentReviewSheet> {
  static const _diffService = CharacterDiffService();
  static const _batchSelector = ReferenceAlignmentBatchSelector();

  final Set<int> _acceptedReferenceIndices = {};
  final Set<int> _acceptedMissingReferenceIndices = {};
  final Set<int> _overriddenAsrLineIndices = {};

  /// 可供逐行纠正的条目：replace（高置信）、lowConfidence（低置信）与
  /// ambiguous（歧义匹配）。missing 漏行走独立的补全区。
  late final List<LyricAlignmentEntry> _correctableEntries;
  late final List<LyricAlignmentEntry> _safeEntries;
  late final List<LyricAlignmentEntry> _uncertainEntries;
  late final List<LyricAlignmentEntry> _missingEntries;
  late final Map<int, ReferenceLineCompletionInsertion> _missingInsertions;
  late final ReferenceLineCompletionPlan _completionPlan;
  late final Map<int, List<CharacterDiffSegment>> _diffs;
  late final int _identicalCount;
  late final int _unmatchedCount;
  late final int _lockedCount;
  late bool _applyTiming;

  /// 歧义条目的用户选择：referenceIndex → 'replace' | 'insert' | null。
  /// insert 表示将参考行作为漏行插入，replace 表示替换匹配的 ASR 行。
  final Map<int, String> _ambiguousChoice = {};

  bool get _canApplyTiming =>
      widget.input.timed && widget.timingUnavailableReason == null;

  int get _thresholdPercent => (widget.minimumSimilarity * 100).round();

  int get _completableCount => _completionPlan.insertions
      .where((insertion) => !insertion.requiresConfirmation)
      .length;

  int get _confirmationRequiredCount =>
      _completionPlan.insertions.length - _completableCount;

  @override
  void initState() {
    super.initState();
    _correctableEntries = [
      for (final entry in widget.alignment.entries)
        if (entry.asrLineIndex != null &&
            entry.status != ReferenceLineAlignmentStatus.identical &&
            entry.status != ReferenceLineAlignmentStatus.missing)
          entry,
    ];
    _safeEntries = [
      for (final entry in _correctableEntries)
        if (entry.status == ReferenceLineAlignmentStatus.replace &&
            !entry.ambiguous &&
            !entry.structuralMismatch &&
            entry.similarity >= widget.minimumSimilarity &&
            !widget.manuallyEditedLineIndices.contains(entry.asrLineIndex))
          entry,
    ];
    final safeKeys = {for (final entry in _safeEntries) entry.referenceIndex};
    _uncertainEntries = [
      for (final entry in _correctableEntries)
        if (!safeKeys.contains(entry.referenceIndex)) entry,
    ];
    _missingEntries = [
      for (final entry in widget.alignment.entries)
        if (entry.status == ReferenceLineAlignmentStatus.missing) entry,
    ];
    _completionPlan = const ReferenceTimelineCompletionService().buildPlan(
      document: widget.document,
      alignment: widget.alignment,
    );
    _missingInsertions = {
      for (final insertion in _completionPlan.insertions)
        insertion.referenceIndex: insertion,
    };
    _diffs = {
      for (final entry in _correctableEntries)
        entry.referenceIndex: _diffService.diff(
          _asrText(entry),
          entry.referenceText,
        ),
    };
    _identicalCount = widget.alignment.entries
        .where(
          (entry) => entry.status == ReferenceLineAlignmentStatus.identical,
        )
        .length;
    _unmatchedCount = widget.alignment.unmatchedAsrIndices.length;
    _lockedCount = _correctableEntries
        .where(
          (entry) =>
              widget.manuallyEditedLineIndices.contains(entry.asrLineIndex),
        )
        .length;

    // 仅安全批量自动预选；lowConfidence/ambiguous/结构差异需用户显式确认。
    _acceptedReferenceIndices.addAll(_currentSelection().safeReferenceIndices);
    _applyTiming = _canApplyTiming && widget.timedLineCount > 0;
    for (final insertion in _completionPlan.insertions) {
      if (!insertion.requiresConfirmation) {
        _acceptedMissingReferenceIndices.add(insertion.referenceIndex);
      }
    }
  }

  String _asrText(LyricAlignmentEntry entry) {
    final index = entry.asrLineIndex;
    if (index == null || index < 0 || index >= widget.document.lines.length) {
      return '';
    }
    return widget.document.lines[index].text;
  }

  bool _isLocked(LyricAlignmentEntry entry) =>
      widget.manuallyEditedLineIndices.contains(entry.asrLineIndex);

  ReferenceAlignmentBatchSelection _currentSelection() {
    return _batchSelector.select(
      alignment: widget.alignment,
      completionPlan: _completionPlan,
      minimumSimilarity: widget.minimumSimilarity,
      protectedLineIndices: widget.manuallyEditedLineIndices.difference(
        _overriddenAsrLineIndices,
      ),
    );
  }

  void _selectHighConfidence() {
    setState(() {
      _acceptedReferenceIndices
        ..clear()
        ..addAll(_currentSelection().safeReferenceIndices);
    });
  }

  /// 显式选择全部需确认行；这是批量覆盖低置信/歧义行的唯一入口。
  Future<void> _selectUncertain() async {
    final selection = _currentSelection();
    if (selection.uncertainReferenceIndices.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: const Text('采纳全部低置信/歧义行？'),
        content: Text(
          '将选中 ${selection.uncertainReferenceIndices.length} 行相似度不足、'
          '存在歧义或结构差异的匹配。它们可能替换掉正确的草稿行，'
          '建议先逐行检查差异再应用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('仍然全部选中'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _acceptedReferenceIndices.addAll(selection.uncertainReferenceIndices);
    });
  }

  void _selectCompletableMissing() {
    setState(() {
      _acceptedMissingReferenceIndices
        ..clear()
        ..addAll([
          for (final insertion in _completionPlan.insertions)
            if (!insertion.requiresConfirmation) insertion.referenceIndex,
        ]);
    });
  }

  void _skipAll() {
    setState(() {
      _acceptedReferenceIndices.clear();
      _acceptedMissingReferenceIndices.clear();
    });
  }

  Future<void> _confirmOverride(LyricAlignmentEntry entry) async {
    final asrIndex = entry.asrLineIndex;
    if (asrIndex == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: const Text('仍然替换这一行？'),
        content: const Text('这一行在本次校对中手动改过。用参考歌词替换后，当前文字会被覆盖，时间轴保持不变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('保留当前文字'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('仍要替换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _overriddenAsrLineIndices.add(asrIndex);
      _acceptedReferenceIndices.add(entry.referenceIndex);
    });
  }

  Widget _buildReviewCard(LyricAlignmentEntry entry) {
    return _ReviewCard(
      entry: entry,
      diff: _diffs[entry.referenceIndex] ?? const [],
      accepted: _acceptedReferenceIndices.contains(entry.referenceIndex),
      ambiguousChoice: _ambiguousChoice[entry.referenceIndex],
      locked: _isLocked(entry),
      overridden: _overriddenAsrLineIndices.contains(entry.asrLineIndex),
      thresholdPercent: _thresholdPercent,
      onChanged: (value) {
        setState(() {
          if (value) {
            _acceptedReferenceIndices.add(entry.referenceIndex);
            _ambiguousChoice.remove(entry.referenceIndex);
          } else {
            _acceptedReferenceIndices.remove(entry.referenceIndex);
          }
        });
      },
      onOverride: () => _confirmOverride(entry),
      onAmbiguousChoice: (choice) {
        setState(() {
          if (choice == null || choice == 'skip') {
            _ambiguousChoice[entry.referenceIndex] = 'skip';
            _acceptedReferenceIndices.remove(entry.referenceIndex);
            _acceptedMissingReferenceIndices.remove(entry.referenceIndex);
          } else if (choice == 'replace') {
            _ambiguousChoice[entry.referenceIndex] = 'replace';
            _acceptedReferenceIndices.add(entry.referenceIndex);
            _acceptedMissingReferenceIndices.remove(entry.referenceIndex);
          } else if (choice == 'insert') {
            _ambiguousChoice[entry.referenceIndex] = 'insert';
            _acceptedMissingReferenceIndices.add(entry.referenceIndex);
            _acceptedReferenceIndices.remove(entry.referenceIndex);
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final gutter = spec.pageGutter.clamp(12.0, 24.0).toDouble();
    final timingEnabled = _applyTiming && _canApplyTiming;
    final canApply =
        _acceptedReferenceIndices.isNotEmpty ||
        _acceptedMissingReferenceIndices.isNotEmpty ||
        timingEnabled;

    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        _buildHeader(context, spec, gutter),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.md),
            children: [
              _buildMetrics(),
              if (widget.input.conflicts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _NoteBox(
                  icon: Icons.warning_amber_rounded,
                  text:
                      '参考歌词导入时发现时间轴冲突：\n'
                      '${widget.input.conflicts.join('\n')}',
                ),
              ],
              if (widget.input.warnings.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _NoteBox(
                  icon: Icons.info_outline_rounded,
                  text: widget.input.warnings.join('\n'),
                ),
              ],
              if (widget.alignment.structuralMismatches.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _NoteBox(
                  icon: Icons.call_split_rounded,
                  text: widget.alignment.structuralMismatches
                      .map((mismatch) => mismatch.message)
                      .join('\n'),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              _buildQuickActions(spec),
              const SizedBox(height: AppSpacing.md),
              if (_correctableEntries.isEmpty)
                const _NoteBox(
                  icon: Icons.check_circle_outline_rounded,
                  text: '没有需要逐行确认的文字差异。',
                )
              else ...[
                if (_safeEntries.isNotEmpty) ...[
                  _SectionTitle('可安全批量采纳（${_safeEntries.length}）'),
                  for (final entry in _safeEntries) _buildReviewCard(entry),
                ],
                if (_uncertainEntries.isNotEmpty) ...[
                  if (_safeEntries.isNotEmpty)
                    const SizedBox(height: AppSpacing.sm),
                  _SectionTitle(
                    '需逐行确认：低置信 / 歧义 / 结构差异（${_uncertainEntries.length}）',
                  ),
                  for (final entry in _uncertainEntries)
                    _buildReviewCard(entry),
                ],
              ],
              if (_missingEntries.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _SectionTitle('补全漏行：参考有、草稿无（${_missingEntries.length}）'),
                const SizedBox(height: AppSpacing.xs),
                const _NoteBox(
                  icon: Icons.playlist_add_rounded,
                  text:
                      '漏行会按前后已匹配草稿行推断时间并插入。标记“需确认”的行'
                      '可能已被 ASR 合并或拆分，默认不勾选；勾选后仍可保存前检查。',
                ),
                for (final entry in _missingEntries)
                  _MissingRow(
                    entry: entry,
                    insertion: _missingInsertions[entry.referenceIndex],
                    accepted: _acceptedMissingReferenceIndices.contains(
                      entry.referenceIndex,
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value) {
                          _acceptedMissingReferenceIndices.add(
                            entry.referenceIndex,
                          );
                        } else {
                          _acceptedMissingReferenceIndices.remove(
                            entry.referenceIndex,
                          );
                        }
                      });
                    },
                  ),
              ],
              if (_unmatchedCount > 0) ...[
                const SizedBox(height: AppSpacing.md),
                _NoteBox(
                  icon: Icons.help_outline_rounded,
                  text: '当前草稿有 $_unmatchedCount 行没有参考对应，将保持原样。',
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              _buildTimingSection(context),
              if (_identicalCount > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '另有 $_identicalCount 行完全一致，无需处理。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        _buildFooter(context, spec, gutter, canApply),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, AppLayoutSpec spec, double gutter) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '逐行确认参考歌词',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '参考 ${widget.input.lines.length} 行'
                  ' / 草稿 ${widget.document.lines.length} 行 · 字符级差异',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '关闭',
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(
              minimumSize: Size(
                spec.minimumInteractiveExtent,
                spec.minimumInteractiveExtent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics() {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        _ReviewMetric(
          label: '待确认',
          count: _correctableEntries.length,
          color: AppColors.accent,
        ),
        _ReviewMetric(label: '已选', count: _acceptedReferenceIndices.length),
        if (_acceptedMissingReferenceIndices.isNotEmpty)
          _ReviewMetric(
            label: '已选补全',
            count: _acceptedMissingReferenceIndices.length,
            color: AppColors.accent,
          ),
        _ReviewMetric(label: '完全一致', count: _identicalCount),
        if (_lockedCount > 0)
          _ReviewMetric(
            label: '手动编辑',
            count: _lockedCount,
            color: AppColors.warning,
          ),
        if (_completableCount > 0)
          _ReviewMetric(label: '可补全', count: _completableCount),
        if (_confirmationRequiredCount > 0)
          _ReviewMetric(
            label: '需确认漏行',
            count: _confirmationRequiredCount,
            color: AppColors.warning,
          ),
        if (_unmatchedCount > 0)
          _ReviewMetric(label: '多余识别', count: _unmatchedCount),
      ],
    );
  }

  Widget _buildQuickActions(AppLayoutSpec spec) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        OutlinedButton.icon(
          onPressed: _safeEntries.isEmpty ? null : _selectHighConfidence,
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, spec.minimumInteractiveExtent),
          ),
          icon: const Icon(Icons.done_all_rounded, size: 18),
          label: Text('全选安全行 ≥$_thresholdPercent%'),
        ),
        if (_uncertainEntries.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _selectUncertain,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, spec.minimumInteractiveExtent),
            ),
            icon: const Icon(Icons.rule_rounded, size: 18),
            label: Text('选择需确认行（${_uncertainEntries.length}）'),
          ),
        if (_completableCount > 0)
          OutlinedButton.icon(
            onPressed: _selectCompletableMissing,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, spec.minimumInteractiveExtent),
            ),
            icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
            label: Text('补全全部漏行（$_completableCount）'),
          ),
        TextButton(
          onPressed:
              _acceptedReferenceIndices.isEmpty &&
                  _acceptedMissingReferenceIndices.isEmpty
              ? null
              : _skipAll,
          style: TextButton.styleFrom(
            minimumSize: Size(0, spec.minimumInteractiveExtent),
          ),
          child: const Text('全部跳过'),
        ),
      ],
    );
  }

  Widget _buildTimingSection(BuildContext context) {
    if (!widget.input.timed) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.sm),
        child: _NoteBox(
          icon: Icons.schedule_rounded,
          text: '纯文本参考：已有行保留 ASR 时间轴；漏行按相邻行空隙推断时间。',
        ),
      );
    }
    if (!_canApplyTiming) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: _NoteBox(
          icon: Icons.info_outline_rounded,
          text:
              widget.timingUnavailableReason ??
              '参考歌词带时间戳，但当前无法整体替换时间轴；'
                  '本次只纠正文字并保留原时间轴。',
        ),
      );
    }
    return CheckboxListTile(
      value: _applyTiming,
      onChanged: (value) => setState(() => _applyTiming = value ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text('同时采用参考歌词时间轴（${widget.timedLineCount} 行）'),
      subtitle: const Text('时间轴整体替换，与逐行文字选择无关；应用后全局偏移归零。'),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    AppLayoutSpec spec,
    double gutter,
    bool canApply,
  ) {
    final timingEnabled = _applyTiming && _canApplyTiming;
    final missingCount = _acceptedMissingReferenceIndices.length;
    final summary = <String>[
      if (_acceptedReferenceIndices.isNotEmpty)
        '已选 ${_acceptedReferenceIndices.length} 行',
      if (missingCount > 0) '补全 $missingCount 行',
      if (timingEnabled) '同时更新时间轴',
      if (_acceptedReferenceIndices.isEmpty &&
          missingCount == 0 &&
          !timingEnabled)
        '勾选要采纳的行',
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: EdgeInsets.fromLTRB(
        gutter,
        AppSpacing.sm,
        gutter,
        AppSpacing.sm,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                summary.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                minimumSize: Size(0, spec.minimumInteractiveExtent),
              ),
              child: const Text('取消'),
            ),
            const SizedBox(width: AppSpacing.xs),
            FilledButton(
              onPressed: canApply
                  ? () => Navigator.of(context).pop(
                      ReferenceAlignmentReviewDecision(
                        acceptedReferenceIndices: Set.unmodifiable(
                          _acceptedReferenceIndices,
                        ),
                        acceptedMissingReferenceIndices: Set.unmodifiable(
                          _acceptedMissingReferenceIndices,
                        ),
                        overriddenAsrLineIndices: Set.unmodifiable(
                          _overriddenAsrLineIndices,
                        ),
                        applyReferenceTiming: timingEnabled,
                      ),
                    )
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: Size(0, spec.minimumInteractiveExtent),
              ),
              child: Text(_applyLabel(timingEnabled)),
            ),
          ],
        ),
      ),
    );
  }

  String _applyLabel(bool timingEnabled) {
    final count = _acceptedReferenceIndices.length;
    final missingCount = _acceptedMissingReferenceIndices.length;
    final parts = <String>[
      if (count > 0) '$count 行',
      if (missingCount > 0) '补全 $missingCount 行',
      if (timingEnabled) '时间轴',
    ];
    if (parts.isEmpty) return '没有可应用的修改';
    if (count > 0 && missingCount == 0 && !timingEnabled) {
      return '应用 $count 行修正';
    }
    if (count == 0 && missingCount == 0 && timingEnabled) {
      return '采用参考时间轴';
    }
    if (count == 0 && missingCount > 0) {
      return timingEnabled ? '补全 $missingCount 行 + 时间轴' : '补全 $missingCount 行';
    }
    return '应用 ${parts.join(' + ')}';
  }
}

class _ReviewCard extends StatelessWidget {
  final LyricAlignmentEntry entry;
  final List<CharacterDiffSegment> diff;
  final bool accepted;
  final bool locked;
  final bool overridden;

  /// 歧义条目的用户选择：'replace' | 'insert' | null。
  final String? ambiguousChoice;
  final int thresholdPercent;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOverride;

  /// 歧义条目选择替换/插入时回调。
  final ValueChanged<String?>? onAmbiguousChoice;

  const _ReviewCard({
    required this.entry,
    required this.diff,
    required this.accepted,
    required this.locked,
    required this.overridden,
    this.ambiguousChoice,
    required this.thresholdPercent,
    required this.onChanged,
    required this.onOverride,
    this.onAmbiguousChoice,
  });

  @override
  Widget build(BuildContext context) {
    final similarityPercent = (entry.similarity * 100).round();
    final lowConfidence = similarityPercent < thresholdPercent;
    final isAmbiguous = entry.status == ReferenceLineAlignmentStatus.ambiguous;
    final showCheckbox = !locked || overridden;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(
          color: accepted
              ? AppColors.accent.withAlpha(90)
              : AppColors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '第 ${entry.asrLineIndex! + 1} 行',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      _lineTimeLabel(entry),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    _Badge(
                      label: '$similarityPercent%',
                      color: lowConfidence
                          ? AppColors.warning
                          : AppColors.accent,
                    ),
                    if (lowConfidence)
                      const _Badge(label: '低相似', color: AppColors.warning),
                    if (entry.status == ReferenceLineAlignmentStatus.ambiguous)
                      const _Badge(label: '歧义匹配', color: AppColors.warning),
                    if (locked)
                      const _Badge(label: '已手动编辑', color: AppColors.warning),
                  ],
                ),
              ),
              if (isAmbiguous && onAmbiguousChoice != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: ambiguousChoice == 'replace',
                          onChanged: (_) => onAmbiguousChoice?.call('replace'),
                        ),
                        const SizedBox(width: 4),
                        const Text('替换此行', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: ambiguousChoice == 'insert',
                          onChanged: (_) => onAmbiguousChoice?.call('insert'),
                        ),
                        const SizedBox(width: 4),
                        const Text('作为漏行插入', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: ambiguousChoice == 'skip',
                          onChanged: (_) => onAmbiguousChoice?.call('skip'),
                        ),
                        const SizedBox(width: 4),
                        const Text('跳过', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ] else if (showCheckbox)
                Checkbox(
                  value: accepted,
                  onChanged: (value) => onChanged(value ?? false),
                )
              else
                const SizedBox(width: AppSpacing.xs),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _DiffLine(
            label: '识别',
            segments: diff,
            showInsertions: false,
            emptyLabel: '（空）',
          ),
          const SizedBox(height: 2),
          _DiffLine(
            label: '参考',
            segments: diff,
            showInsertions: true,
            emptyLabel: '（空）',
          ),
          if (locked && !overridden) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    '本次已手动编辑，默认不覆盖',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.warning),
                  ),
                ),
                TextButton(
                  onPressed: onOverride,
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('仍要替换'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  final String label;
  final List<CharacterDiffSegment> segments;
  final bool showInsertions;
  final String emptyLabel;

  const _DiffLine({
    required this.label,
    required this.segments,
    required this.showInsertions,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary, height: 1.4);
    final spans = <TextSpan>[];
    for (final segment in segments) {
      if (showInsertions && segment.type == CharacterDiffType.delete) continue;
      if (!showInsertions && segment.type == CharacterDiffType.insert) continue;
      final changed = !segment.isEqual;
      spans.add(
        TextSpan(
          text: segment.text,
          style: changed
              ? TextStyle(
                  color: showInsertions
                      ? AppColors.accentHover
                      : AppColors.error,
                  backgroundColor:
                      (showInsertions ? AppColors.accent : AppColors.error)
                          .withAlpha(30),
                  fontWeight: showInsertions
                      ? FontWeight.w700
                      : FontWeight.w500,
                  decoration: showInsertions
                      ? null
                      : TextDecoration.lineThrough,
                  decorationColor: AppColors.error,
                )
              : null,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        ),
        Expanded(
          child: spans.isEmpty
              ? Text(
                  emptyLabel,
                  style: baseStyle?.copyWith(color: AppColors.textTertiary),
                )
              : Text.rich(
                  TextSpan(children: spans),
                  style: baseStyle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }
}

class _MissingRow extends StatelessWidget {
  final LyricAlignmentEntry entry;
  final ReferenceLineCompletionInsertion? insertion;
  final bool accepted;
  final ValueChanged<bool> onChanged;

  const _MissingRow({
    required this.entry,
    required this.insertion,
    required this.accepted,
    required this.onChanged,
  });

  String _positionLabel() {
    final nextIndex = insertion?.nextAsrLineIndex;
    if (nextIndex == null) return '追加到末尾';
    return '插入到第 ${nextIndex + 1} 行前';
  }

  @override
  Widget build(BuildContext context) {
    final insertion = this.insertion;
    final canInsert = insertion != null;
    final warning = insertion?.requiresConfirmation ?? false;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(
          color: accepted
              ? AppColors.accent.withAlpha(90)
              : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.referenceText),
                if (insertion != null) ...[
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _positionLabel(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      Text(
                        '${_formatReviewTime(insertion.startTime)} – '
                        '${_formatReviewTime(insertion.endTime)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (warning)
                        const _Badge(label: '需确认', color: AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    warning
                        ? '前后锚点之间夹着未匹配行，可能已被 ASR 合并/拆分；'
                              '勾选会按上面的时间插入。'
                        : '按前后已匹配行的空隙推断时间。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: warning
                          ? AppColors.warning
                          : AppColors.textTertiary,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  Text(
                    '无法生成插入计划，请手动在播放位置插入。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.warning),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Checkbox(
            value: accepted,
            onChanged: canInsert ? (value) => onChanged(value ?? false) : null,
          ),
        ],
      ),
    );
  }
}

class _ReviewMetric extends StatelessWidget {
  final String label;
  final int count;
  final Color? color;

  const _ReviewMetric({required this.label, required this.count, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color ?? AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _NoteBox extends StatelessWidget {
  final IconData icon;
  final String text;

  const _NoteBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

String _lineTimeLabel(LyricAlignmentEntry entry) {
  final start = entry.startTime;
  final end = entry.endTime;
  if (start == null) return '未定时间';
  if (end == null) return _formatReviewTime(start);
  return '${_formatReviewTime(start)}–${_formatReviewTime(end)}';
}

String _formatReviewTime(Duration duration) {
  final totalMs = duration.inMilliseconds < 0 ? 0 : duration.inMilliseconds;
  final totalSeconds = totalMs ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final tenths = (totalMs % 1000) ~/ 100;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.$tenths';
}
