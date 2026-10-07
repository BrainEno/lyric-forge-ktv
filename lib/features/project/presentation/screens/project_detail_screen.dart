import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/services/asr_runtime_manager.dart';
import '../../../transcription/domain/services/project_transcription_workflow.dart';
import '../../../transcription/domain/services/transcription_settings_store.dart';
import '../../../transcription/presentation/widgets/asr_runtime_setup_dialog.dart';
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
  late final AsrRuntimeManager _asrRuntimeManager;
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
    _asrRuntimeManager = ServiceLocatorGlobal.I.asrRuntimeManager;
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
      barrierDismissible: false,
      builder: (context) => AsrRuntimeSetupDialog(
        initialConfig: current,
      ),
    );
    if (config == null) return current;

    await _transcriptionSettingsStore.save(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地歌词识别环境已保存')),
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
            '新的识别草稿会替换当前歌词。Elysium Player 会先自动备份现有歌词，再开始本地识别。',
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
    } else {
      final runtimeStatus = await _asrRuntimeManager.inspect(config);
      if (!runtimeStatus.isReady) {
        config = await _configureTranscription();
        if (config == null) return;
      }
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
            content: Text('歌词识别失败：$error'),
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
    final spec = AppResponsive.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(spec.pageGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text('加载工程失败', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '工程文件暂时无法读取，请重新加载。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
              style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
              ),
            ),
          ],
        ),
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
                      _ProjectHero(project: project),
                      SizedBox(height: spec.sectionGap),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final twoPane = spec.supportsTwoPane;
                          final mainColumn = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ProcessingProgress(
                                stage: project.currentStage,
                                progress: project.progressPercent,
                                liveProgress:
                                    isTranscribing ? liveProgress : null,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _LyricStatusCard(project: project),
                            ],
                          );
                          final sideColumn = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ActionPanel(
                                project: project,
                                isDesktop: isDesktop,
                                isTranscribing: isTranscribing,
                                onTranscribe: onTranscribe,
                                onCancelTranscription:
                                    onCancelTranscription,
                                onConfigureTranscription:
                                    onConfigureTranscription,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _ProjectMetadata(project: project),
                            ],
                          );

                          if (!twoPane) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                sideColumn,
                                SizedBox(height: spec.sectionGap),
                                mainColumn,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: mainColumn),
                              SizedBox(width: spec.sectionGap),
                              SizedBox(
                                width: spec.sidePanelWidth,
                                child: sideColumn,
                              ),
                            ],
                          );
                        },
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

class _ProjectHero extends StatelessWidget {
  final ProjectManifest project;

  const _ProjectHero({required this.project});

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
          style: (spec.isCompact
                  ? Theme.of(context).textTheme.headlineSmall
                  : Theme.of(context).textTheme.headlineMedium)
              ?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _subtitle(project),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
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

  const _ProjectArtwork({
    required this.project,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final path = project.audioAsset?.thumbnailPath;
    final file = path == null ? null : File(path);
    final hasArtwork = file != null && file.existsSync();
    final size = spec.isShort
        ? 96.0
        : compact
            ? 112.0
            : spec.isExtraLarge
                ? 180.0
                : 164.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(gradient: AppColors.playerGradient),
        child: hasArtwork
            ? Image.file(file!, fit: BoxFit.cover)
            : Center(
                child: Icon(
                  Icons.album_rounded,
                  size: size * 0.42,
                  color: AppColors.textSecondary,
                ),
              ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final ProjectStatus status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(
        _statusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.hoverOverlay,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
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

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final displayProgress = (liveProgress?.progress ?? progress)
        .clamp(0.0, 1.0)
        .toDouble();
    final displayLabel = liveProgress?.message ?? _stageLabel(stage);
    final stages = <Widget>[
      _StagePill(
        label: '导入',
        icon: Icons.audio_file_outlined,
        completed: stage.index >= ProcessingStage.audioImported.index,
      ),
      _StagePill(
        label: '音频处理',
        icon: Icons.tune_rounded,
        completed: stage.index >= ProcessingStage.audioNormalized.index,
      ),
      _StagePill(
        label: '歌词识别',
        icon: Icons.auto_awesome,
        completed: stage.index >= ProcessingStage.transcriptionComplete.index,
        active: liveProgress != null,
      ),
      _StagePill(
        label: '歌词校对',
        icon: Icons.edit_note_rounded,
        completed: stage.index >= ProcessingStage.lyricsEdited.index,
      ),
      _StagePill(
        label: '导出',
        icon: Icons.ios_share_rounded,
        completed: stage.index >= ProcessingStage.exported.index,
      ),
    ];

    return _SurfaceCard(
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
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            minHeight: 5,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (spec.isCompactOrMedium || spec.isShort)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < stages.length; index++) ...[
                    if (index > 0) const SizedBox(width: AppSpacing.sm),
                    stages[index],
                  ],
                ],
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: stages,
            ),
        ],
      ),
    );
  }
}

