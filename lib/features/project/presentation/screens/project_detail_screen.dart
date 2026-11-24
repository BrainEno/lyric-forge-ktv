import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/routes.dart';
import '../project_detail_dependencies.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../transcription/domain/models/spoken_language.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/models/transcription_run_progress.dart';
import '../../../transcription/domain/services/asr_runtime_manager.dart';
import '../../../transcription/domain/services/project_accompaniment_generator.dart';
import '../../../transcription/domain/services/project_transcription_workflow.dart';
import '../../../transcription/domain/services/transcription_settings_store.dart';
import '../../../transcription/presentation/widgets/asr_runtime_setup_dialog.dart';
import '../../domain/models/lyric_review_overview.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/repositories/project_repository.dart';
import '../widgets/project_audio_sources_section.dart';
import '../widgets/project_detail_content.dart';
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

  /// The 建议复核 counts of [_reviewSource], worked out once per loaded copy
  /// rather than on every rebuild: recognition progress rebuilds this page
  /// several times a second, and counting walks every lyric line.
  ProjectManifest? _reviewSource;
  ProjectLyricReviewOverview? _review;

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
    final outcome = await deleteProjectsWithUndo(
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

  /// The editor's 建议复核 counts for [project]; null without lyrics or a
  /// counter. Counted again only when a different copy is loaded.
  ProjectLyricReviewOverview? _reviewOf(ProjectManifest project) {
    if (identical(project, _reviewSource)) return _review;
    _reviewSource = project;
    return _review = project.hasLyrics
        ? widget.dependencies.reviewCounter?.call(project)
        : null;
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
            return const ProjectDetailLoadingState();
          }

          if (snapshot.hasError || snapshot.data == null) {
            return ProjectDetailErrorState(onRetry: _refreshProject);
          }

          final project = snapshot.data!;
          return ProjectDetailContent(
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
            review: _reviewOf(project),
          );
        },
      ),
    );
  }
}
