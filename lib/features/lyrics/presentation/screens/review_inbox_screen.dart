import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_error_state.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../../core/widgets/app_tap_target.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/lyric_review_queue.dart';
import '../controllers/review_inbox_bulk_review.dart';
import '../lyric_review_strings.dart';
import '../widgets/review_inbox_global_review.dart';

/// One row of the review inbox: a project plus its review queue.
class ReviewInboxEntry {
  final ProjectManifest project;
  final LyricReviewQueue queue;

  const ReviewInboxEntry({required this.project, required this.queue});

  /// The queue count is only meaningful when the project actually has lyrics.
  bool get hasLyrics => project.hasLyrics && queue.totalLines > 0;

  /// Whether every line has been confirmed, so nothing waits for review.
  bool get isFullyReviewed => queue.needsReviewCount == 0;
}

/// 「校对」destination: pick a project, land in its lyric editor.
///
/// Before this screen the only way into the editor was to remember which
/// project on the dashboard had lyrics, open it, and press a button there. The
/// review queue already knew which projects still had unreviewed lines; nothing
/// surfaced that.
///
/// Ordering is by outstanding review work first, then recency: a project with
/// 40 unreviewed lines is what the user came here for, not the one they saved
/// five minutes ago.
class ReviewInboxScreen extends StatefulWidget {
  /// Supplied by the routing table; the review inbox is migrated off the global
  /// service locator together with the lyric editor (Phase 4.2).
  final ProjectRepository projectRepository;

  const ReviewInboxScreen({super.key, required this.projectRepository});

  /// Title of the desktop inbox. The phone's 歌词 page is a screen of its
  /// own since D-058: a phone cannot run recognition.
  static const String inboxTitle = '校对';

  static const String markAllReviewedLabel = '全部标为已复核';
  static const String moreActionsTooltip = '更多操作';
  static const String openEditorHint = '打开歌词校对';
  static const String savingLabel = '正在保存复核标记';
  static const String undoLabel = '撤销';

  /// A project row as one spoken button (audit A-04): name, subtitle and the
  /// badges, which were only read as loose words around a bare `InkWell`.
  /// 全部标为已复核 is the row's custom action, so the ⋮ menu is not a
  /// separate stop that only makes sense after the row.
  ///
  /// Since D-069 it uses the editor's words: 建议复核 and 必看 instead of
  /// 待复核 and a separate 低置信度 count, plus the main reasons.
  static String tileLabel({
    required String name,
    required String subtitle,
    required int pending,
    required int mustCheck,
    required int unscored,
    String? reasons,
    bool saving = false,
  }) {
    return AppTapTarget.join([
      name,
      subtitle.replaceAll(' · ', '，'),
      if (pending > 0) ...[
        '${LyricSuggestedReviewStrings.label} $pending 行',
        if (mustCheck > 0)
          '${LyricSuggestedReviewStrings.mustCheckLabel(mustCheck)} 行',
        if (unscored > 0) '未评分 $unscored 行',
        ?reasons,
      ] else
        '已复核',
      if (saving) savingLabel,
    ]);
  }

  /// The line above the list, e.g. `4 个工程，共 23 行建议复核，其中 6 行必看`.
  static String summaryLine({
    required int projects,
    required int pending,
    required int mustCheck,
  }) {
    if (pending == 0) return '$projects 个工程，暂时没有建议复核的行';
    final must = mustCheck > 0 ? '，其中 $mustCheck 行必看' : '';
    return '$projects 个工程，共 $pending 行建议复核$must';
  }

  static const String undoneMessage = '已撤销，复核标记恢复原样';
  static const String undoConflictMessage = '工程已有新的改动，没有撤销';
  static const String saveFailedMessage = '没能保存复核标记，请稍后再试';

  static String markedMessage(String name) => '「$name」已全部标为已复核';
  static String conflictMessage(String name) => '「$name」刚在别处保存过，已重新读取，请再试一次';
  static String unchangedMessage(String name) => '「$name」的每一行都已确认';

  @override
  State<ReviewInboxScreen> createState() => _ReviewInboxScreenState();
}

class _ReviewInboxScreenState extends State<ReviewInboxScreen> {
  late final ProjectRepository _projects;
  late Future<List<ReviewInboxEntry>> _entriesFuture;

  /// Whether the folded 已复核 group is open. Reviewed projects used to sit in
  /// the same list as the ones still waiting, so the list kept growing with
  /// finished work (audit R-02).
  bool _showReviewed = false;

  late final ReviewInboxBulkReview _bulkReview;

  /// Project whose 全部标为已复核 is being saved; its menu shows a spinner.
  String? _savingProjectId;

  /// Progress of 全部工程标为已复核 while it runs.
  ReviewInboxGlobalProgress? _globalProgress;

