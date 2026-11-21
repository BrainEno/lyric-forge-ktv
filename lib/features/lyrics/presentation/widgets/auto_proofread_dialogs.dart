import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/online/online_lyric_query.dart';
import '../../domain/proofreading/auto_proofread_service.dart';

/// Texts of 一键校对, kept together so the menu, the toolbar and the
/// summaries describe it the same way.
class AutoProofreadStrings {
  const AutoProofreadStrings._();

  static const String actionTitle = '一键校对';
  static const String actionDetail = '自动联网查找这首歌的歌词，改错字、补漏句、整理文本和时间轴；可撤销';
  static const String runningLabel = '校对中…';
  static const String tooltip =
      '按歌名和歌手联网查找歌词（网易云音乐、酷狗音乐、LRCLIB），'
      '只改有把握的行，手动改过的行不动；离线时只做本地整理。';

  static String searching(OnlineLyricQuery query) =>
      '正在联网查找「${_song(query)}」的歌词并校对…';

  static String _song(OnlineLyricQuery query) =>
      query.artist.isEmpty ? query.title : '${query.title} - ${query.artist}';

  /// Why no online lyric was used, as the lead of the summary.
  static String? lyricNote(AutoProofreadOutcome outcome) =>
      switch (outcome.lyricStatus) {
        AutoProofreadLyricStatus.applied => null,
        AutoProofreadLyricStatus.searchUnavailable => '未启用联网歌词',
        AutoProofreadLyricStatus.noTitle => '项目没有歌名，无法联网查找',
        AutoProofreadLyricStatus.offline => '无法连接歌词网站',
        AutoProofreadLyricStatus.notFound => '没有找到「${_song(outcome.query)}」的歌词',
        AutoProofreadLyricStatus.noMatch => '找到的歌词与识别结果对不上',
        AutoProofreadLyricStatus.rejected => '在线歌词会打乱时间轴，已放弃使用',
      };

  /// The one-line summary shown after the pass was applied.
  static String summary(AutoProofreadOutcome outcome) {
    final result = outcome.result;
    final reference = result.reference;
    final lead = reference != null && result.usedReference
        ? '已参照${reference.candidate.source.label}「${reference.candidate.title}」'
        : '${lyricNote(outcome)}，已做本地整理';
    final parts = <String>[
      if (result.correctedLines > 0) '改正 ${result.correctedLines} 行',
      if (result.insertedLines > 0) '补全 ${result.insertedLines} 行',
      if (result.verifiedLines > 0) '确认 ${result.verifiedLines} 行无误',
      if (result.cleanedLines > 0) '清理 ${result.cleanedLines} 行',
      if (result.removedLines > 0) '删除 ${result.removedLines} 行非歌词',
      if (result.loopFixes > 0) '精简 ${result.loopFixes} 行循环',
      if (result.repetitionFixes > 0) '统一 ${result.repetitionFixes} 行重复段落',
      if (result.timelineFixes > 0) '修复 ${result.timelineFixes} 处时间轴',
    ];
    final skipped = result.skippedProtectedLines > 0
        ? '；跳过 ${result.skippedProtectedLines} 行手动编辑'
        : '';
    return '$lead：${parts.join('，')}$skipped。请检查后保存。';
  }

  /// Shown when nothing at all needed changing.
  static String nothingToDo(AutoProofreadOutcome outcome) {
    final note = lyricNote(outcome);
    if (note == null) {
      return '歌词与「${outcome.result.reference?.candidate.title ?? outcome.query.title}」'
          '的在线歌词一致，没有需要修改的地方。';
    }
    return '$note，也没有发现可自动修正的问题。可在「校对」菜单中粘贴参考歌词。';
  }
}

/// What the user chose when no online lyric matched.
sealed class AutoProofreadFallback {
  const AutoProofreadFallback();
}

/// Search again with a corrected title and artist.
class AutoProofreadRetry extends AutoProofreadFallback {
  final OnlineLyricQuery query;

  const AutoProofreadRetry(this.query);
}

/// Open the paste-a-lyric review instead.
class AutoProofreadPaste extends AutoProofreadFallback {
  const AutoProofreadPaste();
}

/// Apply only the offline clean-up that was already computed.
class AutoProofreadOfflineOnly extends AutoProofreadFallback {
  const AutoProofreadOfflineOnly();
}

/// Asks what to do when the search found no lyric that matches; null when
/// the user cancelled.
Future<AutoProofreadFallback?> showAutoProofreadFallbackDialog(
  BuildContext context, {
  required AutoProofreadOutcome outcome,
}) {
  return showDialog<AutoProofreadFallback>(
    context: context,
    builder: (_) => _AutoProofreadFallbackDialog(outcome: outcome),
  );
}

class _AutoProofreadFallbackDialog extends StatefulWidget {
  const _AutoProofreadFallbackDialog({required this.outcome});

  final AutoProofreadOutcome outcome;

  @override
  State<_AutoProofreadFallbackDialog> createState() =>
      _AutoProofreadFallbackDialogState();
}

class _AutoProofreadFallbackDialogState
    extends State<_AutoProofreadFallbackDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.outcome.query.title,
  );
  late final TextEditingController _artist = TextEditingController(
    text: widget.outcome.query.artist,
  );

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  void _retry() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(
      AutoProofreadRetry(
        widget.outcome.query.copyWith(
          title: title,
          artist: _artist.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = widget.outcome;
    final best = outcome.bestCandidate;
    final offlineChanges = outcome.result.hasChanges;
    return AlertDialog(
      title: Text(AutoProofreadStrings.lyricNote(outcome) ?? '没有找到歌词'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              best == null
                  ? '歌名或歌手可能写得不准确。改正后可以重新查找，也可以粘贴你手头的歌词。'
                  : '最接近的是「${best.candidate.displayName}」，只有'
                        '${(best.draftCoverage * 100).round()}% 的识别内容能对上，'
                        '可能是同名的另一首歌。改正歌名或歌手后再找一次？',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '歌名'),
              onSubmitted: (_) => _retry(),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _artist,
              decoration: const InputDecoration(labelText: '歌手（可选）'),
              onSubmitted: (_) => _retry(),
            ),
            if (offlineChanges) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                '不用在线歌词也能先做本地整理（清理字幕残留、识别循环和时间轴问题）。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const AutoProofreadPaste()),
          child: const Text('粘贴歌词'),
        ),
        if (offlineChanges)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const AutoProofreadOfflineOnly()),
            child: const Text('只做本地整理'),
          ),
        FilledButton(onPressed: _retry, child: const Text('重新查找')),
      ],
    );
  }
}

/// Offers the line-by-line review of the rows the online lyric could not
/// settle; true when the user wants to review them now.
Future<bool> showAutoProofreadUncertainDialog(
  BuildContext context, {
  required AutoProofreadOutcome outcome,
}) async {
  final count = outcome.result.uncertainLines;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('还有 $count 行需要你确认'),
      content: SizedBox(
        width: 420,
        child: Text(
          '${AutoProofreadStrings.summary(outcome)}\n\n'
          '在线歌词里有 $count 行与识别结果差别较大或位置不确定，没有自动修改。'
          '逐行确认时会直接使用这份在线歌词，不需要再粘贴。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('逐行确认'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
