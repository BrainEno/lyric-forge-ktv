import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/project_transcription_workflow.dart';
import '../../domain/services/transcription_profile_resolver.dart';
import '../../domain/services/transcription_service.dart';
import '../../domain/services/transcription_settings_store.dart';

class LocalProjectTranscriptionWorkflow
    implements ProjectTranscriptionWorkflow {
  final ProjectRepository _projectRepository;
  final TranscriptionService _transcriptionService;
  final TranscriptionSettingsStore _settingsStore;
  final TranscriptionProfileResolver _profileResolver;
  final AsrRuntimeManager _runtimeManager;

  LocalProjectTranscriptionWorkflow({
    required ProjectRepository projectRepository,
    required TranscriptionService transcriptionService,
    required TranscriptionSettingsStore settingsStore,
    required TranscriptionProfileResolver profileResolver,
    required AsrRuntimeManager runtimeManager,
  })  : _projectRepository = projectRepository,
        _transcriptionService = transcriptionService,
        _settingsStore = settingsStore,
        _profileResolver = profileResolver,
        _runtimeManager = runtimeManager;

  @override
  Stream<TranscriptionProgress> get progressStream =>
      _transcriptionService.progressStream;

  @override
  bool get isRunning => _transcriptionService.isRunning;

  @override
  Future<void> transcribeProject(String projectId) async {
    final project = await _projectRepository.getProjectById(projectId);
    if (project == null) {
      throw const TranscriptionException('工程不存在');
    }

    final audio = project.audioAsset;
    if (audio == null) {
      throw const TranscriptionException('工程还没有可识别的音频');
    }

    final config = await _settingsStore.load();
    if (config == null || !config.isConfigured) {
      throw const TranscriptionException('请先完成本地歌词识别运行时配置');
    }

    final resolvedProfile = await _profileResolver.resolve(config);
    final runtimeConfig =
        await _runtimeManager.repair(resolvedProfile.config);
    if (!runtimeConfig.isConfigured) {
      throw const TranscriptionException(
        '本机识别环境尚未准备完成，请先运行自动安装向导',
      );
    }

    final runtimeStatus = await _runtimeManager.inspect(runtimeConfig);
    if (!runtimeStatus.isReady) {
      throw const TranscriptionException(
        '本机识别环境缺少必要组件，请先运行自动安装或修复',
      );
    }

    final inputPath = await _resolveInputPath(project);
    final outputDirectory = await _outputDirectory(project);
    await _backupExistingLyrics(project, outputDirectory);

    await _projectRepository.updateProject(
      project.copyWith(
        status: ProjectStatus.transcribing,
        projectDirectory: project.projectDirectory ?? outputDirectory.parent.path,
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
        throw const TranscriptionException('识别完成，但工程已经不存在');
      }

      await _projectRepository.updateProject(
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
              'backend': editableLyrics.metadata['primaryEngine'] ??
                  editableLyrics.metadata['generatedBy'] ??
                  'local-asr',
              'generatedAt': DateTime.now().toIso8601String(),
              'detectedLanguage': result.detectedLanguage,
              'inputPath': inputPath,
              'normalizedAudioPath': result.normalizedAudioPath,
              'rawJsonPath': result.rawJsonPath,
              'primaryModel': runtimeConfig.mode == TranscriptionMode.whisperOnly
                  ? 'Whisper'
                  : runtimeConfig.engineOrder ==
                          TranscriptionEngineOrder.qwenPrimary
                      ? 'Qwen3-ASR-1.7B'
                      : 'Whisper large-v3',
              'alignmentModel':
                  runtimeConfig.mode == TranscriptionMode.highestQuality
                      ? 'Qwen3-ForcedAligner-0.6B'
                      : null,
              'fallbackModel': runtimeConfig.mode == TranscriptionMode.highestQuality
                  ? runtimeConfig.engineOrder ==
                          TranscriptionEngineOrder.qwenPrimary
                      ? 'Whisper large-v3'
                      : 'Qwen3-ASR-0.6B'
                  : null,
            },
          },
        ),
      );
    } on TranscriptionException catch (error) {
      final latest = await _projectRepository.getProjectById(projectId);
      if (latest != null) {
        if (error.message == '歌词识别已取消') {
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
      'Song title: ' + project.name,
      if (project.artist != null && project.artist!.trim().isNotEmpty)
        'Artist: ' + project.artist!.trim(),
      if (project.album != null && project.album!.trim().isNotEmpty)
        'Album: ' + project.album!.trim(),
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

    throw const TranscriptionException(
      '工程音频文件不可用：人声、标准化音频和原声都不存在',
    );
  }

  Future<Directory> _outputDirectory(ProjectManifest project) async {
    if (project.projectDirectory != null &&
        project.projectDirectory!.trim().isNotEmpty) {
      final directory = Directory(
        project.projectDirectory! +
            Platform.pathSeparator +
            'transcription',
      );
      await directory.create(recursive: true);
      return directory;
    }

    final support = await getApplicationSupportDirectory();
    final projectDirectory = Directory(
      support.path +
          Platform.pathSeparator +
          'LyricForge' +
          Platform.pathSeparator +
          'Projects' +
          Platform.pathSeparator +
          project.id,
    );
    final transcriptionDirectory = Directory(
      projectDirectory.path + Platform.pathSeparator + 'transcription',
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
      outputDirectory.path + Platform.pathSeparator + 'backups',
    );
    await backupDirectory.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backup = File(
      backupDirectory.path +
          Platform.pathSeparator +
          'lyrics_' +
          timestamp +
          '.json',
    );
    await backup.writeAsString(
      const JsonEncoder.withIndent('  ').convert(lyrics.toJson()),
      flush: true,
    );
  }

  @override
  Future<void> cancel() => _transcriptionService.cancel();
}
