import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../project_detail_dependencies.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../../core/widgets/app_button_spinner.dart';
import '../../../../core/widgets/app_error_state.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../transcription/domain/models/spoken_language.dart';
import '../../../transcription/domain/models/transcription_degradation.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/models/transcription_run_progress.dart';
import '../../../transcription/domain/services/asr_runtime_manager.dart';
import '../../../transcription/domain/services/project_accompaniment_generator.dart';
import '../../../transcription/domain/services/project_transcription_workflow.dart';
import '../../../transcription/domain/services/transcription_settings_store.dart';
import '../../../transcription/presentation/widgets/asr_runtime_setup_dialog.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/repositories/project_repository.dart';
import '../widgets/project_detail_columns.dart';
import '../widgets/production_steps.dart';
import '../widgets/recognition_progress_card.dart';
import '../widgets/project_audio_sources_section.dart';
import '../widgets/project_deletion_flow.dart';
import '../widgets/project_sung_language_selector.dart';

class ProjectDetailScreen extends StatefulWidget {
  final String projectId;
  final ProjectDetailDependencies dependencies;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    required this.dependencies,
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

  /// The recognition in progress on this page (D-049), null otherwise.
  TranscriptionRunTracker? _runTracker;
  bool _isTranscribing = false;
  bool _isImportingStem = false;
  bool _importingVocal = false;

  /// 自动生成伴奏 running on this page (D-060), with its own progress.
  bool _isGeneratingAccompaniment = false;
  double _generationProgress = 0;
  String _generationMessage = '';

  /// Kept here rather than in the section: a refresh after an import shows
  /// the loading state and rebuilds the whole page.
  bool _audioSourcesExpanded = false;

  /// The workflow's 自动生成伴奏, when this device can separate.
  ProjectAccompanimentGenerator? get _accompanimentGenerator {
    final workflow = _transcriptionWorkflow;
    if (workflow is! ProjectAccompanimentGenerator) return null;
    // An unrelated interface: the check does not promote the local.
    final generator = workflow as ProjectAccompanimentGenerator;
    return generator.canGenerateAccompaniment ? generator : null;
  }

  bool get _busy =>
      _isTranscribing || _isImportingStem || _isGeneratingAccompaniment;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _repository = widget.dependencies.projectRepository;
    _transcriptionWorkflow = widget.dependencies.transcriptionWorkflow;
    _transcriptionSettingsStore =
        widget.dependencies.transcriptionSettingsStore;
    _asrRuntimeManager = widget.dependencies.asrRuntimeManager;
    _loadProject();