  /// Whether a save from this screen is running, so a second one waits.
  bool get _busy => _savingProjectId != null || _globalProgress != null;

  @override
  void initState() {
    super.initState();
    _projects = widget.projectRepository;
    _bulkReview = ReviewInboxBulkReview(_projects);
    _entriesFuture = _load();
  }

  Future<List<ReviewInboxEntry>> _load() async {
    final projects = await _projects.getAllProjects();
    final entries = <ReviewInboxEntry>[];
    for (final project in projects) {
      final document = project.lyricDocument;
      if (document == null || document.lines.isEmpty) continue;
      entries.add(
        ReviewInboxEntry(
          project: project,
          // The editor counts with the audio length (lines past the end of
          // the song need review); the inbox must report the same number.
          queue: LyricReviewQueue.build(
            document,
            audioDuration: project.audioAsset?.duration,
          ),
        ),
      );
    }
    // The most urgent work first, as in the editor's 建议复核 list: rows
    // that must be checked, then everything suggested, then recency.
    entries.sort((left, right) {
      final byMustCheck = right.queue.mustCheckCount.compareTo(
        left.queue.mustCheckCount,
      );
      if (byMustCheck != 0) return byMustCheck;
      final byQueue = right.queue.needsReviewCount.compareTo(
        left.queue.needsReviewCount,
      );
      if (byQueue != 0) return byQueue;
      return right.project.updatedAt.compareTo(left.project.updatedAt);
    });
    return entries;
  }

  Future<void> _refresh() async {
    final future = _load();
    // Block body on purpose: an arrow here returns the assignment's value,
    // which is a Future, and setState rejects callbacks that return futures.
    setState(() {
      _entriesFuture = future;
    });
    await future;
  }

  /// Reads the list again without waiting, after a save from this screen.
  void _reload() {
    setState(() {
      _entriesFuture = _load();
    });
  }

  /// 全部标为已复核 for one project, after a confirmation (audit R-03).
  Future<void> _markAllReviewed(ReviewInboxEntry entry) async {
    final project = entry.project;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _MarkAllReviewedDialog(entry: entry),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingProjectId = project.id);
    BulkReviewResult? result;
    try {
      result = await _bulkReview.markAllReviewed(project);
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    setState(() => _savingProjectId = null);
    messenger.showSnackBar(_resultSnackBar(project, result));
    if (result != null && result.status != BulkReviewStatus.unchanged) {
      _reload();
    }
  }

  SnackBar _resultSnackBar(ProjectManifest project, BulkReviewResult? result) {
    if (result == null) {
      return const SnackBar(content: Text(ReviewInboxScreen.saveFailedMessage));
    }
    final message = switch (result.status) {
      BulkReviewStatus.saved => ReviewInboxScreen.markedMessage(project.name),
      BulkReviewStatus.conflict => ReviewInboxScreen.conflictMessage(
        project.name,
      ),
      BulkReviewStatus.unchanged => ReviewInboxScreen.unchangedMessage(
        project.name,
      ),
    };
    return SnackBar(
      content: Text(message),
      action: result.canUndo
          ? SnackBarAction(
              label: ReviewInboxScreen.undoLabel,
              onPressed: () => _undo(result),
            )
          : null,
    );
  }

  Future<void> _undo(BulkReviewResult result) async {
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final undone = await _bulkReview.undo(result);
      message = undone.status == BulkReviewStatus.saved
          ? ReviewInboxScreen.undoneMessage
          : ReviewInboxScreen.undoConflictMessage;
    } catch (_) {
      message = ReviewInboxScreen.saveFailedMessage;
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
    _reload();
  }

  void _openImport() {
    Navigator.pushNamed(context, Routes.import);
  }

  /// Opens the editor and reads the list again when it closes. The inbox
  /// used to keep its old copy, so lines confirmed and saved in the editor
  /// still showed as waiting here, which read as "the save did not stick".
  Future<void> _openEditor(ProjectManifest project) async {
    await Navigator.pushNamed(context, Routes.lyricEditorPath(project.id));
    if (mounted) _reload();
  }

