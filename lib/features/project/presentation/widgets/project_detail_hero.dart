import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../domain/models/project_manifest.dart';

// The top of the project page: the cover, the name and what the project
// has (D-074).

class ProjectDetailHero extends StatelessWidget {
  final ProjectManifest project;

  const ProjectDetailHero({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final stacked = spec.isCompactOrMedium || spec.isShort;
    final heroPadding = spec.isCompact ? AppSpacing.md : AppSpacing.lg;
    final artwork = _ProjectArtwork(project: project, compact: stacked);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '歌曲工程',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 0.6,
              ),
            ),
            _StatusPill(status: project.status),
            if (project.lyricDocument?.lines.isNotEmpty == true)
              _MiniPill(
                icon: Icons.lyrics_rounded,
                label: '${project.lyricDocument!.lines.length} 行歌词',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          project.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              (spec.isCompact
                      ? Theme.of(context).textTheme.headlineSmall
                      : Theme.of(context).textTheme.headlineMedium)
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _subtitle(project),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (project.audioAsset != null)
              _MiniPill(
                icon: Icons.graphic_eq_rounded,
                label: project.audioAsset!.format.toUpperCase(),
              ),
            _MiniPill(
              icon: project.hasLyrics
                  ? Icons.check_circle_outline_rounded
                  : Icons.edit_note_rounded,
              label: project.hasLyrics ? '已有歌词草稿' : '等待生成歌词',
            ),
            if (project.canPlay)
              const _MiniPill(
                icon: Icons.play_circle_outline_rounded,
                label: '可进入播放器',
              ),
          ],
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(heroPadding),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                artwork,
                SizedBox(height: spec.isShort ? AppSpacing.md : AppSpacing.lg),
                details,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                artwork,
                const SizedBox(width: AppSpacing.xl),
                Expanded(child: details),
              ],
            ),
    );
  }

  String _subtitle(ProjectManifest project) {
    final parts = <String>[];
    if (project.artist?.trim().isNotEmpty == true) {
      parts.add(project.artist!.trim());
    }
    if (project.album?.trim().isNotEmpty == true) {
      parts.add(project.album!.trim());
    }
    return parts.isEmpty ? '本地音频 · Elysium Player KTV 工程' : parts.join(' · ');
  }
}

class _ProjectArtwork extends StatelessWidget {
  final ProjectManifest project;
  final bool compact;

  const _ProjectArtwork({required this.project, required this.compact});

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final size = spec.isShort
        ? 96.0
        : compact
        ? 112.0
        : spec.isExtraLarge
        ? 180.0
        : 164.0;

    // Shared cover: same placeholder as the library and the player, and no
    // broken image when the thumbnail cannot be decoded (audit C-04).
    return AppArtwork(
      path: project.audioAsset?.thumbnailPath,
      size: size,
      borderRadius: AppSpacing.radiusLarge,
    );
  }
}

class _StatusPill extends StatelessWidget {
  final ProjectStatus status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      label: _statusLabel(status),
      color: _statusColor(status),
      emphasized: true,
    );
  }
}

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return AppBadge(label: label, icon: icon);
  }
}

String _statusLabel(ProjectStatus status) {
  return switch (status) {
    ProjectStatus.draft => '草稿',
    ProjectStatus.importing => '导入中',
    ProjectStatus.processing => '处理中',
    ProjectStatus.transcribing => '识别中',
    ProjectStatus.editing => '待校对',
    ProjectStatus.ready => '就绪',
    ProjectStatus.error => '需要处理',
  };
}

Color _statusColor(ProjectStatus status) {
  return switch (status) {
    ProjectStatus.draft => AppColors.textTertiary,
    ProjectStatus.importing => AppColors.info,
    ProjectStatus.processing => AppColors.info,
    ProjectStatus.transcribing => AppColors.info,
    ProjectStatus.editing => AppColors.warning,
    ProjectStatus.ready => AppColors.success,
    ProjectStatus.error => AppColors.error,
  };
}
