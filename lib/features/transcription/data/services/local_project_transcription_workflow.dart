import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../player/domain/repositories/local_media_metadata_repository.dart';
import '../../../player/domain/services/audio_path_canonicalizer.dart';
import '../../../player/domain/services/playback_lyrics_project_linker.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/transcription_degradation.dart';
import '../../domain/models/transcription_model_identity.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/project_transcription_workflow.dart';
import '../../domain/services/transcription_profile_resolver.dart';
import '../../domain/services/transcription_service.dart';
import '../../domain/services/transcription_settings_store.dart';

/// Persists ASR output as the editable timeline consumed by lyric editing and
/// synchronized playback surfaces. Playback consumers reload the persisted
/// project after editing so the corrected timeline becomes the new source of
/// truth immediately. Interoperable exports flatten the global correction into
/// effective playback timestamps while this project timeline stays lossless.
class LocalProjectTranscriptionWorkflow
    implements ProjectTranscriptionWorkflow {
  final ProjectRepository _projectRepository;
  final TranscriptionService _transcriptionService;
  final TranscriptionSettingsStore _settingsStore;
  final TranscriptionProfileResolver _profileResolver;
  final AsrRuntimeManager _runtimeManager;
  final LocalMediaMetadataRepository _mediaMetadataRepository;
  final PlaybackSessionService _playbackSession;
  final AudioPathCanonicalizer _pathCanonicalizer;

  LocalProjectTranscriptionWorkflow({
    required ProjectRepository projectRepository,
    required TranscriptionService transcriptionService,
    required TranscriptionSettingsStore settingsStore,
    required TranscriptionProfileResolver profileResolver,
    required AsrRuntimeManager runtimeManager,
    required LocalMediaMetadataRepository mediaMetadataRepository,
    required PlaybackSessionService playbackSession,
    required AudioPathCanonicalizer pathCanonicalizer,
  }) : _projectRepository = projectRepository,
       _transcriptionService = transcriptionService,
       _settingsStore = settingsStore,
       _profileResolver = profileResolver,
       _runtimeManager = runtimeManager,
       _mediaMetadataRepository = mediaMetadataRepository,
       _playbackSession = playbackSession,
       _pathCanonicalizer = pathCanonicalizer;

  @override
  Stream<TranscriptionProgress> get progressStream =>
      _transcriptionService.progressStream;

  @override
  bool get isRunning => _transcriptionService.isRunning;

  @override
  Future<void> transcribeProject(String projectId) async {
    final project = await _projectRepository.getProjectById(projectId);
    if (project == null) {
      throw const TranscriptionException.input('工程不存在');
    }

    final audio = project.audioAsset;
    if (audio == null) {
      throw const TranscriptionException.input('工程还没有可识别的音频');
    }

    final config = await _settingsStore.load();
    if (config == null || !config.isConfigured) {
      throw const TranscriptionException.environment('请先完成本地歌词识别运行时配置');
    }

    late final ResolvedTranscriptionProfile resolvedProfile;
    late final TranscriptionConfig runtimeConfig;
    try {
      resolvedProfile = await _profileResolver.resolve(config);
      runtimeConfig = await _runtimeManager.repair(resolvedProfile.config);
      if (!runtimeConfig.isConfigured) {
        throw const TranscriptionException.environment(
          '本机识别环境尚未准备完成，请先运行自动安装向导',
        );
      }

      final runtimeStatus = await _runtimeManager.inspect(runtimeConfig);
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

    final inputPath = await _resolveInputPath(project);
    final outputDirectory = await _outputDirectory(project);
    await _backupExistingLyrics(project, outputDirectory);

    await _projectRepository.updateProject(
      project.copyWith(
        status: ProjectStatus.transcribing,
        projectDirectory:
            project.projectDirectory ?? outputDirectory.parent.path,
      ),
    );

    try {
      final result = await _transcriptionService.transcribe(
        TranscriptionRequest(
          inputAudioPath: inputPath,
          outputDirectory: outputDirectory.path,
          config: runtimeConfig,
          context: _buildRecognitionContext(project),
        ),
      );

      final editableLyrics = result.lyrics.copyWith(
        metadata: {
          ...result.lyrics.metadata,
          'timelineFormat': 'lyricforge-timeline-v1',
          'editableDraft': true,
        },
      );
      final latest = await _projectRepository.getProjectById(projectId);
      if (latest == null) {
        throw const TranscriptionException.input('识别完成，但工程已经不存在');
      }

      final savedProject = await _projectRepository.updateProject(
        latest.copyWith(
          status: ProjectStatus.editing,
          currentStage: ProcessingStage.transcriptionComplete,
          lyricDocument: editableLyrics,
          metadata: {
            ...latest.metadata,
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
              'degradationReason':
                  TranscriptionQualityMetadata.reasonOf(
                    editableLyrics.metadata,
                  )?.name,
              'generatedAt': DateTime.now().toIso8601String(),
              'detectedLanguage': result.detectedLanguage,
              'inputPath': inputPath,
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
      );
      await linkPlaybackLyricsProject(
        audioPath: savedProject.audioAsset!.originalPath,
        projectId: savedProject.id,
        metadataRepository: _mediaMetadataRepository,
        playbackSession: _playbackSession,
        pathCanonicalizer: _pathCanonicalizer,
      );
    } on TranscriptionException catch (error) {
      final latest = await _projectRepository.getProjectById(projectId);
      if (latest != null) {
        if (error.kind == TranscriptionFailureKind.cancelled ||
            error.message == '歌词识别已取消') {
          await _projectRepository.updateProject(
            latest.copyWith(
              status: latest.hasLyrics
                  ? ProjectStatus.editing
                  : ProjectStatus.draft,
            ),
          );
        } else {
          await _projectRepository.updateProject(
            latest.copyWith(
              status: ProjectStatus.error,
              metadata: {
                ...latest.metadata,
                'transcriptionError': {
                  'at': DateTime.now().toIso8601String(),
                  'kind': error.kind.name,
                  'message': error.toString(),
                },
              },
            ),
          );
        }
      }
      rethrow;
    }
  }

  String _buildRecognitionContext(ProjectManifest project) {
    final parts = <String>[
      'Song title: ${project.name}',
      if (project.artist != null && project.artist!.trim().isNotEmpty)
        'Artist: ${project.artist!.trim()}',
      if (project.album != null && project.album!.trim().isNotEmpty)
        'Album: ${project.album!.trim()}',
    ];
    return parts.join('. ');
  }

  Future<String> _resolveInputPath(ProjectManifest project) async {
    final audio = project.audioAsset!;
    final candidates = [
      audio.vocalPath,
      audio.normalizedPath,
      audio.originalPath,
    ];

    for (final path in candidates) {
      if (path == null || path.trim().isEmpty) continue;
      if (await File(path).exists()) return path;
    }

    throw const TranscriptionException.input('工程音频文件不可用：人声、标准化音频和原声都不存在');
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
  Future<void> cancel() => _transcriptionService.cancel();
}
