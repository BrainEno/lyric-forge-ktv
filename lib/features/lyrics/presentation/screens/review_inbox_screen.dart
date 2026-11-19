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
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/lyric_review_queue.dart';

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

  @override
  void initState() {
    super.initState();
    _projects = widget.projectRepository;
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
          queue: LyricReviewQueue.build(document),
        ),
      );
    }
    entries.sort((left, right) {
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

  void _openImport() {
    Navigator.pushNamed(context, Routes.import);
  }

  void _openEditor(ProjectManifest project) {
    Navigator.pushNamed(context, Routes.lyricEditorPath(project.id));
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
    final showReviewed = pending.isEmpty || _showReviewed;

    Widget tile(ReviewInboxEntry entry) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: _ReviewInboxTile(
        key: ValueKey('review-inbox:${entry.project.id}'),
        entry: entry,
        onTap: () => _openEditor(entry.project),
      ),
    );

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Text(
          totalPending == 0
              ? '${entries.length} 个工程，暂时没有待复核的行'
              : '${entries.length} 个工程，共 $totalPending 行待复核',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
        ),
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
        title: const Text('校对'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<ReviewInboxEntry>>(
          future: _entriesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
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
        ),
      ),
    );
  }
}

class _ReviewInboxTile extends StatelessWidget {
  final ReviewInboxEntry entry;
  final VoidCallback onTap;

  static const double artworkExtent = 44;

  const _ReviewInboxTile({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pending = entry.queue.needsReviewCount;
    final lowConfidence = entry.queue.lowConfidenceCount;
    final unscored = entry.queue.unscoredLines;
    final project = entry.project;

    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
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
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (pending > 0)
                _Badge(label: '待复核 $pending', color: AppColors.accent)
              else
                const _Badge(label: '已复核', color: AppColors.textTertiary),
              if (lowConfidence > 0) ...[
                const SizedBox(width: AppSpacing.xs),
                _Badge(label: '低置信度 $lowConfidence', color: AppColors.warning),
              ] else if (unscored > 0 && pending > 0) ...[
                // "Unknown" rather than a red zero — the same rule the editor
                // toolbar follows.
                const SizedBox(width: AppSpacing.xs),
                _Badge(label: '未评分 $unscored', color: AppColors.textTertiary),
              ],
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ],
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
