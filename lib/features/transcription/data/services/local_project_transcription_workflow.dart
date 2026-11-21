import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../lyrics/domain/services/chinese_script_unification_service.dart';
import '../../../player/domain/repositories/local_media_metadata_repository.dart';
import '../../../player/domain/services/audio_path_canonicalizer.dart';
import '../../../player/domain/services/playback_lyrics_project_linker.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/transcription_degradation.dart';
import '../../domain/models/transcription_model_identity.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/models/transcription_run_progress.dart';
import '../../domain/models/vocal_gap_fill_models.dart';
import '../../domain/models/vocal_separation_models.dart';
import '../../domain/services/asr_resource_coordinator.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/project_transcription_workflow.dart';
import '../../domain/services/project_vocal_separator.dart';
import '../../domain/services/transcription_profile_resolver.dart';
import '../../domain/services/transcription_service.dart';
import '../../domain/services/transcription_settings_store.dart';
import '../../domain/services/transcription_vocal_check.dart';
import '../../domain/services/transcription_vocal_gap_fill.dart';
import '../../domain/services/vocal_activity_lyric_gate.dart';
import 'project_recognition_hints.dart';
import 'project_transcription_input.dart';

enum _WorkflowPhase {
  idle,
  preparing,
  separating,
  recognizing,
  checking,
  fillingGaps,
  committing,
}

