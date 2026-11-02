import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
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
  final ProjectRepository? projectRepository;

  const ReviewInboxScreen({super.key, this.projectRepository});

  @override
  State<ReviewInboxScreen> createState() => _ReviewInboxScreenState();
}

class _ReviewInboxScreenState extends State<ReviewInboxScreen> {
  late ProjectRepository _projects;
  late Future<List<ReviewInboxEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _projects =
        widget.projectRepository ?? ServiceLocatorGlobal.I.projectRepository;
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

  void _openEditor(ProjectManifest project) {
    Navigator.pushNamed(context, Routes.lyricEditorPath(project.id));
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
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Message(
                icon: Icons.error_outline_rounded,
                title: '工程列表加载失败',
                message: '歌词工程暂时无法读取，可以重新加载一次。',
                action: '重试',
                onAction: _refresh,
              );
            }
            final entries = snapshot.data ?? const <ReviewInboxEntry>[];
            if (entries.isEmpty) {
              return _Message(
                icon: Icons.playlist_add_check_circle_outlined,
                title: '还没有可校对的歌词',
                message: '导入并识别一首歌之后，它的歌词会出现在这里，并标出还有多少行需要复核。',
                action: '去导入',
                onAction: () => Navigator.pushNamed(context, Routes.import),
              );
            }
            final totalPending = entries.fold<int>(
              0,
              (sum, entry) => sum + entry.queue.needsReviewCount,
            );
            return RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.accent,
              backgroundColor: AppColors.bgElevated,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: layout.pageGutter,
                  vertical: AppSpacing.md,
                ),
                itemCount: entries.length + 1,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text(
                        totalPending == 0
                            ? '${entries.length} 个工程，暂时没有待复核的行'
                            : '${entries.length} 个工程，共 $totalPending 行待复核',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  final entry = entries[index - 1];
                  return _ReviewInboxTile(
                    entry: entry,
                    onTap: () => _openEditor(entry.project),
                  );
                },
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

  const _ReviewInboxTile({required this.entry, required this.onTap});

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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: const Icon(
                  Icons.lyrics_outlined,
                  size: 22,
                  color: AppColors.textSecondary,
                ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.all(spec.pageGutter.clamp(16, 32).toDouble()),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppColors.textTertiary),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonal(onPressed: onAction, child: Text(action)),
            ],
          ),
        ),
      ),
    );
  }
}
