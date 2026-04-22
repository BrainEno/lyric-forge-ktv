import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/repositories/project_repository.dart';

/// Project detail screen - displays project information and processing status.
/// Entry point for lyrics editing and player access.
class ProjectDetailScreen extends StatefulWidget {
  final String projectId;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late final ProjectRepository _repository;
  late Future<ProjectManifest?> _projectFuture;

  @override
  void initState() {
    super.initState();
    _repository = ServiceLocatorGlobal.I.projectRepository;
    _loadProject();
  }

  void _loadProject() {
    _projectFuture = _repository.getProjectById(widget.projectId);
  }

  Future<void> _refreshProject() async {
    setState(_loadProject);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: FutureBuilder<ProjectManifest?>(
        future: _projectFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingState();
          }

          if (snapshot.hasError || snapshot.data == null) {
            return _ErrorState(
              onRetry: _refreshProject,
            );
          }

          final project = snapshot.data!;
          return _ProjectDetailContent(
            project: project,
            onRefresh: _refreshProject,
          );
        },
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: AppColors.error,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '加载工程失败',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _ProjectDetailContent extends StatelessWidget {
  final ProjectManifest project;
  final VoidCallback onRefresh;

  const _ProjectDetailContent({
    required this.project,
    required this.onRefresh,
  });

  String _getStatusLabel(ProjectStatus status) {
    return switch (status) {
      ProjectStatus.draft => '草稿',
      ProjectStatus.importing => '导入中',
      ProjectStatus.processing => '处理中',
      ProjectStatus.transcribing => '识别中',
      ProjectStatus.editing => '编辑中',
      ProjectStatus.ready => '就绪',
      ProjectStatus.error => '错误',
    };
  }

  Color _getStatusColor(ProjectStatus status) {
    return switch (status) {
      ProjectStatus.draft => AppColors.textTertiary,
      ProjectStatus.importing => AppColors.info,
      ProjectStatus.processing => AppColors.info,
      ProjectStatus.transcribing => AppColors.info,
      ProjectStatus.editing => AppColors.warning,
      ProjectStatus.ready => AppColors.accent,
      ProjectStatus.error => AppColors.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.accent,
      backgroundColor: AppColors.bgElevated,
      child: CustomScrollView(
        slivers: [
          // App Bar with project title
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.bgBase,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                project.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.playerGradient,
                ),
                child: Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    ),
                    child: const Icon(
                      Icons.album,
                      size: 64,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Project info card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(project.status).withAlpha(26),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
                    ),
                    child: Text(
                      _getStatusLabel(project.status),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: _getStatusColor(project.status),
                          ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Artist & Album
                  if (project.artist != null) ...[
                    Text(
                      project.artist!,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  if (project.album != null)
                    Text(
                      project.album!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),

                  const SizedBox(height: AppSpacing.lg),

                  // Processing progress
                  _ProcessingProgress(
                    stage: project.currentStage,
                    progress: project.progressPercent,
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // Action buttons
                  _ActionButtons(project: project),

                  const SizedBox(height: AppSpacing.xl),

                  // Project metadata
                  _ProjectMetadata(project: project),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessingProgress extends StatelessWidget {
  final ProcessingStage stage;
  final double progress;

  const _ProcessingProgress({
    required this.stage,
    required this.progress,
  });

  String _getStageLabel(ProcessingStage stage) {
    return switch (stage) {
      ProcessingStage.none => '等待开始',
      ProcessingStage.audioImported => '音频已导入',
      ProcessingStage.audioNormalized => '音频已标准化',
      ProcessingStage.vocalsSeparated => '人声已分离',
      ProcessingStage.transcriptionComplete => '歌词已识别',
      ProcessingStage.lyricsEdited => '歌词已编辑',
      ProcessingStage.exported => '已导出',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '处理进度',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.bgHighlight,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            minHeight: 6,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getStageLabel(stage),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.accent,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final ProjectManifest project;

  const _ActionButtons({required this.project});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary: Play if ready, Edit if has lyrics
        ElevatedButton.icon(
          onPressed: project.canPlay
              ? () => Navigator.pushNamed(
                    context,
                    Routes.playerPath(project.id),
                  )
              : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(project.canPlay ? '开始演唱' : '等待音频处理'),
        ),

        const SizedBox(height: AppSpacing.md),

        // Secondary: Edit lyrics
        OutlinedButton.icon(
          onPressed: () => Navigator.pushNamed(
            context,
            Routes.lyricEditorPath(project.id),
          ),
          icon: const Icon(Icons.edit),
          label: const Text('编辑歌词'),
        ),
      ],
    );
  }
}

class _ProjectMetadata extends StatelessWidget {
  final ProjectManifest project;

  const _ProjectMetadata({required this.project});

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '工程信息',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          _MetadataRow(
            label: '创建时间',
            value: _formatDate(project.createdAt),
          ),
          _MetadataRow(
            label: '更新时间',
            value: _formatDate(project.updatedAt),
          ),
          _MetadataRow(
            label: '工程 ID',
            value: project.id.substring(0, project.id.length > 8 ? 8 : project.id.length),
          ),
          if (project.hasLyrics)
            const _MetadataRow(
              label: '歌词状态',
              value: '已就绪',
            ),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
