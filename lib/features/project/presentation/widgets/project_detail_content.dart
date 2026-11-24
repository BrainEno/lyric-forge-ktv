import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_error_state.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../transcription/domain/models/transcription_run_progress.dart';
import '../../domain/models/lyric_review_overview.dart';
import '../../domain/models/project_manifest.dart';
import 'project_audio_sources_section.dart';
import 'project_detail_action_panel.dart';
import 'project_detail_cards.dart';
import 'project_detail_columns.dart';
import 'project_detail_hero.dart';
import 'recognition_progress_card.dart';

// The project page's layout: the app bar, the hero, then the progress and
// lyric cards beside the next steps and the project facts (D-074).

class ProjectDetailLoadingState extends StatelessWidget {
  const ProjectDetailLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppLoadingState(message: '正在读取工程');
  }
}

class ProjectDetailErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const ProjectDetailErrorState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppErrorState(
      title: '加载工程失败',
      message: '工程文件暂时无法读取，请重新加载。',
      retryLabel: '重新加载',
      onRetry: onRetry,
    );
  }
}

class ProjectDetailContent extends StatelessWidget {
  final ProjectManifest project;
  final VoidCallback onRefresh;
  final bool isDesktop;
  final bool isTranscribing;
  final bool isImportingStem;
  final bool isImportingVocal;
  final TranscriptionRunTracker? runTracker;
  final bool audioSourcesExpanded;
  final ValueChanged<bool> onAudioSourcesExpandedChanged;
  final VoidCallback onImportAccompaniment;
  final VoidCallback onImportVocal;
  final AccompanimentGenerationView generation;
  final VoidCallback onTranscribe;
  final ValueChanged<String?>? onSungLanguageChanged;
  final VoidCallback onCancelTranscription;
  final VoidCallback onConfigureTranscription;
  final VoidCallback onOpenEditor;

  /// Null hides 删除工程.
  final VoidCallback? onDelete;
  final bool deleteEnabled;

  /// The editor's 建议复核 counts; null when unknown.
  final ProjectLyricReviewOverview? review;

  const ProjectDetailContent({
    super.key,
    required this.project,
    required this.onRefresh,
    required this.isDesktop,
    required this.isTranscribing,
    required this.isImportingStem,
    required this.isImportingVocal,
    required this.runTracker,
    required this.audioSourcesExpanded,
    required this.onAudioSourcesExpandedChanged,
    required this.onImportAccompaniment,
    required this.onImportVocal,
    required this.generation,
    required this.onTranscribe,
    required this.onSungLanguageChanged,
    required this.onCancelTranscription,
    required this.onConfigureTranscription,
    required this.onOpenEditor,
    this.onDelete,
    this.deleteEnabled = true,
    this.review,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final verticalStart = spec.isCompact || spec.isShort
        ? AppSpacing.md
        : AppSpacing.lg;
    final verticalEnd = spec.isCompact || spec.isShort
        ? AppSpacing.xl
        : AppSpacing.xxxl;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.accent,
      backgroundColor: AppColors.bgElevated,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bgBase,
            surfaceTintColor: Colors.transparent,
            title: Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              SizedBox(
                width: spec.minimumInteractiveExtent,
                height: spec.minimumInteractiveExtent,
                child: IconButton(
                  tooltip: '刷新工程',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              if (onDelete != null)
                PopupMenuButton<String>(
                  key: const ValueKey('project_detail_more'),
                  tooltip: '更多',
                  onSelected: (value) {
                    if (value == 'delete') onDelete!();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      key: const ValueKey('project_detail_delete'),
                      value: 'delete',
                      enabled: deleteEnabled,
                      child: Text(deleteEnabled ? '删除工程' : '删除工程（处理中不可用）'),
                    ),
                  ],
                ),
              SizedBox(width: spec.isCompact ? 4 : AppSpacing.sm),
            ],
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: spec.contentMaxWidth),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    spec.pageGutter,
                    verticalStart,
                    spec.pageGutter,
                    verticalEnd,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProjectDetailHero(project: project),
                      SizedBox(height: spec.sectionGap),
                      ProjectDetailColumns(
                        gap: spec.sectionGap,
                        main: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isTranscribing && runTracker != null)
                              RecognitionProgressCard(
                                tracker: runTracker!,
                                onCancel: onCancelTranscription,
                              )
                            else
                              ProjectDetailProgressCard(
                                stage: project.currentStage,
                                progress: project.progressPercent,
                              ),
                            const SizedBox(height: AppSpacing.md),
                            ProjectDetailLyricStatusCard(
                              project: project,
                              review: review,
                            ),
                          ],
                        ),
                        side: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ProjectDetailActionPanel(
                              project: project,
                              isDesktop: isDesktop,
                              isTranscribing: isTranscribing,
                              isImportingStem: isImportingStem,
                              isImportingVocal: isImportingVocal,
                              audioSourcesExpanded: audioSourcesExpanded,
                              onAudioSourcesExpandedChanged:
                                  onAudioSourcesExpandedChanged,
                              onImportAccompaniment: onImportAccompaniment,
                              onImportVocal: onImportVocal,
                              generation: generation,
                              onTranscribe: onTranscribe,
                              onSungLanguageChanged: onSungLanguageChanged,
                              onCancelTranscription: onCancelTranscription,
                              onConfigureTranscription:
                                  onConfigureTranscription,
                              onOpenEditor: onOpenEditor,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            ProjectDetailMetadataCard(project: project),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