  /// 全部工程标为已复核, after a confirmation (audit R-03).
  Future<void> _markEverythingReviewed(List<ReviewInboxEntry> pending) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ReviewInboxGlobalReviewDialog(
        projectNames: [for (final entry in pending) entry.project.name],
        totalLines: pending.fold(0, (sum, e) => sum + e.queue.totalLines),
        pendingLines: pending.fold(
          0,
          (sum, entry) => sum + entry.queue.needsReviewCount,
        ),
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _globalProgress = (done: 0, total: pending.length));
    final batch = await _bulkReview.markAllProjectsReviewed(
      [for (final entry in pending) entry.project],
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() => _globalProgress = (done: done, total: total));
      },
    );
    if (!mounted) return;
    setState(() => _globalProgress = null);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ReviewInboxGlobalReviewText.result(batch)),
        duration: const Duration(seconds: 8),
        action: batch.canUndo
            ? SnackBarAction(
                label: ReviewInboxGlobalReviewText.undoLabel,
                onPressed: () => _undoBatch(batch),
              )
            : null,
      ),
    );
    if (batch.changedAnything) _reload();
  }

  Future<void> _undoBatch(BulkReviewBatchResult batch) async {
    final messenger = ScaffoldMessenger.of(context);
    final undone = await _bulkReview.undoBatch(batch);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(ReviewInboxGlobalReviewText.undoResult(undone))),
    );
    _reload();
  }

  /// Summary line, the projects that still need review, then the reviewed
  /// ones. Those are folded behind a toggle while anything else is waiting;
  /// when everything is reviewed they are the list.
  List<Widget> _rows(BuildContext context, List<ReviewInboxEntry> entries) {
    final pending = entries.where((entry) => !entry.isFullyReviewed).toList();
    final reviewed = entries.where((entry) => entry.isFullyReviewed).toList();
    final totalPending = pending.fold<int>(
      0,
      (sum, entry) => sum + entry.queue.needsReviewCount,
    );
    final totalMustCheck = pending.fold<int>(
      0,
      (sum, entry) => sum + entry.queue.mustCheckCount,
    );
    final showReviewed = pending.isEmpty || _showReviewed;

    Widget tile(ReviewInboxEntry entry) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: _ReviewInboxTile(
        key: ValueKey('review-inbox:${entry.project.id}'),
        entry: entry,
        onTap: () => _openEditor(entry.project),
        saving: _savingProjectId == entry.project.id,
        onMarkAllReviewed: _busy ? null : () => _markAllReviewed(entry),
      ),
    );

    return [
      ReviewInboxSummaryBar(
        summary: ReviewInboxScreen.summaryLine(
          projects: entries.length,
          pending: totalPending,
          mustCheck: totalMustCheck,
        ),
        progress: _globalProgress,
        onMarkEverything: pending.isEmpty || _busy
            ? null
            : () => _markEverythingReviewed(pending),
      ),
      ...pending.map(tile),
      if (pending.isNotEmpty && reviewed.isNotEmpty)
        _ReviewedToggle(
          count: reviewed.length,
          expanded: _showReviewed,
          onToggle: () => setState(() => _showReviewed = !_showReviewed),
        ),
      if (showReviewed) ...reviewed.map(tile),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        title: const Text(ReviewInboxScreen.inboxTitle),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(child: _inbox(layout)),
    );
  }

  Widget _inbox(AppLayoutSpec layout) {
    return FutureBuilder<List<ReviewInboxEntry>>(
      future: _entriesFuture,
      builder: (context, snapshot) {
        // A reload after a save keeps the current list on screen until
        // the new one arrives instead of flashing the spinner.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const AppLoadingState(message: '正在读取歌词工程');
        }
        if (snapshot.hasError) {
          return AppErrorState(
            title: '工程列表加载失败',
            message: '歌词工程暂时无法读取，可以重新加载一次。',
            onRetry: _refresh,
          );
        }
        final entries = snapshot.data ?? const <ReviewInboxEntry>[];
        if (entries.isEmpty) {
          return AppEmptyState(
            icon: Icons.playlist_add_check_circle_outlined,
            title: '还没有可校对的歌词',
            message: '导入并识别一首歌之后，它的歌词会出现在这里，并标出还有多少行需要复核。',
            actions: [
              FilledButton.tonal(
                onPressed: _openImport,
                child: const Text('去导入'),
              ),
            ],
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.accent,
          backgroundColor: AppColors.bgElevated,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: layout.pageGutter,
              vertical: AppSpacing.md,
            ),
            children: _rows(context, entries),
          ),
        );
      },
    );
  }
}

class _ReviewInboxTile extends StatelessWidget {
  final ReviewInboxEntry entry;
  final VoidCallback onTap;

  /// 全部标为已复核; null disables the menu while another save runs.
  final VoidCallback? onMarkAllReviewed;

  /// This project's 全部标为已复核 is being saved.
  final bool saving;

  static const double artworkExtent = 44;