    _progressSubscription = _transcriptionWorkflow.progressStream.listen((
      progress,
    ) {
      if (!mounted) return;
      if (_isGeneratingAccompaniment) {
        setState(() {
          if (progress.progress > _generationProgress) {
            _generationProgress = progress.progress;
          }
          if (progress.message.isNotEmpty) {
            _generationMessage = progress.message;
          }
        });
        return;
      }
      final tracker = _runTracker;
      if (tracker == null) return;
      setState(() => tracker.record(progress, DateTime.now()));
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

  /// Opens the lyric editor and reads the project again when it closes, so
  /// the lyric card shows what was saved there rather than the copy loaded
  /// before the editor opened.
  Future<void> _openLyricEditor(ProjectManifest project) async {
    await Navigator.pushNamed(context, Routes.lyricEditorPath(project.id));
    if (mounted) await _refreshProject();
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
        dependencies: widget.dependencies.asrRuntimeSetupDependencies,
      ),
    );
    if (config == null) return current;

    await _transcriptionSettingsStore.save(config);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('本地歌词识别环境已保存')));
    }
    return config;
  }

  /// Saves this song's 演唱语言 (D-062); null is 自动判断. A draft that
  /// already exists is not touched: the message offers to recognise again.
  Future<void> _setSungLanguage(ProjectManifest project, String? code) async {
    if (_busy) return;
    final latest = await _repository.getProjectById(project.id);
    if (latest == null || !mounted) return;
    if (SpokenLanguageResolution.projectChoiceOf(latest.metadata) == code) {
      return;
    }
    final metadata = Map<String, dynamic>.from(latest.metadata);
    if (code == null) {
      metadata.remove(SpokenLanguageResolution.projectChoiceKey);
    } else {
      metadata[SpokenLanguageResolution.projectChoiceKey] = code;
    }
    final ProjectManifest saved;
    try {
      saved = await _repository.updateProjectIfUnchanged(
        latest.copyWith(metadata: metadata),
        expectedRevision: latest.revision,
      );
    } on ProjectUpdateConflictException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('工程刚刚被修改，请再选一次演唱语言')));
      }
      await _refreshProject();
      return;
    }
    await _refreshProject();
    if (!mounted) return;
    final label = ProjectSungLanguageSelector.labelOf(code);
    final applies = code == null ? '改为自动判断' : '已设为$label';
    final canRecognize = _isDesktop && saved.audioAsset != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved.hasLyrics ? '演唱语言$applies，重新识别后生效' : '演唱语言$applies，生成歌词时使用',
        ),
        duration: const Duration(seconds: 6),
        action: saved.hasLyrics && canRecognize
            ? SnackBarAction(
                label: '重新识别',
                onPressed: () {
                  if (mounted) _startTranscription(saved);
                },
              )
            : null,
      ),
    );
  }

  /// 删除工程 (D-063): back to where the project was opened from once it
  /// is gone.
  Future<void> _deleteProject(ProjectManifest project) async {
    final service = widget.dependencies.deletionService;
    if (service == null || _busy) return;
    final outcome = await deleteProjectsWithConfirmation(
      context,
      service: service,
      projects: [project],
    );
    if (!mounted || !outcome.deleted.contains(project.id)) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _startTranscription(ProjectManifest project) async {
    if (!_isDesktop || _busy || project.audioAsset == null) return;

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
      // Only the Whisper baseline blocks the button. Sending the user into
      // setup because the optional second engine is missing would refuse work
      // the app can actually finish (with a recorded degradation).
      if (!runtimeStatus.isBaselineReady) {
        config = await _configureTranscription();
        if (config == null) return;
      }
    }

    final tracker = TranscriptionRunTracker(startedAt: DateTime.now());
    setState(() {
      _isTranscribing = true;
      _runTracker = tracker;
    });

    try {
      await _transcriptionWorkflow.transcribeProject(project.id);
      // Separation may have linked a new vocal stem and accompaniment.
      await _syncPlaybackSources(
        project,
        await _repository.getProjectById(project.id),
      );
      await _refreshProject();
      if (mounted) {
        // The way to the next step is on the message itself (D-049).
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranscriptionRunText.finished(tracker.elapsed(DateTime.now())),
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: '去校对',
              // The message can outlive this page; it then does nothing.
              onPressed: () {
                if (mounted) _openLyricEditor(project);
              },
            ),
          ),
        );
      }
    } on TranscriptionException catch (error) {
      if (mounted) {
        final cancelled = error.kind == TranscriptionFailureKind.cancelled;
        // Stopping is the user's choice, not an error: no red, no retry.
        ScaffoldMessenger.of(context).showSnackBar(
          cancelled
              ? const SnackBar(content: Text(TranscriptionRunText.cancelled))
              : _failureSnackBar(error.toString(), project.id),
        );
      }
      await _refreshProject();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(_failureSnackBar('歌词识别失败：$error', project.id));
      }
      await _refreshProject();
    } finally {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _runTracker = null;
        });
      }
    }
  }

  SnackBar _failureSnackBar(String message, String projectId) {
    return SnackBar(
      content: Text(message),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: '重试',
        onPressed: () => _retryTranscription(projectId),
      ),
    );
  }

  /// Starts again from the latest copy of the project.
  Future<void> _retryTranscription(String projectId) async {
    final latest = await _repository.getProjectById(projectId);
    if (!mounted || latest == null) return;
    await _startTranscription(latest);
  }

  Future<void> _importStem(
    ProjectManifest project, {
    required bool vocal,
  }) async {
    if (!_isDesktop || _busy || project.audioAsset == null) return;
    // Reserve the operation before awaiting the confirmation dialog or picker.
    setState(() {
      _isImportingStem = true;
      _importingVocal = vocal;
    });
    final label = vocal ? '人声' : '伴奏';
    try {
      final existing = vocal
          ? project.audioAsset!.vocalPath
          : project.audioAsset!.instrumentalPath;
      if (existing != null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('更换$label？'),
            content: Text('工程将使用新选择的$label，原文件不会删除。请选择与原曲时间轴一致的音频。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('选择新$label'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final updated = vocal
          ? await widget.dependencies.vocalImporter.importVocalFor(project)
          : await widget.dependencies.accompanimentImporter.importFor(project);
      if (updated == null) return;
      var synchronized = false;
      final updater = widget.dependencies.playbackSourceUpdater;
      final replacement = updated.audioAsset;
      if (updater != null && replacement != null) {
        try {
          synchronized = await updater.updateActiveProjectSources(
            projectId: project.id,
            expected: project.audioAsset!,
            replacement: replacement,
          );
        } catch (_) {
          // Import is already saved; a playback sync failure is not an import failure.
        }
      }
      if (!mounted) return;
      await _refreshProject();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            synchronized
                ? '$label已导入，并同步到当前播放队列。'
                : '$label已导入。若此工程正在播放，请先切换歌曲，再重新打开工程播放器。',
          ),
          duration: const Duration(seconds: 7),
        ),
      );
    } on ProjectUpdateConflictException {
      if (!mounted) return;
      await _refreshProject();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('工程已发生变化，未替换$label；请刷新后重试。')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入$label失败，请检查文件和存储空间后重试。')));
    } finally {
      if (mounted) setState(() => _isImportingStem = false);
    }
  }

  /// Points a queue that is playing [before] at the tracks of [after], when
  /// separation changed them and the change cannot interrupt the audio.
  Future<bool> _syncPlaybackSources(
    ProjectManifest before,
    ProjectManifest? after,
  ) async {
    final updater = widget.dependencies.playbackSourceUpdater;
    final expected = before.audioAsset;
    final replacement = after?.audioAsset;
    if (updater == null || expected == null || replacement == null) {
      return false;
    }
    if (expected.instrumentalPath == replacement.instrumentalPath &&
        expected.vocalPath == replacement.vocalPath) {
      return false;
    }
    try {
      return await updater.updateActiveProjectSources(
        projectId: before.id,
        expected: expected,
        replacement: replacement,
      );
    } on Object {
      // The project is saved; reopening the player picks the tracks up.
      return false;
    }
  }

  /// 自动生成伴奏 (D-060): separation on its own, so a project can be sung
  /// over without recognising its lyrics first.
  Future<void> _generateAccompaniment(ProjectManifest project) async {
    final generator = _accompanimentGenerator;
    if (generator == null ||
        !_isDesktop ||
        _busy ||
        project.audioAsset == null) {
      return;
    }
    setState(() {
      _isGeneratingAccompaniment = true;
      _generationProgress = 0;
      _generationMessage = '正在准备生成伴奏';
      _audioSourcesExpanded = true;
    });
    try {
      // Separation needs the FFmpeg of the recognition environment.
      final config = await _transcriptionSettingsStore.load();
      if (config == null) {
        if (!mounted) return;
        final configured = await _configureTranscription();
        if (configured == null) return;
      }
      final result = await generator.generateAccompaniment(project.id);
      final synchronized = await _syncPlaybackSources(project, result.project);
      if (!mounted) return;
      await _refreshProject();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.linked && synchronized
                ? '${result.message}已同步到当前播放队列。'
                : result.message,
          ),
          duration: const Duration(seconds: 8),
          action: result.linked
              ? SnackBarAction(
                  label: '打开播放器',
                  onPressed: () {
                    if (mounted) {
                      Navigator.pushNamed(
                        context,
                        Routes.playerPath(project.id),
                      );
                    }
                  },
                )
              : null,
        ),
      );
    } on TranscriptionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          error.kind == TranscriptionFailureKind.cancelled
              ? const SnackBar(content: Text('已停止生成伴奏'))
              : SnackBar(
                  content: Text('生成伴奏失败：$error'),
                  backgroundColor: AppColors.error,
                  duration: const Duration(seconds: 10),
                ),
        );
        await _refreshProject();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成伴奏失败：$error'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 10),
          ),
        );
        await _refreshProject();
      }
    } finally {
      if (mounted) setState(() => _isGeneratingAccompaniment = false);
    }
  }

  Future<void> _cancelAccompanimentGeneration() async {
    if (!_isGeneratingAccompaniment) return;
    await _transcriptionWorkflow.cancel();
  }

  /// Asks before minutes of recognition are thrown away (D-049).
  Future<void> _cancelTranscription() async {
    final tracker = _runTracker;
    if (tracker != null) {
      final spent = tracker.elapsed(DateTime.now());
      final stop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('停止识别？'),
          content: Text(TranscriptionRunText.cancelConfirmation(spent)),
          actions: [
            TextButton(
              key: const ValueKey('recognition_keep_running'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续识别'),
            ),
            FilledButton(
              key: const ValueKey('recognition_confirm_stop'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('停止识别'),
            ),
          ],
        ),
      );
      if (stop != true || !mounted || !_isTranscribing) return;
    }
    await _transcriptionWorkflow.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: FutureBuilder<ProjectManifest?>(
        future: _projectFuture,
        builder: (context, snapshot) {
          // A refresh keeps the current page until the new copy arrives.
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
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
            isImportingStem: _isImportingStem,
            isImportingVocal: _importingVocal,
            runTracker: _runTracker,
            audioSourcesExpanded: _audioSourcesExpanded,
            onAudioSourcesExpandedChanged: (value) =>
                setState(() => _audioSourcesExpanded = value),
            onImportAccompaniment: () => _importStem(project, vocal: false),
            onImportVocal: () => _importStem(project, vocal: true),
            generation: AccompanimentGenerationView(
              onGenerate:
                  _accompanimentGenerator != null &&
                      project.audioAsset?.instrumentalPath == null
                  ? () => _generateAccompaniment(project)
                  : null,
              running: _isGeneratingAccompaniment,
              progress: _generationProgress,
              message: _generationMessage,
              onCancel: _cancelAccompanimentGeneration,
            ),
            onTranscribe: () => _startTranscription(project),
            onSungLanguageChanged: _busy
                ? null
                : (code) => _setSungLanguage(project, code),
            onCancelTranscription: _cancelTranscription,
            onConfigureTranscription: _configureTranscription,
            onOpenEditor: () => _openLyricEditor(project),
            onDelete: widget.dependencies.deletionService == null
                ? null
                : () => _deleteProject(project),
            deleteEnabled: !_busy,
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
    return const AppLoadingState(message: '正在读取工程');
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

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

class _ProjectDetailContent extends StatelessWidget {
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

  const _ProjectDetailContent({
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
                      _ProjectHero(project: project),
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
                              _ProcessingProgress(
                                stage: project.currentStage,
                                progress: project.progressPercent,
                              ),
                            const SizedBox(height: AppSpacing.md),
                            _LyricStatusCard(project: project),
                          ],
                        ),
                        side: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ActionPanel(
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
                            _ProjectMetadata(project: project),
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

class _ProcessingProgress extends StatelessWidget {
  final ProcessingStage stage;
  final double progress;

  const _ProcessingProgress({required this.stage, required this.progress});

  @override
  Widget build(BuildContext context) {
    final displayProgress = progress.clamp(0.0, 1.0).toDouble();
    final displayLabel = _stageLabel(stage);
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
                  _MetricChip(
                    label: '语言',
                    value: SpokenLanguagePolicy.label(document.language.trim()),
                  ),
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
    return AppBadge(label: '$label · $value');
  }
}

class _ActionPanel extends StatelessWidget {
  final ProjectManifest project;
  final bool isDesktop;
  final bool isTranscribing;
  final bool isImportingStem;
  final bool isImportingVocal;
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

  const _ActionPanel({
    required this.project,
    required this.isDesktop,
    required this.isTranscribing,
    required this.isImportingStem,
    required this.isImportingVocal,
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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            _nextStepText(project),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (project.hasLyrics)
            FilledButton.icon(
              style: buttonStyle,
              onPressed: onOpenEditor,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('校对歌词'),
            )
          else if (isDesktop)
            FilledButton.icon(
              style: buttonStyle,
              onPressed:
                  isTranscribing ||
                      isImportingStem ||
                      generation.running ||
                      project.audioAsset == null
                  ? null
                  : onTranscribe,
              icon: isTranscribing
                  ? const AppButtonSpinner()
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
              label: Text(project.canPlay ? '打开播放器' : '缺少工程音频'),
            ),
          ],
          if (isDesktop && project.hasLyrics && !isTranscribing) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: isImportingStem || generation.running
                  ? null
                  : onTranscribe,
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
          if (isDesktop && project.audioAsset != null) ...[
            const SizedBox(height: AppSpacing.md),
            ProjectSungLanguageSelector(
              value: SpokenLanguageResolution.projectChoiceOf(project.metadata),
              recognizedAs: SpokenLanguageResolution.describeProject(
                project.metadata,
              ),
              onChanged: isTranscribing ? null : onSungLanguageChanged,
            ),
          ],
          if (isDesktop && project.audioAsset != null) ...[
            const Divider(height: AppSpacing.xl),
            ProjectAudioSourcesSection(
              audio: project.audioAsset!,
              expanded: audioSourcesExpanded,
              onExpandedChanged: onAudioSourcesExpandedChanged,
              busy: isTranscribing || isImportingStem,
              isImportingStem: isImportingStem,
              isImportingVocal: isImportingVocal,
              onImportAccompaniment: onImportAccompaniment,
              onImportVocal: onImportVocal,
              generation: generation,
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
    return '歌词已准备好，工程需要音频才能进入播放器。';
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
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _ProjectMetadata extends StatelessWidget {
  final ProjectManifest project;

  const _ProjectMetadata({required this.project});

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

    return _SurfaceCard(
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
    ProjectStatus.ready => AppColors.success,
    ProjectStatus.error => AppColors.error,
  };
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