/// Persists ASR output as the editable timeline consumed by lyric editing and
/// synchronized playback surfaces. Playback consumers reload the persisted
/// project after editing so the corrected timeline becomes the new source of
/// truth immediately. Interoperable exports flatten the global correction into
/// effective playback timestamps while this project timeline stays lossless.
class LocalProjectTranscriptionWorkflow
    implements ProjectTranscriptionWorkflow {
  static const _runIdKey = 'activeTranscriptionRunId';

  final ProjectRepository _projectRepository;
  final TranscriptionService _transcriptionService;
  final TranscriptionSettingsStore _settingsStore;
  final TranscriptionProfileResolver _profileResolver;
  final AsrRuntimeManager _runtimeManager;
  final AsrResourceCoordinator _resources;
  _WorkflowPhase _phase = _WorkflowPhase.idle;
  bool _cancelRequested = false;
  Future<void>? _pendingCancel;
  final LocalMediaMetadataRepository _mediaMetadataRepository;
  final PlaybackSessionService _playbackSession;
  final AudioPathCanonicalizer _pathCanonicalizer;
  final ChineseScriptUnificationService _scriptUnification;

  /// Optional lead-vocal separation before recognition (D-043). Null keeps
  /// the earlier behaviour: recognise the imported stem or the mix.
  final ProjectVocalSeparator? _vocalSeparator;

  /// Optional check of a draft recognised from a vocal stem against the
  /// stem (D-044). Null keeps the draft exactly as recognised.
  final TranscriptionVocalCheck? _vocalCheck;

  /// Optional last step: recognise the stretches the vocal check found
  /// singing but no row in, and insert what is heard (D-047). Null, or the
  /// setting switched off, leaves those stretches for the editor.
  final TranscriptionVocalGapFill? _vocalGapFill;

  /// Progress of the workflow's own steps (separation, gap filling), merged
  /// into [progressStream] around recognition's.
  final StreamController<TranscriptionProgress> _stepProgress =
      StreamController<TranscriptionProgress>.broadcast(sync: true);

  /// Turns the steps' own 0–100% into one forward-only progress of the run
  /// (D-049).
  final TranscriptionRunMeter _meter = TranscriptionRunMeter();

  LocalProjectTranscriptionWorkflow({
    required ProjectRepository projectRepository,
    required TranscriptionService transcriptionService,
    required TranscriptionSettingsStore settingsStore,
    required TranscriptionProfileResolver profileResolver,
    required AsrRuntimeManager runtimeManager,
    required AsrResourceCoordinator resources,
    required LocalMediaMetadataRepository mediaMetadataRepository,
    required PlaybackSessionService playbackSession,
    required AudioPathCanonicalizer pathCanonicalizer,
    ChineseScriptUnificationService scriptUnification =
        const ChineseScriptUnificationService(),
    ProjectVocalSeparator? vocalSeparator,
    TranscriptionVocalCheck? vocalCheck,
    TranscriptionVocalGapFill? vocalGapFill,
  }) : _projectRepository = projectRepository,
       _transcriptionService = transcriptionService,
       _settingsStore = settingsStore,
       _profileResolver = profileResolver,
       _runtimeManager = runtimeManager,
       _resources = resources,
       _mediaMetadataRepository = mediaMetadataRepository,
       _playbackSession = playbackSession,
       _pathCanonicalizer = pathCanonicalizer,
       _scriptUnification = scriptUnification,
       _vocalSeparator = vocalSeparator,
       _vocalCheck = vocalCheck,
       _vocalGapFill = vocalGapFill;

  /// The run's progress: its own steps (preparing, separation, the vocal
  /// check, gap filling, saving) around recognition's events, each tagged
  /// with its [TranscriptionRunStep] and the forward-only progress of the
  /// whole run (D-049).
  @override
  Stream<TranscriptionProgress> get progressStream {
    return Stream<TranscriptionProgress>.multi((controller) {
      void forward(TranscriptionProgress event) =>
          controller.addSync(_meter.tag(event, _runStep));
      final subscriptions = [
        _stepProgress.stream.listen(forward),
        _transcriptionService.progressStream.listen(
          forward,
          onError: controller.addErrorSync,
        ),
      ];
      controller.onCancel = () =>
          Future.wait([for (final s in subscriptions) s.cancel()]);
    }, isBroadcast: true);
  }

  @override
  bool get isRunning => _phase != _WorkflowPhase.idle;

  /// The step of the run the current phase belongs to.
  TranscriptionRunStep get _runStep => switch (_phase) {
    _WorkflowPhase.idle ||
    _WorkflowPhase.preparing => TranscriptionRunStep.preparing,
    _WorkflowPhase.separating => TranscriptionRunStep.separating,
    _WorkflowPhase.recognizing => TranscriptionRunStep.recognizing,
    _WorkflowPhase.checking => TranscriptionRunStep.checking,
    _WorkflowPhase.fillingGaps => TranscriptionRunStep.fillingGaps,
    _WorkflowPhase.committing => TranscriptionRunStep.saving,
  };

  /// Says what the run is doing at the start of a step that reports nothing
  /// of its own for a while.
  void _announce(
    String message, {
    double progress = 0,
    TranscriptionStage stage = TranscriptionStage.validating,
  }) {
    _stepProgress.add(
      TranscriptionProgress(stage: stage, progress: progress, message: message),
    );
  }

  @override
  Future<void> transcribeProject(String projectId) async {
    if (isRunning) throw const TranscriptionException.busy('已有歌词识别任务正在运行');
    final lease = _resources.tryAcquire(AsrResourceUse.transcription);
    if (lease == null) {
      throw const TranscriptionException.busy('识别资源正在使用，请稍后重试');
    }
    _phase = _WorkflowPhase.preparing;
    _cancelRequested = false;
    _meter.start();
    try {
      await _transcribeProject(projectId);
    } finally {
      _meter.finish();
      try {
        final pendingCancel = _pendingCancel;
        if (pendingCancel != null) await pendingCancel;
      } finally {
        _pendingCancel = null;
        _cancelRequested = false;
        _phase = _WorkflowPhase.idle;
        lease.release();
      }
    }
  }

  Future<void> _transcribeProject(String projectId) async {
    _announce('正在检查本机识别环境');
    final project = await _projectRepository.getProjectById(projectId);
    _checkCancelled();
    if (project == null) {
      throw const TranscriptionException.input('工程不存在');
    }

    final audio = project.audioAsset;
    if (audio == null) {
      throw const TranscriptionException.input('工程还没有可识别的音频');
    }

    final config = await _settingsStore.load();
    _checkCancelled();
    if (config == null || !config.isConfigured) {
      throw const TranscriptionException.environment('请先完成本地歌词识别运行时配置');
    }

    late final ResolvedTranscriptionProfile resolvedProfile;
    late final TranscriptionConfig runtimeConfig;
    late final AsrRuntimeStatus runtimeStatus;
    try {
      resolvedProfile = await _profileResolver.resolve(config);
      _checkCancelled();
      runtimeConfig = await _runtimeManager.repair(resolvedProfile.config);
      _checkCancelled();
      if (!runtimeConfig.isConfigured) {
        throw const TranscriptionException.environment(
          '本机识别环境尚未准备完成，请先运行自动安装向导',
        );
      }

      runtimeStatus = await _runtimeManager.inspect(runtimeConfig);
      _checkCancelled();
      // Only the Whisper baseline may block recognition. A missing second
      // engine is not a reason to refuse the song: the transcription service
      // degrades to Whisper and records why, so the user still gets a draft.
      if (!runtimeStatus.isBaselineReady) {
        final failed = runtimeStatus.missingBaselineComponents
            .map((component) => '${component.label}: ${component.detail}')
            .join('; ');
        throw TranscriptionException.environment(
          '本机识别环境缺少 Whisper 基线组件，请先运行自动安装或修复',
          details: failed.isEmpty ? null : failed,
        );
      }
    } on TranscriptionException catch (error) {
      if (error.kind == TranscriptionFailureKind.cancelled) rethrow;
      throw error.withKind(TranscriptionFailureKind.environment);
    } catch (error) {
      throw TranscriptionException.environment(
        '无法检查本机歌词识别环境',
        details: error.toString(),
      );
    }

    // An automatic stem is trusted only when this run's separation step
    // confirms it (or, without a separator, unless separation is off).
    final mixInput = await resolveProjectTranscriptionInput(
      project,
      includeVocal:
          !_isAutomaticStem(audio) ||
          (_vocalSeparator == null &&
              runtimeConfig.vocalSeparation != VocalSeparationPreference.off),
    );
    _checkCancelled();
    _announce('正在读取工程并备份现有歌词', progress: 0.6);
    final outputDirectory = await _outputDirectory(project);
    _checkCancelled();
    await _backupExistingLyrics(project, outputDirectory);
    _checkCancelled();

    final runId = const Uuid().v4();
    late final ProjectManifest started;
    try {
      started = await _projectRepository.updateProjectIfUnchanged(
        project.copyWith(
          status: ProjectStatus.transcribing,
          projectDirectory:
              project.projectDirectory ?? outputDirectory.parent.path,
          metadata: {...project.metadata, _runIdKey: runId},
        ),
        expectedRevision: project.revision,
      );
    } on ProjectUpdateConflictException {
      throw const TranscriptionException.input('工程在识别准备期间发生变化，请刷新后重试。');
    }

    try {
      // If cancellation arrived during the start write, restore the run marker.
      _checkCancelled();
      var runProject = started;
      var inputPath = mixInput;
      VocalSeparationOutcome? separation;
      final separator = _vocalSeparator;
      if (separator != null) {
        _phase = _WorkflowPhase.separating;
        final prepared = await separator.separate(
          started,
          config: runtimeConfig,
          workDirectory:
              '${outputDirectory.parent.path}${Platform.pathSeparator}stems',
          onProgress: _stepProgress.add,
        );
        _checkCancelled();
        separation = prepared.outcome;
        final updatedAudio = prepared.updatedAudio;
        if (updatedAudio != null) {
          runProject = await _projectRepository.updateProjectIfUnchanged(
            started.copyWith(audioAsset: updatedAudio),
            expectedRevision: started.revision,
          );
          _checkCancelled();
        }
        final vocalPath = separation.vocalPath;
        if (separation.usesSeparatedVocal && vocalPath != null) {
          inputPath = vocalPath;
        }
        _stepProgress.add(
          TranscriptionProgress(
            stage: TranscriptionStage.preprocessing,
            progress: 1,
            message: separation.summary,
          ),
        );
      }
      _phase = _WorkflowPhase.recognizing;
      _announce('正在启动识别引擎', stage: TranscriptionStage.loadingModel);
      final result = await _transcriptionService.transcribe(
        TranscriptionRequest(
          inputAudioPath: inputPath,
          outputDirectory: outputDirectory.path,
          config: runtimeConfig,
          recognitionHints: recognitionHintsForProject(project),
        ),
      );

      _checkCancelled();
      if (_vocalCheck != null) {
        _phase = _WorkflowPhase.checking;
        _announce('正在对照人声音轨检查歌词草稿', stage: TranscriptionStage.parsing);
      }
      final checked = await _checkAgainstVocal(
        result,
        inputPath: inputPath,
        separation: separation,
        audio: runProject.audioAsset,
      );
      _checkCancelled();
      final gapFill = await _fillVocalGaps(
        checked,
        result: result,
        inputPath: inputPath,
        config: runtimeConfig,
        status: runtimeStatus,
        hints: recognitionHintsForProject(project),
        audioDuration: runProject.audioAsset?.duration,
      );
      _checkCancelled();
      // From here a project write may commit; do not report cancellation.
      _phase = _WorkflowPhase.committing;
      _announce('正在保存歌词草稿', stage: TranscriptionStage.parsing);
      final draft = gapFill?.document ?? checked?.document ?? result.lyrics;
      final recognizedLyrics = draft.copyWith(
        metadata: {
          ...draft.metadata,
          'timelineFormat': 'lyricforge-timeline-v1',
          'editableDraft': true,
        },
      );
      // A fresh draft has no manual edits, so the script preference can be
      // applied here once. Only line text changes, and the conversion is
      // recorded so independent ASR evidence still matches the draft.
      final scriptPlan = _scriptUnification.plan(
        recognizedLyrics,
        preference: runtimeConfig.chineseScriptPreference,
      );
      final editableLyrics = scriptPlan.applyTo(recognizedLyrics);
      final latest = await _projectRepository.getProjectById(projectId);
      if (latest == null) {
        throw const TranscriptionException.input('识别完成，但工程已经不存在');
      }

      final finishedMetadata = Map<String, dynamic>.from(latest.metadata)
        ..remove(_runIdKey);
      final savedProject = await _projectRepository.updateProjectIfUnchanged(
        latest.copyWith(
          status: ProjectStatus.editing,
          currentStage: ProcessingStage.transcriptionComplete,
          lyricDocument: editableLyrics,
          metadata: {
            ...finishedMetadata,
            'transcription': {
              'mode': runtimeConfig.mode.name,
              'hardwareProfile': resolvedProfile.profile.name,
              'hardwareProfileLabel': resolvedProfile.label,
              'hardwareOs': resolvedProfile.hardware.operatingSystem,
              'hardwareArchitecture': resolvedProfile.hardware.architecture,
              'backend':
                  editableLyrics.metadata['primaryEngine'] ??
                  editableLyrics.metadata['generatedBy'] ??
                  'local-asr',
              'degraded': TranscriptionQualityMetadata.isDegraded(
                editableLyrics.metadata,
              ),
              'degradationReason': TranscriptionQualityMetadata.reasonOf(
                editableLyrics.metadata,
              )?.name,
              'generatedAt': DateTime.now().toIso8601String(),
              'detectedLanguage': result.detectedLanguage,
              'chineseScript': {
                'preference': scriptPlan.preference.name,
                'target': scriptPlan.target?.name,
                'convertedLines': scriptPlan.changes.length,
                'inconsistentLinesBefore': scriptPlan.profile.inconsistentLines,
                'noopReason': scriptPlan.noopReason?.name,
              },
              'inputPath': inputPath,
              'vocalSeparation': separation?.toJson(),
              'vocalCheck': checked?.report.toJson(),
              'vocalGapFill': gapFill?.report.toJson(),
              'normalizedAudioPath': result.normalizedAudioPath,
              'rawJsonPath': result.rawJsonPath,
              'primaryModel':
                  runtimeConfig.mode == TranscriptionMode.whisperOnly
                  ? TranscriptionModelIdentity.whisperLabel(
                      runtimeConfig.modelPath,
                    )
                  : runtimeConfig.engineOrder ==
                        TranscriptionEngineOrder.qwenPrimary
                  ? TranscriptionModelIdentity.qwenAsrLabel(
                      runtimeConfig.qwenModelPath,
                    )
                  : TranscriptionModelIdentity.whisperLabel(
                      runtimeConfig.modelPath,
                    ),
              'alignmentModel':
                  runtimeConfig.mode == TranscriptionMode.highestQuality
                  ? TranscriptionModelIdentity.qwenAlignerLabel(
                      runtimeConfig.qwenAlignerModelPath,
                    )
                  : null,
              'fallbackModel':
                  runtimeConfig.mode == TranscriptionMode.highestQuality
                  ? runtimeConfig.engineOrder ==
                            TranscriptionEngineOrder.qwenPrimary
                        ? TranscriptionModelIdentity.whisperLabel(
                            runtimeConfig.modelPath,
                          )
                        : TranscriptionModelIdentity.qwenAsrLabel(
                            runtimeConfig.qwenModelPath,
                          )
                  : null,
            },
          },
        ),
        expectedRevision: runProject.revision,
      );
      await linkPlaybackLyricsProject(
        audioPath: savedProject.audioAsset!.originalPath,
        projectId: savedProject.id,
        metadataRepository: _mediaMetadataRepository,
        playbackSession: _playbackSession,
        pathCanonicalizer: _pathCanonicalizer,
      );
      _announce('歌词草稿已保存', progress: 1, stage: TranscriptionStage.completed);
    } on ProjectUpdateConflictException {
      await _finishUncommittedRun(project, runId);
      throw const TranscriptionException.input('识别期间工程发生变化，未覆盖最新歌词；请刷新后重试。');
    } on TranscriptionException catch (error) {
      await _finishUncommittedRun(project, runId, error: error);
      rethrow;
    }
  }

  /// The draft checked against the vocal stem it was recognised from, or
  /// null without a configured check. A mix (or a normalized copy of it) is
  /// loud everywhere, so it is reported and left alone.
  Future<VocalCheckResult?> _checkAgainstVocal(
    TranscriptionResult result, {
    required String inputPath,
    required VocalSeparationOutcome? separation,
    required AudioAsset? audio,
  }) async {
    final check = _vocalCheck;
    if (check == null) return null;
    final separatedVocal = separation?.usesSeparatedVocal == true
        ? separation?.vocalPath
        : null;
    final vocalInput =
        inputPath == separatedVocal ||
        (audio?.vocalPath != null &&
            inputPath == audio?.vocalPath &&
            inputPath != audio?.originalPath);
    if (!vocalInput) {
      return VocalCheckResult.unchanged(
        result.lyrics,
        const VocalCheckReport.skipped(VocalCheckSkipReason.notVocalInput),
      );
    }
    try {
      // Recognition's own 16 kHz mono copy first; the stem itself if that
      // copy is gone or not a plain WAV.
      return await check.check(
        result.lyrics,
        audioPaths: [result.normalizedAudioPath, inputPath],
      );
    } catch (error) {
      return VocalCheckResult.unchanged(
        result.lyrics,
        VocalCheckReport.skipped(
          VocalCheckSkipReason.failed,
          error: error.toString(),
        ),
      );
    }
  }

  /// The checked draft with the stretches of singing it has no row for
  /// recognised and filled in, or null when the step is not configured.
  /// Runs only after a vocal check that actually looked at a vocal stem;
  /// never fails the run.
  Future<VocalGapFillResult?> _fillVocalGaps(
    VocalCheckResult? checked, {
    required TranscriptionResult result,
    required String inputPath,
    required TranscriptionConfig config,
    required AsrRuntimeStatus status,
    required RecognitionHints hints,
    required Duration? audioDuration,
  }) async {
    final fill = _vocalGapFill;
    if (fill == null || checked == null) return null;
    final draft = checked.document;
    VocalGapFillResult skipped(VocalGapFillSkipReason reason) =>
        VocalGapFillResult(draft, VocalGapFillReport.skipped(reason));
    if (config.vocalGapFill == VocalGapFillPreference.off) {
      return skipped(VocalGapFillSkipReason.disabled);
    }
    if (!checked.report.applied) {
      return skipped(VocalGapFillSkipReason.noVocalCheck);
    }
    if (checked.report.record.uncoveredSpans.isEmpty) {
      return skipped(VocalGapFillSkipReason.noGaps);
    }
    final engines = vocalGapFillEngines(
      config: config,
      status: status,
      degraded: TranscriptionQualityMetadata.isDegraded(result.lyrics.metadata),
    );
    if (engines.isEmpty) return skipped(VocalGapFillSkipReason.noEngine);

    _phase = _WorkflowPhase.fillingGaps;
    VocalGapFillResult filled;
    try {
      filled = await fill.fill(
        draft,
        VocalGapFillRequest(
          audioPath: inputPath,
          config: config,
          engines: engines,
          hints: hints,
          audioDuration: audioDuration != null && audioDuration > Duration.zero
              ? audioDuration
              : null,
          onProgress: _stepProgress.add,
        ),
      );
    } on Object catch (error) {
      filled = VocalGapFillResult(
        draft,
        VocalGapFillReport.skipped(
          VocalGapFillSkipReason.failed,
          engines: engines,
          error: error.toString(),
        ),
      );
    }
    _stepProgress.add(
      TranscriptionProgress(
        stage: TranscriptionStage.parsing,
        progress: 1,
        message: filled.report.summary,
      ),
    );
    return filled;
  }

  Future<void> _finishUncommittedRun(
    ProjectManifest original,
    String runId, {
    TranscriptionException? error,
  }) async {
    try {
      final latest = await _projectRepository.getProjectById(original.id);
      if (latest == null || latest.metadata[_runIdKey] != runId) return;
      final metadata = Map<String, dynamic>.from(latest.metadata)
        ..remove(_runIdKey);
      if (error != null && error.kind != TranscriptionFailureKind.cancelled) {
        metadata['transcriptionError'] = {
          'at': DateTime.now().toIso8601String(),
          'kind': error.kind.name,
          'message': error.toString(),
        };
      }
      final fallbackStatus = switch (original.status) {
        ProjectStatus.ready ||
        ProjectStatus.editing ||
        ProjectStatus.draft => original.status,
        _ => latest.hasLyrics ? ProjectStatus.editing : ProjectStatus.draft,
      };
      final status = latest.status != ProjectStatus.transcribing
          ? latest.status
          : error != null && error.kind != TranscriptionFailureKind.cancelled
          ? ProjectStatus.error
          : fallbackStatus;
      await _projectRepository.updateProjectIfUnchanged(
        latest.copyWith(status: status, metadata: metadata),
        expectedRevision: latest.revision,
      );
    } catch (_) {
      // A concurrent writer or storage failure must not mask the original error
      // or permit cleanup to overwrite a newer project snapshot.
    }
  }

  Future<Directory> _outputDirectory(ProjectManifest project) async {
    if (project.projectDirectory != null &&
        project.projectDirectory!.trim().isNotEmpty) {
      final directory = Directory(
        '${project.projectDirectory!}${Platform.pathSeparator}transcription',
      );
      await directory.create(recursive: true);
      return directory;
    }

    final support = await getApplicationSupportDirectory();
    final projectDirectory = Directory(
      '${support.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}Projects${Platform.pathSeparator}${project.id}',
    );
    final transcriptionDirectory = Directory(
      '${projectDirectory.path}${Platform.pathSeparator}transcription',
    );
    await transcriptionDirectory.create(recursive: true);
    return transcriptionDirectory;
  }

  Future<void> _backupExistingLyrics(
    ProjectManifest project,
    Directory outputDirectory,
  ) async {
    final lyrics = project.lyricDocument;
    if (lyrics == null || lyrics.lines.isEmpty) return;

    final backupDirectory = Directory(
      '${outputDirectory.path}${Platform.pathSeparator}backups',
    );
    await backupDirectory.create(recursive: true);
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backup = File(
      '${backupDirectory.path}${Platform.pathSeparator}lyrics_$timestamp.json',
    );
    await backup.writeAsString(
      const JsonEncoder.withIndent('  ').convert(lyrics.toJson()),
      flush: true,
    );
  }

  @override
  Future<void> cancel() async {
    if (_phase == _WorkflowPhase.idle || _phase == _WorkflowPhase.committing) {
      return;
    }
    _cancelRequested = true;
    if (_phase == _WorkflowPhase.separating) {
      await (_pendingCancel ??= _vocalSeparator!.cancel());
    } else if (_phase == _WorkflowPhase.recognizing) {
      await (_pendingCancel ??= _transcriptionService.cancel());
    } else if (_phase == _WorkflowPhase.fillingGaps) {
      await (_pendingCancel ??= _vocalGapFill!.cancel());
    }
  }

  static bool _isAutomaticStem(AudioAsset audio) {
    final marker = VocalStemMarker.fromAudioMetadata(audio.metadata);
    return marker != null && marker.vocalPath == audio.vocalPath;
  }

  void _checkCancelled() {
    if (_cancelRequested) {
      throw const TranscriptionException.cancelled('歌词识别已取消');
    }
  }
}