  const _ReviewInboxTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onMarkAllReviewed,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    final pending = entry.queue.needsReviewCount;
    final mustCheck = entry.queue.mustCheckCount;
    final unscored = entry.queue.unscoredLines;
    final reasons = pending > 0
        ? LyricSuggestedReviewStrings.mainReasons(entry.queue)
        : null;
    final project = entry.project;

    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: AppTapTarget(
        label: ReviewInboxScreen.tileLabel(
          name: project.name,
          subtitle: _subtitle(project, entry.queue),
          pending: pending,
          mustCheck: mustCheck,
          unscored: unscored,
          reasons: reasons,
          saving: saving,
        ),
        hint: ReviewInboxScreen.openEditorHint,
        onTap: onTap,
        actions: {
          if (pending > 0 && !saving)
            ReviewInboxScreen.markAllReviewedLabel: onMarkAllReviewed,
        },
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // The song's cover when the project has one, so the list reads
                // like the music it holds rather than a column of identical
                // lyric icons (audit R-01).
                AppArtwork(
                  path: project.audioAsset?.thumbnailPath,
                  size: _ReviewInboxTile.artworkExtent,
                  borderRadius: AppSpacing.radiusMedium,
                  placeholderIcon: Icons.lyrics_outlined,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(project, entry.queue),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      // Why the rows are waiting, in the editor's words.
                      if (reasons != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          reasons,
                          key: ValueKey('review-inbox:reasons:${project.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (pending > 0)
                  _Badge(
                    label: LyricSuggestedReviewStrings.chip(pending),
                    color: AppColors.textSecondary,
                  )
                else
                  _Badge(label: '已复核', color: AppColors.textTertiary),
                if (mustCheck > 0) ...[
                  const SizedBox(width: AppSpacing.xs),
                  // A caution, as on the editor's rows; lavender is for
                  // things to press.
                  _Badge(
                    label: LyricSuggestedReviewStrings.mustCheckLabel(
                      mustCheck,
                    ),
                    color: AppColors.warning,
                  ),
                ] else if (unscored > 0 && pending > 0) ...[
                  // "Unknown" rather than a red zero — the same rule the editor
                  // toolbar follows.
                  const SizedBox(width: AppSpacing.xs),
                  _Badge(label: '未评分 $unscored', color: AppColors.textTertiary),
                ],
                if (pending > 0) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _TileMenu(
                    key: ValueKey('review-inbox:actions:${project.id}'),
                    saving: saving,
                    onMarkAllReviewed: onMarkAllReviewed,
                  ),
                ],
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(ProjectManifest project, LyricReviewQueue queue) {
    final parts = <String>['${queue.totalLines} 行'];
    final artist = project.artist?.trim();
    if (artist != null && artist.isNotEmpty) parts.insert(0, artist);
    parts.add('${queue.reviewedLines} 行已确认');
    return parts.join(' · ');
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return AppBadge(label: label, color: color);
  }
}

/// Opens and closes the folded group of fully reviewed projects.
class _ReviewedToggle extends StatelessWidget {
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  const _ReviewedToggle({
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        expanded: expanded,
        child: InkWell(
          key: const ValueKey('review-inbox:reviewed-toggle'),
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: layout.minimumInteractiveExtent,
            ),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    expanded ? '收起已复核的工程' : '已复核的工程 · $count 个',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The per-project 更多操作 menu, or a spinner while its save runs.
class _TileMenu extends StatelessWidget {
  final bool saving;
  final VoidCallback? onMarkAllReviewed;

  static const double spinnerSize = 20;

  const _TileMenu({
    super.key,
    required this.saving,
    required this.onMarkAllReviewed,
  });

  @override
  Widget build(BuildContext context) {
    final extent = AppResponsive.of(context).minimumInteractiveExtent;
    if (saving) {
      return SizedBox.square(
        dimension: extent,
        child: const Center(
          child: SizedBox.square(
            dimension: spinnerSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: ReviewInboxScreen.savingLabel,
            ),
          ),
        ),
      );
    }
    final onSelected = onMarkAllReviewed;
    return PopupMenuButton<VoidCallback>(
      tooltip: ReviewInboxScreen.moreActionsTooltip,
      enabled: onSelected != null,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        if (onSelected != null)
          PopupMenuItem<VoidCallback>(
            value: onSelected,
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.done_all_rounded),
              title: Text(ReviewInboxScreen.markAllReviewedLabel),
            ),
          ),
      ],
    );
  }
}

/// Confirms 全部标为已复核 with the numbers it changes.
class _MarkAllReviewedDialog extends StatelessWidget {
  final ReviewInboxEntry entry;

  const _MarkAllReviewedDialog({required this.entry});

  @override
  Widget build(BuildContext context) {
    final queue = entry.queue;
    return AlertDialog(
      title: const Text('${ReviewInboxScreen.markAllReviewedLabel}？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '「${entry.project.name}」的 ${queue.totalLines} 行都会记为人工确认，'
            '建议复核的 ${queue.needsReviewCount} 行会移出列表。',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '之后改动任何一行的文字或时间，那一行会重新列入建议复核。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(ReviewInboxScreen.markAllReviewedLabel),
        ),
      ],
    );
  }
}
