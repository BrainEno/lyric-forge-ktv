import '../../features/player/data/repositories/memory_play_history_repository.dart';
import '../../features/player/data/services/default_playback_session_service.dart';
import '../../features/player/data/services/local_audio_library_import_service.dart';
import '../../features/player/data/services/just_audio_player_service.dart';
import '../../features/player/domain/repositories/play_history_repository.dart';
import '../../features/player/domain/services/audio_library_import_service.dart';
import '../../features/player/domain/services/audio_player_service.dart';
import '../../features/player/domain/services/playback_session_service.dart';
import '../../features/project/data/repositories/memory_project_repository.dart';
import '../../features/project/domain/repositories/project_repository.dart';
import '../../features/transcription/data/services/file_transcription_settings_store.dart';
import '../../features/transcription/data/services/high_quality_transcription_service.dart';
import '../../features/transcription/data/services/qwen3_asr_native_transcription_service.dart';
import '../../features/transcription/data/services/resumable_chunked_transcription_service.dart';
import '../../features/transcription/data/services/local_project_transcription_workflow.dart';
import '../../features/transcription/data/services/managed_asr_runtime_manager.dart';
import '../../features/transcription/data/services/managed_model_asr_runtime_manager.dart';
import '../../features/transcription/data/services/native_transcription_profile_resolver.dart';
import '../../features/transcription/data/services/whisper_cpp_transcription_service.dart';
import '../../features/transcription/domain/services/asr_runtime_manager.dart';
import '../../features/transcription/domain/services/project_transcription_workflow.dart';
import '../../features/transcription/domain/services/transcription_profile_resolver.dart';
import '../../features/transcription/domain/services/transcription_service.dart';
import '../../features/transcription/domain/services/transcription_settings_store.dart';
import '../../features/transfer/data/services/file_media_hub_connection_store.dart';
import '../../features/transfer/data/services/http_media_hub_client_service.dart';
import '../../features/transfer/data/services/http_media_hub_service.dart';
import '../../features/transfer/domain/services/media_hub_client_service.dart';
import '../../features/transfer/domain/services/media_hub_connection_store.dart';
import '../../features/transfer/domain/services/media_hub_service.dart';

/// Simple service locator for dependency injection.
/// Replaced with proper DI (e.g., get_it, injectable) as project grows.
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  late final ProjectRepository projectRepository;
  late final AudioPlayerService audioPlayerService;
  late final AudioLibraryImportService audioLibraryImportService;
  late final PlayHistoryRepository playHistoryRepository;
  late final PlaybackSessionService playbackSessionService;
  late final MediaHubService mediaHubService;
  late final TranscriptionService transcriptionService;
  late final AsrRuntimeManager asrRuntimeManager;
  late final TranscriptionProfileResolver transcriptionProfileResolver;
  late final TranscriptionSettingsStore transcriptionSettingsStore;
  late final ProjectTranscriptionWorkflow projectTranscriptionWorkflow;
  late final MediaHubClientService mediaHubClientService;
  late final MediaHubConnectionStore mediaHubConnectionStore;

  void initialize() {
    projectRepository = MemoryProjectRepository();
    audioPlayerService = JustAudioPlayerService();
    audioLibraryImportService = LocalAudioLibraryImportService();
    playbackSessionService = DefaultPlaybackSessionService(audioPlayerService);
    playHistoryRepository = MemoryPlayHistoryRepository();
    mediaHubService = HttpMediaHubService();
    mediaHubClientService = HttpMediaHubClientService();
    mediaHubConnectionStore = FileMediaHubConnectionStore();
    transcriptionProfileResolver = NativeTranscriptionProfileResolver();
    final runtimeInstaller = ManagedAsrRuntimeManager(
      profileResolver: transcriptionProfileResolver,
    );
    asrRuntimeManager = ManagedModelAsrRuntimeManager(
      delegate: runtimeInstaller,
      profileResolver: transcriptionProfileResolver,
    );
    transcriptionService = ResumableChunkedTranscriptionService(
      delegate: HighQualityTranscriptionService(
        primary: Qwen3AsrNativeTranscriptionService(),
        fallback: WhisperCppTranscriptionService(),
      ),
    );
    transcriptionSettingsStore = FileTranscriptionSettingsStore();
    projectTranscriptionWorkflow = LocalProjectTranscriptionWorkflow(
      projectRepository: projectRepository,
      transcriptionService: transcriptionService,
      settingsStore: transcriptionSettingsStore,
      profileResolver: transcriptionProfileResolver,
      runtimeManager: asrRuntimeManager,
    );
  }
}

/// Global accessor for services.
/// Usage: `ServiceLocator.I.projectRepository`
extension ServiceLocatorGlobal on ServiceLocator {
  static ServiceLocator get I => ServiceLocator();
}
