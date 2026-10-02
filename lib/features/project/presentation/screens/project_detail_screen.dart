import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/services/project_transcription_workflow.dart';
import '../../../transcription/domain/services/transcription_settings_store.dart';
import '../../../transcription/presentation/widgets/transcription_config_dialog.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/repositories/project_repository.dart';

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
  late final ProjectTranscriptionWorkflow _transcriptionWorkflow;
  late final TranscriptionSettingsStore _transcriptionSettingsStore;
  late Future<ProjectManifest?> _projectFuture;

  StreamSubscription<TranscriptionProgress>? _progressSubscription;
  TranscriptionProgress? _liveProgress;
  bool _isTranscribing = false;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _repository = ServiceLocatorGlobal.I.projectRepository;
    _transcriptionWorkflow =
        ServiceLocatorGlobal.I.projectTranscriptionWorkflow;
    _transcriptionSettingsStore =
        ServiceLocatorGlobal.I.transcriptionSettingsStore;
    _loadProject();

    _progressSubscription =
        _transcriptionWorkflow.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() => _liveProgress = progress);
    });
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  void _loadProject() {
    _projectFuture = _repository.getProjectById(widget.projectId);
  }

  Future<void> _refreshProject() async {
    setState(_loadProject);
  }

  Future<TranscriptionConfig?> _configureTranscription() async {
    final current = await _transcriptionSettingsStore.load();
    if (!mounted) return null;

    final config = await showDialog<TranscriptionConfig>(
      context: context,
      builder: (context) => TranscriptionConfigDialog(
        initialConfig: current,
      ),
    );
    if (config == null) return current;

    await _transcriptionSettingsStore.save(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地歌词识别设置已保存')),
      );
    }
    return config;
  }

  Future<void> _startTranscription(ProjectManifest project) async {
    if (!_isDesktop || _isTranscribing || project.audioAsset == null) return;

    if (project.hasLyrics) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重新识别歌词？'),
          content: const Text(
            '新的识别草稿会替换当前歌词。LyricForge 会先自动备份现有歌词，再开始本地识别。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('备份并重新识别'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    var config = await _transcriptionSettingsStore.load();
    if (config == null) {
      config = await _configureTranscription();
      if (config == null) return;
    }

    setState(() {
      _isTranscribing = true;
      _liveProgress = const TranscriptionProgress(
        stage: TranscriptionStage.validating,
        progress: 0.0,
        message: '准备本地歌词识别',
      );
    });

    try {
      await _transcriptionWorkflow.transcribeProject(project.id);
      await _refreshProject();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('歌词草稿已生成，请进入编辑器校对')),
        );
      }
    } on TranscriptionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
      await _refreshProject();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('歌词识别失败：' + error.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
      await _refreshProject();
    } finally {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _liveProgress = null;
        });
      }
    }
  }

  Future<void> _cancelTranscription() async {
    await _transcriptionWorkflow.cancel();
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
            return _ErrorState(onRetry: _refreshProject);
          }

          final project = snapshot.data!;
          return _ProjectDetailContent(
            project: project,
            onRefresh: _refreshProject,
            isDesktop: _isDesktop,
            isTranscribing: _isTranscribing,
            liveProgress: _liveProgress,
            onTranscribe: () => _startTranscription(project),
            onCancelTranscription: _cancelTranscription,
            onConfigureTranscription: _configureTranscription,
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
    return const Center(child: CircularProgressIndicator());
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
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: AppSpacing.md),
          Text('加载工程失败', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _ProjectDetailContent extends StatelessWidget {
  final ProjectManifest project;
  final VoidCallback onRefresh;
  final bool isDesktop;
  final bool isTranscribing;
  final TranscriptionProgress? liveProgress;
  final VoidCallback onTranscribe;
  final VoidCallback onCancelTranscription;
  final VoidCallback onConfigureTranscription;

  const _ProjectDetailContent({
    required this.project,
    required this.onRefresh,
    required this.isDesktop,
    required this.isTranscribing,
    required this.liveProgress,
    required this.onTranscribe,
    required this.onCancelTranscription,
    required this.onConfigureTranscription,
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
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.bgBase,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                project.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              background: Container(
                decoration: BoxDecoration(gradient: AppColors.playerGradient),
                child: Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusLarge),
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(project.status).withAlpha(26),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusCircular),
                    ),
                    child: Text(
                      _getStatusLabel(project.status),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: _getStatusColor(project.status),
                          ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                  _ProcessingProgress(
                    stage: project.currentStage,
                    progress: project.progressPercent,
                    liveProgress: isTranscribing ? liveProgress : null,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _ActionButtons(
                    project: project,
                    isDesktop: isDesktop,
                    isTranscribing: isTranscribing,
                    onTranscribe: onTranscribe,
                    onCancelTranscription: onCancelTranscription,
                    onConfigureTranscription: onConfigureTranscription,
                  ),
                  const SizedBox(height: AppSpacing.xl),
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
  final TranscriptionProgress? liveProgress;

  const _ProcessingProgress({
    required this.stage,
    required this.progress,
    this.liveProgress,
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
    final displayProgress = liveProgress?.progress ?? progress;
    final displayLabel = liveProgress?.message ?? _getStageLabel(stage);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('处理进度', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: displayProgress,
            backgroundColor: AppColors.bgHighlight,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.accent),
            minHeight: 6,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  displayLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                (displayProgress * 100).toInt().toString() + '%',
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
  final bool isDesktop;
  final bool isTranscribing;
  final VoidCallback onTranscribe;
  final VoidCallback onCancelTranscription;
  final VoidCallback onConfigureTranscription;

  const _ActionButtons({
    required this.project,
    required this.isDesktop,
    required this.isTranscribing,
    required this.onTranscribe,
    required this.onCancelTranscription,
    required this.onConfigureTranscription,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDesktop) ...[
          ElevatedButton.icon(
            onPressed: isTranscribing || project.audioAsset == null
                ? null
                : onTranscribe,
            icon: isTranscribing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.pureWhite,
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              isTranscribing
                  ? '正在本地识别...'
                  : project.hasLyrics
                      ? '重新识别歌词'
                      : '生成歌词',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (isTranscribing)
            OutlinedButton.icon(
              onPressed: onCancelTranscription,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('取消识别'),
            )
          else
            TextButton.icon(
              onPressed: onConfigureTranscription,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('本地识别设置'),
            ),
          const SizedBox(height: AppSpacing.md),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            child: const Text('歌词自动识别需要在桌面端本地完成'),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        ElevatedButton.icon(
          onPressed: project.canPlay
              ? () => Navigator.pushNamed(
                    context,
                    Routes.playerPath(project.id),
                  )
              : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(project.canPlay ? '打开播放器' : '等待音频处理'),
        ),
        const SizedBox(height: AppSpacing.md),
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
    return date.year.toString() +
        '-' +
        date.month.toString().padLeft(2, '0') +
        '-' +
        date.day.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final transcription = project.metadata['transcription'];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('工程信息', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          _MetadataRow(label: '创建时间', value: _formatDate(project.createdAt)),
          _MetadataRow(label: '更新时间', value: _formatDate(project.updatedAt)),
          _MetadataRow(
            label: '工程 ID',
            value: project.id.substring(
              0,
              project.id.length > 8 ? 8 : project.id.length,
            ),
          ),
          if (project.audioAsset != null)
            _MetadataRow(
              label: '音频格式',
              value: project.audioAsset!.format.toUpperCase(),
            ),
          if (project.hasLyrics)
            const _MetadataRow(label: '歌词状态', value: '待校对 / 已生成'),
          if (transcription is Map && transcription['detectedLanguage'] != null)
            _MetadataRow(
              label: '识别语言',
              value: transcription['detectedLanguage'].toString(),
            ),
          if (transcription is Map && transcription['mode'] != null)
            _MetadataRow(
              label: '识别模式',
              value: transcription['mode'] == 'highestQuality'
                  ? '最高质量'
                  : 'Whisper',
            ),
          if (transcription is Map &&
              transcription['hardwareProfileLabel'] != null)
            _MetadataRow(
              label: '本机 Profile',
              value: transcription['hardwareProfileLabel'].toString(),
            ),
          if (project.lyricDocument?.metadata['fallbackCandidateCount'] != null)
            _MetadataRow(
              label: '备用复核',
              value:
                  project.lyricDocument!.metadata['fallbackCandidateCount'].toString() +
                      ' 行 / 采用 ' +
                      (project.lyricDocument!.metadata['fallbackAppliedCount'] ?? 0)
                          .toString() +
                      ' 行',
            ),
          if (project.lyricDocument?.metadata['fallbackStatus'] == 'failed')
            const _MetadataRow(
              label: '备用引擎',
              value: '第二意见识别失败 · 主识别结果已保留',
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
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
