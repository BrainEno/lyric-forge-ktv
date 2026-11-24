import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../transcription/domain/models/spoken_language.dart';
import '../../../transcription/domain/models/transcription_degradation.dart';
import '../../domain/models/lyric_review_overview.dart';
import '../../domain/models/project_manifest.dart';
import 'production_steps.dart';

// The project page's cards: production progress, the lyric draft, the
// project facts, and the surface they share (D-074).

class ProjectDetailSurfaceCard extends StatelessWidget {
  final Widget child;

  const ProjectDetailSurfaceCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Container(
      padding: EdgeInsets.all(spec.isCompact ? AppSpacing.sm : AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: child,
    );
  }
}

class ProjectDetailProgressCard extends StatelessWidget {
  final ProcessingStage stage;
  final double progress;

  const ProjectDetailProgressCard({
    super.key,
    required this.stage,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final displayProgress = progress.clamp(0.0, 1.0).toDouble();
    final displayLabel = _stageLabel(stage);
    return ProjectDetailSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '制作进度',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(displayProgress * 100).round()}%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: displayProgress,
            backgroundColor: AppColors.bgHighlight,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            minHeight: 5,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
          ),
          const SizedBox(height: AppSpacing.lg),
          ProductionSteps(
            steps: productionStepsFor(stage, transcribing: false),
          ),
        ],
      ),
    );
  }
}

/// The lyric draft at a glance. Since D-069 its review numbers are the
/// editor's 建议复核 and 必看, counted live, instead of the 低置信度 and
/// 重点复核 numbers frozen into the draft when it was recognised.
class ProjectDetailLyricStatusCard extends StatelessWidget {
  final ProjectManifest project;
  final ProjectLyricReviewOverview? review;

  const ProjectDetailLyricStatusCard({
    super.key,
    required this.project,
    this.review,
  });

  /// The sentence under the title for a project with lyrics.
  static String reviewSentence(ProjectLyricReviewOverview? review) {
    if (review == null) return '自动识别结果仍建议进入歌词编辑器逐行校对。';
    if (review.suggested == 0) {
      return review.reviewed > 0
          ? '建议复核的行都已确认，仍可在歌词编辑器里逐行检查。'
          : '没有发现需要复核的行，仍可在歌词编辑器里逐行检查。';
    }
    final must = review.mustCheck > 0 ? '，其中 ${review.mustCheck} 行必看' : '';
    return '还有 ${review.suggested} 行建议复核$must，在歌词编辑器里逐行确认。';
  }

  @override
  Widget build(BuildContext context) {
    final document = project.lyricDocument;
    final hasLyrics = project.hasLyrics;
    final review = this.review;

    return ProjectDetailSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (hasLyrics ? AppColors.accent : AppColors.info)
                      .withAlpha(22),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: Icon(
                  hasLyrics ? Icons.lyrics_rounded : Icons.edit_note_rounded,
                  color: hasLyrics ? AppColors.accent : AppColors.info,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasLyrics ? '歌词草稿已生成' : '还没有歌词草稿',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasLyrics
                          ? reviewSentence(review)
                          : '在桌面端完成本地识别后，会在这里生成可编辑时间轴。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasLyrics) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _MetricChip(
                  label: '歌词行',
                  value: document!.lines.length.toString(),
                ),
                if (document.language.trim().isNotEmpty)
                  _MetricChip(
                    label: '语言',
                    value: SpokenLanguagePolicy.label(document.language.trim()),
                  ),
                if (review != null)
                  _MetricChip(
                    label: '建议复核',
                    value: review.suggested > 0 ? '${review.suggested} 行' : '无',
                  ),
                if (review != null && review.mustCheck > 0)
                  _MetricChip(label: '必看', value: '${review.mustCheck} 行'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return AppBadge(label: '$label · $value');
  }
}

class ProjectDetailMetadataCard extends StatelessWidget {
  final ProjectManifest project;

  const ProjectDetailMetadataCard({super.key, required this.project});

  static String _modeLabel(Object? mode, {required bool degraded}) {
    final base = mode == 'highestQuality' ? '最高质量' : 'Whisper';
    return degraded ? '$base（已降级为单引擎）' : base;
  }

  @override
  Widget build(BuildContext context) {
    final transcription = project.metadata['transcription'];
    final lyricMetadata = project.lyricDocument?.metadata;
    final degraded = lyricMetadata != null
        ? TranscriptionQualityMetadata.isDegraded(lyricMetadata)
        : transcription is Map && transcription['degraded'] == true;
    final rows = <_MetadataValue>[
      _MetadataValue('创建', _formatDate(project.createdAt)),
      _MetadataValue('更新', _formatDate(project.updatedAt)),
      if (project.audioAsset != null)
        _MetadataValue('音频', project.audioAsset!.format.toUpperCase()),
      if (SpokenLanguageResolution.describeProject(project.metadata)
          case final language?)
        _MetadataValue('演唱语言', language),
      if (transcription is Map && transcription['mode'] != null)
        _MetadataValue(
          '识别模式',
          _modeLabel(transcription['mode'], degraded: degraded),
        ),
      if (degraded)
        _MetadataValue(
          '识别降级',
          (lyricMetadata == null
                  ? null
                  : TranscriptionQualityMetadata.explanationOf(
                      lyricMetadata,
                    )) ??
              '已降级为单引擎识别',
        ),
      if (transcription is Map && transcription['hardwareProfileLabel'] != null)
        _MetadataValue(
          '本机方案',
          transcription['hardwareProfileLabel'].toString(),
        ),
      if (project.lyricDocument?.metadata['fallbackCandidateCount'] != null)
        _MetadataValue(
          '备用复核',
          '${project.lyricDocument!.metadata['fallbackCandidateCount']} 行 / 采用 ${project.lyricDocument!.metadata['fallbackAppliedCount'] ?? 0} 行',
        ),
      if (project.lyricDocument?.metadata['fallbackStatus'] == 'failed')
        const _MetadataValue('备用引擎', '失败 · 已保留主结果'),
    ];

    return ProjectDetailSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '工程信息',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Tooltip(
                message: '工程 ID ${project.id}',
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final row in rows) _MetadataRow(row: row),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _MetadataValue {
  final String label;
  final String value;

  const _MetadataValue(this.label, this.value);
}

class _MetadataRow extends StatelessWidget {
  final _MetadataValue row;

  const _MetadataRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    if (spec.isCompact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 2),
            Text(
              row.value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              row.label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
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

String _stageLabel(ProcessingStage stage) {
  return switch (stage) {
    ProcessingStage.none => '等待开始',
    ProcessingStage.audioImported => '音频已经导入，可以开始制作歌词',
    ProcessingStage.audioNormalized => '音频已经标准化',
    ProcessingStage.vocalsSeparated => '工程记录了音轨分离阶段',
    ProcessingStage.transcriptionComplete => '歌词草稿已经生成，等待人工校对',
    ProcessingStage.lyricsEdited => '歌词校对完成',
    ProcessingStage.exported => '工程已经导出',
  };
}
