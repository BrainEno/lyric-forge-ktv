import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../../features/lyrics/data/services/local_lyric_file_import_service.dart';
import '../../features/lyrics/domain/services/lyric_file_import_service.dart';
import '../../features/player/data/repositories/file_local_media_collection_repository.dart';
import '../../features/player/data/repositories/file_local_media_library_repository.dart';
import '../../features/player/data/repositories/file_local_media_metadata_repository.dart';
import '../../features/player/data/repositories/file_play_history_repository.dart';
import '../../features/player/data/services/default_playback_session_service.dart';
import '../../features/player/data/services/just_audio_player_service.dart';
import '../../features/player/data/services/library_metadata_playback_session_service.dart';
import '../../features/player/data/services/local_audio_library_import_service.dart';
import '../../features/player/data/services/pure_dart_embedded_audio_metadata_reader.dart';
import '../../features/player/data/services/system_media_controls_handler.dart';
import '../../features/player/domain/repositories/local_media_collection_repository.dart';
import '../../features/player/domain/repositories/local_media_library_repository.dart';
import '../../features/player/domain/repositories/local_media_metadata_repository.dart';
import '../../features/player/domain/repositories/play_history_repository.dart';
import '../../features/player/domain/services/audio_library_import_service.dart';
import '../../features/player/domain/services/audio_player_service.dart';
import '../../features/player/domain/services/embedded_audio_metadata_reader.dart';
import '../../features/player/domain/services/playback_session_service.dart';
import '../../features/project/data/repositories/file_project_repository.dart';
import '../../features/project/domain/repositories/project_repository.dart';
import '../../features/transcription/data/services/file_batch_transcription_queue.dart';
import '../../features/transcription/data/services/file_transcription_settings_store.dart';
import '../../features/transcription/data/services/high_quality_transcription_service.dart';
import '../../features/transcription/data/services/local_project_transcription_workflow.dart';
import '../../features/transcription/data/services/managed_asr_runtime_manager.dart';
import '../../features/transcription/data/services/managed_model_asr_runtime_manager.dart';
import '../../features/transcription/data/services/native_transcription_profile_resolver.dart';
import '../../features/transcription/data/services/qwen3_asr_native_transcription_service.dart';
import '../../features/transcription/data/services/resumable_chunked_transcription_service.dart';
import '../../features/transcription/data/services/whisper_cpp_transcription_service.dart';
import '../../features/transcription/domain/services/asr_runtime_manager.dart';
import '../../features/transcription/domain/services/batch_transcription_queue.dart';
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
  late final EmbeddedAudioMetadataReader embeddedAudioMetadataReader;
  late final LocalMediaLibraryRepository localMediaLibraryRepository;
  late final LocalMediaCollectionRepository localMediaCollectionRepository;
  late final LocalMediaMetadataRepository localMediaMetadataRepository;
  late final LyricFileImportService lyricFileImportService;
  late final PlayHistoryRepository playHistoryRepository;
  late final PlaybackSessionService playbackSessionService;
  late final MediaHubService mediaHubService;
  late final TranscriptionService transcriptionService;
  late final AsrRuntimeManager asrRuntimeManager;
  late final TranscriptionProfileResolver transcriptionProfileResolver;
  late final TranscriptionSettingsStore transcriptionSettingsStore;
  late final ProjectTranscriptionWorkflow projectTranscriptionWorkflow;
  late final BatchTranscriptionQueue transcriptionQueue;
  late final MediaHubClientService mediaHubClientService;
  late final MediaHubConnectionStore mediaHubConnectionStore;

  SystemMediaControlsHandler? systemMediaControlsHandler;

  void initialize() {
    projectRepository = FileProjectRepository();
    audioPlayerService = JustAudioPlayerService();
    embeddedAudioMetadataReader = const PureDartEmbeddedAudioMetadataReader();
    localMediaLibraryRepository = FileLocalMediaLibraryRepository(
      metadataReader: embeddedAudioMetadataReader,
    );
    localMediaCollectionRepository = FileLocalMediaCollectionRepository();
    audioLibraryImportService = LocalAudioLibraryImportService(
      onFilesPicked: (paths) async {
        await localMediaLibraryRepository.addPaths(paths);
      },
      onDirectoryPicked: (rootPath, paths) async {
        await localMediaLibraryRepository.addRoot(rootPath);
        await localMediaLibraryRepository.addPaths(paths);
      },
    );
    localMediaMetadataRepository = FileLocalMediaMetadataRepository();
    lyricFileImportService = LocalLyricFileImportService();
    playHistoryRepository = FilePlayHistoryRepository();
    final basePlaybackSession = DefaultPlaybackSessionService(
      audioPlayerService,
      playHistoryRepository: playHistoryRepository,
      localMediaMetadataRepository: localMediaMetadataRepository,
    );
    playbackSessionService = LibraryMetadataPlaybackSessionService(
      delegate: basePlaybackSession,
      libraryRepository: localMediaLibraryRepository,
    );
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
    transcriptionQueue = FileBatchTranscriptionQueue(
      projectRepository: projectRepository,
      workflow: projectTranscriptionWorkflow,
    );
    unawaited(transcriptionQueue.initialize());
  }

  /// Registers LyricForge's existing playback session with Android/iOS system
  /// media controls. Desktop playback intentionally keeps using the lightweight
  /// in-process path for now.
  Future<void> initializeSystemMediaControls() async {
    if (!_supportsMobileSystemMediaControls ||
        systemMediaControlsHandler != null) {
      return;
    }

    final handler = await AudioService.init<SystemMediaControlsHandler>(
      builder: () => SystemMediaControlsHandler(
        session: playbackSessionService,
        audioPlayer: audioPlayerService,
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.braineno.lyricforge.playback',
        androidNotificationChannelName: 'LyricForge playback',
        androidNotificationChannelDescription:
            'Background music playback and media controls',
        androidNotificationIcon: 'drawable/ic_stat_music_note',
        androidResumeOnClick: true,
        androidNotificationOngoing: false,
        // Keep the service foreground-capable while paused so a headset or
        // notification play action can resume reliably on Android 12+.
        androidStopForegroundOnPause: false,
        fastForwardInterval: Duration(seconds: 10),
        rewindInterval: Duration(seconds: 10),
        preloadArtwork: true,
        artDownscaleWidth: 768,
        artDownscaleHeight: 768,
      ),
    );
    systemMediaControlsHandler = handler;

    // Apply the music profile after audio plugins have initialised. just_audio
    // then handles normal focus interruptions (calls/other media) and headphone
    // unplug events using this shared audio session configuration.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  bool get _supportsMobileSystemMediaControls =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

/// Global accessor for services.
/// Usage: `ServiceLocator.I.projectRepository`
extension ServiceLocatorGlobal on ServiceLocator {
  static ServiceLocator get I => ServiceLocator();
}
