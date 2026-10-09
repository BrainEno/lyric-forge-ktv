import 'dart:async';
import 'dart:io';

import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_end_to_end_smoke_test_service.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/project_transcription_workflow.dart';
import '../../domain/services/transcription_settings_store.dart';

class LocalAsrEndToEndSmokeTestService
    implements AsrEndToEndSmokeTestService {
  static const _supportedExtensions = <String>{
    'mp3',
    'flac',
    'wav',
    'm4a',
    'aac',
    'ogg',
  };

  static const _defaultConfig = TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    profilePreference: TranscriptionProfilePreference.automatic,
    qwenExecutable: 'qwen3-asr',
    whisperExecutable: 'whisper-cli',
    modelPath: '',
  );

  final ProjectRepository projectRepository;
  final ProjectTranscriptionWorkflow workflow;
  final TranscriptionSettingsStore settingsStore;
  final AsrRuntimeManager runtimeManager;

  final StreamController<AsrEndToEndSmokeProgress> _progressController =
      StreamController<AsrEndToEndSmokeProgress>.broadcast();

  bool _running = false;
  bool _cancelRequested = false;
  StreamSubscription<AsrRuntimeInstallProgress>? _runtimeProgressSubscription;
  StreamSubscription<TranscriptionProgress>? _transcriptionProgressSubscription;

  LocalAsrEndToEndSmokeTestService({
    required this.projectRepository,
    required this.workflow,
    required this.settingsStore,
    required this.runtimeManager,
  });

  @override
  Stream<AsrEndToEndSmokeProgress> get progressStream =>
      _progressController.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<AsrEndToEndSmokeResult> run(String audioPath) async {
    if (_running) {
      throw const TranscriptionException('ASR 端到端自检正在运行，请等待当前任务结束');
    }

    _running = true;
    _cancelRequested = false;
    ProjectManifest? smokeProject;
    var installedEnvironment = false;

    try {
      _emit(
        AsrEndToEndSmokeStage.validatingAudio,
        0.02,
        '正在检查真实音频文件',
      );
      final source = File(audioPath);
      if (!await source.exists()) {
        throw const TranscriptionException('ASR 自检音频文件不存在');
      }

      final extension = _extension(audioPath);
      if (!_supportedExtensions.contains(extension)) {
        throw TranscriptionException(
          'ASR 自检不支持 .$extension 音频',
          details: '请选择 MP3、FLAC、WAV、M4A、AAC 或 OGG 文件',
        );
      }
      _throwIfCancelled();

      var config = await settingsStore.load() ?? _defaultConfig;
      config = await runtimeManager.repair(config);
      var runtimeStatus = await runtimeManager.inspect(config);

      if (!runtimeStatus.isReady) {
        _emit(
          AsrEndToEndSmokeStage.preparingEnvironment,
          0.06,
          '识别环境不完整，正在自动准备 runtime 与模型',
        );
        _runtimeProgressSubscription = runtimeManager.progressStream.listen(
          (progress) {
            final phaseProgress = progress.progress.clamp(0.0, 1.0).toDouble();
            _emit(
              AsrEndToEndSmokeStage.preparingEnvironment,
              0.06 + phaseProgress * 0.44,
              progress.message,
            );
          },
        );
        config = await runtimeManager.installRecommended(config);
        installedEnvironment = true;
        await _runtimeProgressSubscription?.cancel();
        _runtimeProgressSubscription = null;
        _throwIfCancelled();
        runtimeStatus = await runtimeManager.inspect(config);
      }

      if (!runtimeStatus.isReady) {
        throw const TranscriptionException(
          'ASR 自检无法开始：自动准备结束后识别环境仍未通过检查',
        );
      }

      // Persist repaired/installed absolute paths before calling the production
      // workflow, because that workflow deliberately reloads settings itself.
      await settingsStore.save(config);
      _throwIfCancelled();

      _emit(
        AsrEndToEndSmokeStage.creatingProject,
        0.52,
        '正在创建真实歌词识别自检工程',
      );
      final baseName = _basenameWithoutExtension(audioPath);
      var project = await projectRepository.createProject(
        name: '$baseName · ASR 自检',
      );
      project = await projectRepository.updateProject(
        project.copyWith(
          status: ProjectStatus.draft,
          currentStage: ProcessingStage.audioImported,
          audioAsset: AudioAsset(
            originalPath: source.absolute.path,
            format: extension,
          ),
          metadata: {
            ...project.metadata,
            'asrSmokeTest': {
              'status': 'running',
              'startedAt': DateTime.now().toUtc().toIso8601String(),
              'sourcePath': source.absolute.path,
              'environmentInstalled': installedEnvironment,
            },
          },
        ),
      );
      smokeProject = project;
      _throwIfCancelled();

      _emit(
        AsrEndToEndSmokeStage.transcribing,
        0.56,
        '正在使用生产识别链路转写真实音频',
      );
      _transcriptionProgressSubscription = workflow.progressStream.listen(
        (progress) {
          final phaseProgress = progress.progress.clamp(0.0, 1.0).toDouble();
          _emit(
            AsrEndToEndSmokeStage.transcribing,
            0.56 + phaseProgress * 0.36,
            progress.message,
          );
        },
      );
      await workflow.transcribeProject(project.id);
      await _transcriptionProgressSubscription?.cancel();
      _transcriptionProgressSubscription = null;
      _throwIfCancelled();

      _emit(
        AsrEndToEndSmokeStage.verifyingResult,
        0.94,
        '正在验证歌词工程、时间轴与转写元数据',
      );
      final verified = await projectRepository.getProjectById(project.id);
      if (verified == null) {
        throw const TranscriptionException('ASR 自检失败：转写完成后工程不存在');
      }

      final lyrics = verified.lyricDocument;
      final hasVisibleLyrics = lyrics != null &&
          lyrics.lines.any((line) => line.text.trim().isNotEmpty);
      final hasTranscriptionMetadata = verified.metadata['transcription'] is Map;
      if (!hasVisibleLyrics ||
          verified.currentStage != ProcessingStage.transcriptionComplete ||
          !hasTranscriptionMetadata) {
        throw TranscriptionException(
          'ASR 自检失败：生产转写没有生成可校对的完整歌词工程',
          details:
              'lyrics=${lyrics?.lines.length ?? 0}, stage=${verified.currentStage.name}, '
              'metadata=$hasTranscriptionMetadata',
        );
      }

      final finalProject = await _markSmokeResult(
        verified,
        status: 'passed',
        details: {
          'finishedAt': DateTime.now().toUtc().toIso8601String(),
          'lyricLineCount': lyrics!.lines.length,
        },
      );

      _emit(
        AsrEndToEndSmokeStage.completed,
        1.0,
        '端到端歌词识别自检通过，正在打开校对页',
      );
      return AsrEndToEndSmokeResult(
        projectId: finalProject.id,
        projectName: finalProject.name,
        sourcePath: source.absolute.path,
        lyricLineCount: lyrics.lines.length,
        environmentInstalled: installedEnvironment,
      );
    } on TranscriptionException catch (error) {
      if (smokeProject != null) {
        await _recordFailure(smokeProject.id, error.toString());
      }
      rethrow;
    } catch (error) {
      if (smokeProject != null) {
        await _recordFailure(smokeProject.id, error.toString());
      }
      throw TranscriptionException(
        'ASR 端到端自检失败',
        details: error.toString(),
      );
    } finally {
      await _runtimeProgressSubscription?.cancel();
      _runtimeProgressSubscription = null;
      await _transcriptionProgressSubscription?.cancel();
      _transcriptionProgressSubscription = null;
      _running = false;
      _cancelRequested = false;
    }
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    _emit(
      AsrEndToEndSmokeStage.cancelling,
      0,
      '正在取消 ASR 端到端自检',
    );
    if (runtimeManager.isInstalling) {
      await runtimeManager.cancel();
    }
    if (workflow.isRunning) {
      await workflow.cancel();
    }
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const TranscriptionException('ASR 端到端自检已取消');
    }
  }

  Future<void> _recordFailure(String projectId, String error) async {
    try {
      final latest = await projectRepository.getProjectById(projectId);
      if (latest == null) return;
      await _markSmokeResult(
        latest,
        status: _cancelRequested ? 'cancelled' : 'failed',
        details: {
          'finishedAt': DateTime.now().toUtc().toIso8601String(),
          'error': error,
        },
      );
    } catch (_) {
      // Preserve the primary smoke-test error if diagnostic persistence fails.
    }
  }

  Future<ProjectManifest> _markSmokeResult(
    ProjectManifest project, {
    required String status,
    required Map<String, dynamic> details,
  }) {
    final existing = project.metadata['asrSmokeTest'];
    final smokeMetadata = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};
    return projectRepository.updateProject(
      project.copyWith(
        metadata: {
          ...project.metadata,
          'asrSmokeTest': {
            ...smokeMetadata,
            'status': status,
            ...details,
          },
        },
      ),
    );
  }

  String _extension(String path) {
    final normalized = path.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  String _basenameWithoutExtension(String path) {
    final normalized = path.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  void _emit(
    AsrEndToEndSmokeStage stage,
    double progress,
    String message,
  ) {
    if (_progressController.isClosed) return;
    _progressController.add(
      AsrEndToEndSmokeProgress(
        stage: stage,
        progress: progress.clamp(0.0, 1.0).toDouble(),
        message: message,
      ),
    );
  }
}