class _StagePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool completed;
  final bool active;

  const _StagePill({
    required this.label,
    required this.icon,
    required this.completed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = completed || active ? AppColors.accent : AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: completed || active
            ? AppColors.accent.withAlpha(18)
            : AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            completed ? Icons.check_circle_rounded : icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: completed || active
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _LyricStatusCard extends StatelessWidget {
  final ProjectManifest project;

  const _LyricStatusCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final document = project.lyricDocument;
    final hasLyrics = project.hasLyrics;
    final lowConfidence = document?.metadata['lowConfidenceLineCount'];
    final fallback = document?.metadata['fallbackCandidateCount'];

    return _SurfaceCard(
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
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusMedium),
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
                          ? '自动识别结果仍建议进入歌词编辑器逐行校对。'
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
                  _MetricChip(label: '语言', value: document.language),
                if (lowConfidence != null)
                  _MetricChip(label: '低置信度', value: '$lowConfidence 行'),
                if (fallback != null)
                  _MetricChip(label: '重点复核', value: '$fallback 行'),
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(
        '$label · $value',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
            ),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  final ProjectManifest project;
  final bool isDesktop;
  final bool isTranscribing;
  final VoidCallback onTranscribe;
  final VoidCallback onCancelTranscription;
  final VoidCallback onConfigureTranscription;

  const _ActionPanel({
    required this.project,
    required this.isDesktop,
    required this.isTranscribing,
    required this.onTranscribe,
    required this.onCancelTranscription,
    required this.onConfigureTranscription,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
    );
    final outlinedStyle = OutlinedButton.styleFrom(
      minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
    );

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '下一步',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            _nextStepText(project),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (project.hasLyrics)
            FilledButton.icon(
              style: buttonStyle,
              onPressed: () => Navigator.pushNamed(
                context,
                Routes.lyricEditorPath(project.id),
              ),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('校对歌词'),
            )
          else if (isDesktop)
            FilledButton.icon(
              style: buttonStyle,
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
              label: Text(isTranscribing ? '正在生成歌词…' : '生成歌词'),
            )
          else
            const _DesktopRequiredNotice(),
          if (project.hasLyrics) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: outlinedStyle,
              onPressed: project.canPlay
                  ? () => Navigator.pushNamed(
                        context,
                        Routes.playerPath(project.id),
                      )
                  : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(project.canPlay ? '打开播放器' : '等待伴奏处理'),
            ),
          ],
          if (isDesktop && project.hasLyrics && !isTranscribing) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: onTranscribe,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('重新识别歌词'),
            ),
          ],
          if (isTranscribing) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: outlinedStyle,
              onPressed: onCancelTranscription,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('取消识别'),
            ),
          ],
          if (isDesktop) ...[
            const Divider(height: AppSpacing.xl),
            TextButton.icon(
              onPressed: isTranscribing ? null : onConfigureTranscription,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('识别环境与高级设置'),
            ),
          ],
        ],
      ),
    );
  }

  String _nextStepText(ProjectManifest project) {
    if (!project.hasLyrics) return '先生成歌词草稿，再进入逐行校对。';
    if (project.currentStage.index < ProcessingStage.lyricsEdited.index) {
      return '识别已经完成，建议先校对时间轴和文本。';
    }
    if (project.canPlay) return '歌词已经校对，可以进入播放器预览 KTV 效果。';
    return '歌词已准备好，等待伴奏处理后即可播放。';
  }
}

class _DesktopRequiredNotice extends StatelessWidget {
  const _DesktopRequiredNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Text(
        '本地歌词自动识别需要在桌面端完成。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
      ),
    );
  }
}

class _ProjectMetadata extends StatelessWidget {
  final ProjectManifest project;

  const _ProjectMetadata({required this.project});

  @override
  Widget build(BuildContext context) {
    final transcription = project.metadata['transcription'];
    final rows = <_MetadataValue>[
      _MetadataValue('创建', _formatDate(project.createdAt)),
      _MetadataValue('更新', _formatDate(project.updatedAt)),
      if (project.audioAsset != null)
        _MetadataValue('音频', project.audioAsset!.format.toUpperCase()),
      if (transcription is Map && transcription['detectedLanguage'] != null)
        _MetadataValue('识别语言', transcription['detectedLanguage'].toString()),
      if (transcription is Map && transcription['mode'] != null)
        _MetadataValue(
          '识别模式',
          transcription['mode'] == 'highestQuality' ? '最高质量' : 'Whisper',
        ),
      if (transcription is Map &&
          transcription['hardwareProfileLabel'] != null)
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

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '工程信息',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Tooltip(
                message: '工程 ID ${project.id}',
                child: const Icon(
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              row.value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  final Widget child;

  const _SurfaceCard({required this.child});

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
    ProjectStatus.ready => AppColors.accent,
    ProjectStatus.error => AppColors.error,
  };
}

String _stageLabel(ProcessingStage stage) {
  return switch (stage) {
    ProcessingStage.none => '等待开始',
    ProcessingStage.audioImported => '音频已经导入，可以开始制作歌词',
    ProcessingStage.audioNormalized => '音频已经标准化',
    ProcessingStage.vocalsSeparated => '人声与伴奏已经准备好',
    ProcessingStage.transcriptionComplete => '歌词草稿已经生成，等待人工校对',
    ProcessingStage.lyricsEdited => '歌词校对完成',
    ProcessingStage.exported => '工程已经导出',
  };
}
