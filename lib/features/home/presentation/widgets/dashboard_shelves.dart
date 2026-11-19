// The dashboard's lower sections: section headers, the recent listening
// shelf, the recent project grid, and their empty and loading states.
//
// Split out of `dashboard_screen.dart` (audit D-06).

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../player/domain/models/play_history.dart';
import '../../../project/domain/models/project_manifest.dart';
import 'dashboard_surfaces.dart';

class DashboardSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? action;
  final VoidCallback? onAction;

  const DashboardSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
    final label = action;
    if (label == null) return info;
    final button = TextButton(onPressed: onAction, child: Text(label));
    if (layout.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          info,
          const SizedBox(height: AppSpacing.xs),
          button,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: info),
        button,
      ],
    );
  }
}

class DashboardRecentShelf extends StatelessWidget {
  final List<PlayHistory> histories;
  final ValueChanged<PlayHistory> onPlay;

  const DashboardRecentShelf({
    super.key,
    required this.histories,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return SizedBox(
      height: layout.isCompact ? 174 : 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: histories.length,
        separatorBuilder: (_, _) => SizedBox(width: layout.sectionGap / 2),
        itemBuilder: (context, index) => _ListeningCard(
          history: histories[index],
          width: layout.isCompact ? 146 : 160,
          onTap: () => onPlay(histories[index]),
        ),
      ),
    );
  }
}

class _ListeningCard extends StatelessWidget {
  final PlayHistory history;
  final double width;
  final VoidCallback onTap;

  const _ListeningCard({
    required this.history,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: InkWell(
          onTap: onTap,
          hoverColor: AppColors.hoverOverlay,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The cover recorded with the history entry, through the
                // shared artwork component. Every card used to draw the same
                // gradient and note icon (audit D-04); entries saved before
                // covers were recorded still get the shared placeholder.
                Expanded(
                  child: AppArtwork(
                    path: history.artworkPath,
                    borderRadius: AppSpacing.radiusMedium,
                    placeholderIcon: Icons.music_note_rounded,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  history.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  history.artist?.trim().isNotEmpty == true
                      ? history.artist!
                      : history.formattedPlayedAt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dashboardMutedLabel(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardProjectGrid extends StatelessWidget {
  final List<ProjectManifest> projects;
  final ValueChanged<ProjectManifest> onOpen;

  const DashboardProjectGrid({
    super.key,
    required this.projects,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final columns = layout.gridColumns(minTileWidth: 280, min: 1, max: 4);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: projects.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: columns == 1
                ? (layout.isCompact ? 2.05 : 2.35)
                : 1.35,
          ),
          itemBuilder: (context, index) => _ProjectCard(
            project: projects[index],
            onTap: () => onOpen(projects[index]),
          ),
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ProjectManifest project;
  final VoidCallback onTap;

  const _ProjectCard({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lyricCount = project.lyricDocument?.lines.length ?? 0;
    final layout = AppResponsive.of(context);
    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.hoverOverlay,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: Padding(
          padding: EdgeInsets.all(
            layout.isCompact ? AppSpacing.sm : AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DashboardArtwork(
                    path: project.audioAsset?.thumbnailPath,
                    size: layout.isCompact ? 52 : 64,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          project.artist?.trim().isNotEmpty == true
                              ? project.artist!
                              : '歌词工程',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: dashboardMutedLabel(context),
                        ),
                      ],
                    ),
                  ),
                  _StatusDot(project.status),
                ],
              ),
              const Spacer(),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _MetaChip(
                    icon: project.hasLyrics
                        ? Icons.lyrics_rounded
                        : Icons.graphic_eq_rounded,
                    label: project.hasLyrics ? '$lyricCount 行歌词' : '待生成歌词',
                    accent: project.hasLyrics,
                  ),
                  _MetaChip(
                    icon: Icons.schedule_rounded,
                    label: _stageLabel(project.currentStage),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                value: project.progressPercent.clamp(0.0, 1.0).toDouble(),
                minHeight: 3,
                backgroundColor: AppColors.bgHighlight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final ProjectStatus status;
  const _StatusDot(this.status);

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ProjectStatus.ready => AppColors.success,
      ProjectStatus.error => AppColors.error,
      ProjectStatus.transcribing || ProjectStatus.processing => AppColors.info,
      ProjectStatus.editing => AppColors.warning,
      _ => AppColors.textTertiary,
    };
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  const _MetaChip({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      label: label,
      icon: icon,
      tone: accent ? AppBadgeTone.accent : AppBadgeTone.neutral,
    );
  }
}

/// Dashboard card for an empty or failed shelf. The layout comes from the
/// shared [AppEmptyState] inline density; this only adds the card frame and
/// the error colour.
class DashboardEmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  /// Button label; null leaves the card without an action.
  final String? action;
  final VoidCallback onAction;
  final bool isError;

  const DashboardEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final label = action;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(
            layout.isCompact ? AppSpacing.md : AppSpacing.xl,
          ),
          decoration: dashboardCardDecoration(),
          child: AppEmptyState(
            density: AppEmptyStateDensity.inline,
            icon: icon,
            iconColor: isError ? AppColors.error : null,
            title: title,
            message: message,
            actions: [
              if (label != null)
                OutlinedButton(onPressed: onAction, child: Text(label)),
            ],
          ),
        );
      },
    );
  }
}

class DashboardLoadingBlock extends StatelessWidget {
  final double height;
  const DashboardLoadingBlock({super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

String _stageLabel(ProcessingStage stage) => switch (stage) {
  ProcessingStage.none => '待开始',
  ProcessingStage.audioImported => '已导入',
  ProcessingStage.audioNormalized => '音频处理',
  ProcessingStage.vocalsSeparated => '人声已分离',
  ProcessingStage.transcriptionComplete => '歌词已识别',
  ProcessingStage.lyricsEdited => '歌词已校对',
  ProcessingStage.exported => '已导出',
};
