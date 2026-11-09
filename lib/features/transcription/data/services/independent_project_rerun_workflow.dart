import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/transcription_profile_resolver.dart';
import '../../domain/services/transcription_service.dart';
import '../../domain/services/transcription_settings_store.dart';
import 'independent_project_rerun_service.dart';
import 'project_rerun_candidate_store.dart';
import 'qwen3_asr_native_transcription_service.dart';
import 'whisper_cpp_transcription_service.dart';

enum IndependentRerunPhase { idle, preparing, recognizing, saving }

/// Selects exactly one real engine and saves its result as a separate pair.
///
/// This instance only serializes its own calls. The caller must hold an
/// app-wide ASR resource lease before use: other transcription, alignment or
/// runtime-install operations may otherwise compete for the same resources.
/// This does not provide the lease and is not wired into the app yet.
class IndependentProjectRerunWorkflow {
  final ProjectRepository _projects;
  final TranscriptionSettingsStore _settings;
  final TranscriptionProfileResolver _profiles;
  final AsrRuntimeManager _runtime;
  final IndependentProjectRerunService _runner;
  final ProjectRerunCandidateStore _store;
  IndependentRerunPhase _phase = IndependentRerunPhase.idle;
  bool _cancelled = false;

  IndependentProjectRerunWorkflow({
    required ProjectRepository projects,
    required TranscriptionSettingsStore settings,
    required TranscriptionProfileResolver profiles,
    required AsrRuntimeManager runtime,
    TranscriptionService Function()? createQwen,
    TranscriptionService Function()? createWhisper,
  }) : _projects = projects,
       _settings = settings,
       _profiles = profiles,
       _runtime = runtime,
       _runner = IndependentProjectRerunService(
         projects: projects,
         createQwen: createQwen ?? Qwen3AsrNativeTranscriptionService.new,
         createWhisper: createWhisper ?? WhisperCppTranscriptionService.new,
       ),
       _store = ProjectRerunCandidateStore(projects);

  IndependentRerunPhase get phase => _phase;
  bool get isRunning => _phase != IndependentRerunPhase.idle;

  Future<SavedRerunCandidate> run({
    required String projectId,
    required IndependentRerunEngine engine,
  }) async {
    if (isRunning) throw const TranscriptionException.busy('已有独立识别任务正在运行');
    _phase = IndependentRerunPhase.preparing;
    _cancelled = false;
    try {
      _checkRuntimeNotInstalling();
      final project = await _projects.getProjectById(projectId);
      _checkCancelled();
      if (project == null || project.lyricDocument == null) {
        throw const TranscriptionException.input('工程或原始歌词不存在');
      }
      if (_store.read(project).length >= ProjectRerunCandidateStore.maxCandidates) {
        throw const TranscriptionException.input('候选版本已达到上限，未覆盖任何版本');
      }
      final settings = await _settings.load();
      _checkCancelled();
      if (settings == null) throw const TranscriptionException.environment('请先完成本地歌词识别运行时配置');
      // Runtime inspect reports Qwen components only in highest-quality mode.
      // This mode changes readiness inspection, not the selected engine.
      final requested = settings.copyWith(mode: engine == IndependentRerunEngine.qwen
          ? TranscriptionMode.highestQuality : TranscriptionMode.whisperOnly);
      final resolved = await _profiles.resolve(requested);
      _checkCancelled();
      _checkRuntimeNotInstalling();
      final config = await _runtime.repair(resolved.config);
      _checkCancelled();
      _checkRuntimeNotInstalling();
      final status = await _runtime.inspect(config);
      _checkCancelled();
      _checkRuntimeNotInstalling();
      final required = switch (engine) {
        IndependentRerunEngine.qwen => const {
          AsrRuntimeComponent.ffmpeg, AsrRuntimeComponent.qwenRuntime,
          AsrRuntimeComponent.qwenModel, AsrRuntimeComponent.qwenAligner,
        },
        IndependentRerunEngine.whisper => const {
          AsrRuntimeComponent.ffmpeg, AsrRuntimeComponent.whisperRuntime,
          AsrRuntimeComponent.whisperModel,
        },
      };
      if (!status.hasReadyComponents(required) ||
          (engine == IndependentRerunEngine.qwen && !config.isQwenConfigured) ||
          (engine == IndependentRerunEngine.whisper && !config.isWhisperConfigured)) {
        throw const TranscriptionException.environment('所选识别引擎或模型尚未就绪，请先检查本地运行环境');
      }
      _phase = IndependentRerunPhase.recognizing;
      final pair = await _runner.run(projectId: projectId, engine: engine, config: config);
      _checkCancelled();
      // Once persistence begins it cannot be reliably cancelled. Never report
      // cancellation after a write might already have committed.
      _phase = IndependentRerunPhase.saving;
      return await _store.save(pair);
    } finally {
      _phase = IndependentRerunPhase.idle;
      _cancelled = false;
    }
  }

  /// Returns false if idle or persistence has started and cannot be aborted.
  /// Preflight operations finish cooperatively; shared runtime setup is never
  /// cancelled by this workflow. Inference cancellation targets only its runner.
  Future<bool> cancel() async {
    if (_phase == IndependentRerunPhase.idle || _phase == IndependentRerunPhase.saving) return false;
    _cancelled = true;
    if (_phase == IndependentRerunPhase.recognizing) await _runner.cancel();
    return true;
  }

  void _checkRuntimeNotInstalling() {
    if (_runtime.isInstalling) {
      throw const TranscriptionException.busy('识别运行时正在安装或修复，请稍后重试');
    }
  }

  void _checkCancelled() {
    if (_cancelled) throw const TranscriptionException.cancelled('独立识别已取消');
  }
}
