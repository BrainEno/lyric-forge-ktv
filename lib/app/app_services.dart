import 'dart:async';

import 'ktv_recording_assembly.dart';

import '../features/lyrics/data/services/local_lyric_file_export_service.dart';
import '../features/lyrics/data/services/local_lyric_file_import_service.dart';
import '../features/lyrics/domain/services/lyric_file_export_service.dart';
import '../features/lyrics/domain/services/lyric_file_import_service.dart';
import '../features/player/data/repositories/file_local_media_collection_repository.dart';
import '../features/player/data/repositories/file_local_media_library_repository.dart';
import '../features/player/data/repositories/file_local_media_metadata_repository.dart';
import '../features/player/data/repositories/file_play_history_repository.dart';
import '../features/player/data/repositories/file_playback_session_store.dart';
import '../features/player/data/services/default_playback_session_service.dart';
import '../features/player/data/services/exclusive_audio_preview_service.dart';
import '../features/player/data/services/just_audio_audio_preview_service.dart';
import '../features/player/data/services/file_audio_path_canonicalizer.dart';
import '../features/player/data/services/file_ktv_microphone_preference_store.dart';
import '../features/player/data/services/file_ktv_take_history_store.dart';
import '../features/player/data/services/file_local_media_relink_service.dart';
import '../features/player/data/services/record_soloud_ktv_microphone_service.dart';
import '../features/player/data/services/just_audio_player_service.dart';
import '../features/player/data/services/library_metadata_playback_session_service.dart';
import '../features/player/data/services/local_audio_library_import_service.dart';
import '../features/player/data/services/pure_dart_embedded_audio_metadata_reader.dart';
import '../features/player/data/services/remote_rebinding_playback_session_service.dart';
import '../features/player/domain/repositories/local_media_collection_repository.dart';
import '../features/player/domain/repositories/local_media_library_repository.dart';
import '../features/player/domain/repositories/local_media_metadata_repository.dart';
import '../features/player/domain/repositories/play_history_repository.dart';
import '../features/player/domain/repositories/playback_session_store.dart';
import '../features/player/domain/services/audio_library_import_service.dart';
import '../features/player/domain/services/audio_path_canonicalizer.dart';
import '../features/player/domain/services/audio_preview_service.dart';
import '../features/player/domain/services/audio_player_service.dart';
import '../features/player/domain/services/ktv_microphone_service.dart';
import '../features/player/domain/services/ktv_recording_service.dart';
import '../features/player/domain/services/ktv_take_history_store.dart';
import '../features/player/domain/services/embedded_audio_metadata_reader.dart';
import '../features/player/domain/services/local_media_relink_service.dart';
import '../features/player/domain/services/playback_session_service.dart';
import '../features/project/data/repositories/file_project_repository.dart';
import '../features/project/domain/repositories/project_repository.dart';
import '../features/transcription/data/services/file_batch_transcription_queue.dart';
import '../features/transcription/data/services/file_transcription_settings_store.dart';
import '../features/transcription/data/services/asr_download_connection_checker.dart';
import '../features/transcription/data/services/asr_download_http_client_factory.dart';
import '../features/transcription/data/services/high_quality_transcription_service.dart';
import '../features/transcription/data/services/local_asr_end_to_end_smoke_test_service.dart';
import '../features/transcription/data/services/local_asr_managed_storage_service.dart';
import '../features/transcription/data/services/local_asr_storage_preflight_service.dart';
import '../features/transcription/data/services/local_project_transcription_workflow.dart';
import '../features/transcription/data/services/managed_asr_runtime_manager.dart';
import '../features/transcription/data/services/managed_model_asr_runtime_manager.dart';
import '../features/transcription/data/services/native_transcription_profile_resolver.dart';
import '../features/transcription/data/services/qwen3_asr_native_transcription_service.dart';
import '../features/transcription/data/services/resilient_asr_runtime_manager.dart';
import '../features/transcription/data/services/resumable_chunked_transcription_service.dart';
import '../features/transcription/data/services/retrying_asr_runtime_manager.dart';
import '../features/transcription/data/services/storage_preflight_asr_runtime_manager.dart';
import '../features/transcription/data/services/whisper_cpp_transcription_service.dart';
import '../features/transcription/domain/services/asr_end_to_end_smoke_test_service.dart';
import '../features/transcription/domain/services/asr_download_connection_checker.dart';
import '../features/transcription/domain/services/asr_resource_coordinator.dart';
import '../features/transcription/domain/services/asr_runtime_manager.dart';
import '../features/transcription/domain/services/asr_storage_preflight_service.dart';
import '../features/transcription/domain/services/batch_transcription_queue.dart';
import '../features/transcription/domain/services/project_transcription_workflow.dart';
import '../features/transcription/domain/services/transcription_profile_resolver.dart';
import '../features/transcription/domain/services/transcription_service.dart';
import '../features/transcription/domain/services/transcription_settings_store.dart';
import '../features/transfer/data/services/discoverable_media_hub_service.dart';
import '../features/transfer/data/services/file_media_hub_connection_store.dart';
import '../features/transfer/data/services/file_media_hub_device_identity_store.dart';
import '../features/transfer/data/services/file_media_transfer_queue_service.dart';
import '../features/transfer/data/services/http_media_hub_client_service.dart';
import '../features/transfer/data/services/http_media_hub_service.dart';
import '../features/transfer/data/services/local_library_media_share_catalog.dart';
import '../features/transfer/data/services/local_media_transfer_service.dart';
import '../features/transfer/data/services/media_hub_rebinding_audio_player_service.dart';
import '../features/transfer/data/services/media_hub_remote_playback_item_resolver.dart';
import '../features/transfer/data/services/udp_media_hub_discovery_service.dart';
import '../features/transfer/domain/services/media_hub_client_service.dart';
import '../features/transfer/domain/services/media_hub_connection_store.dart';
import '../features/transfer/domain/services/media_hub_service.dart';
import '../features/transfer/domain/services/media_share_catalog.dart';
import '../features/transfer/domain/services/media_transfer_queue_service.dart';
import '../features/transfer/domain/services/media_transfer_service.dart';

/// The composition root's product: every app-scoped service, built once.
///
/// Phase 4.2 moved this out of `lib/core/services/service_locator.dart`. The
/// construction order below *is* the dependency graph, so it belongs in the
/// assembly layer (`lib/app/`) rather than in `core/`, which the rest of the app
/// is allowed to depend on without also depending on concrete implementations.
///
/// [instance] is the transitional global. Screens should take what they need as
/// constructor parameters (see `LyricEditorScreen.dependencies`); the ratchet in
/// `test/architecture/app_assembly_contract_test.dart` only lets the number of
/// callers shrink.
class AppServices {
  static final AppServices instance = AppServices._();
  AppServices._();

  bool _initialized = false;

  /// Whether [initialize] has run, i.e. whether the `late final` services can
  /// be read.
  ///
  /// The app shell can be built before bootstrap in tests (`ElysiumPlayerApp`
  /// renders a `MaterialApp` without pumping routes); reading a service then
  /// would throw `LateInitializationError` instead of leaving the shell idle.
  bool get isInitialized => _initialized;

  late final ProjectRepository projectRepository;
  late final AudioPlayerService audioPlayerService;

  /// App-scoped audition channel for loose files (KTV takes, exported mixes).
  /// Separate from [audioPlayerService] on purpose: an audition must never be
  /// mistaken for the queue's current item, but the two must not sound at once.
  late final AudioPreviewService audioPreviewService;
  late final KtvMicrophoneService ktvMicrophoneService;
  late final KtvRecordingService ktvRecordingService;
  late final KtvTakeHistoryStore ktvTakeHistoryStore;
  late final AudioLibraryImportService audioLibraryImportService;
  late final EmbeddedAudioMetadataReader embeddedAudioMetadataReader;
  late final LocalMediaLibraryRepository localMediaLibraryRepository;
  late final LocalMediaCollectionRepository localMediaCollectionRepository;
  late final LocalMediaMetadataRepository localMediaMetadataRepository;
  late final LocalMediaRelinkService localMediaRelinkService;
  late final LyricFileImportService lyricFileImportService;
  late final LyricFileExportService lyricFileExportService;
  late final PlayHistoryRepository playHistoryRepository;
  late final PlaybackSessionStore playbackSessionStore;
  late final PlaybackSessionService playbackSessionService;
  late final AudioPathCanonicalizer audioPathCanonicalizer;
  late final MediaHubService mediaHubService;
  late final MediaShareCatalog mediaShareCatalog;
  late final TranscriptionService transcriptionService;
  late final Qwen3AsrNativeTranscriptionService qwenNativeTranscriptionService;
  late final AsrRuntimeManager asrRuntimeManager;
  late final LocalAsrManagedStorageService asrManagedStorageService;
  late final AsrStoragePreflightService asrStoragePreflightService;
  late final TranscriptionProfileResolver transcriptionProfileResolver;
  late final TranscriptionSettingsStore transcriptionSettingsStore;
  late final TranscriptionDownloadProxyStore transcriptionDownloadProxyStore;
  late final AsrDownloadConnectionChecker asrDownloadConnectionChecker;
  late final AsrResourceCoordinator asrResourceCoordinator;
  late final AsrEndToEndSmokeTestService asrEndToEndSmokeTestService;
  late final BatchTranscriptionQueue transcriptionQueue;
  late final MediaHubClientService mediaHubClientService;
  late final MediaHubConnectionStore mediaHubConnectionStore;
  late final MediaTransferService mediaTransferService;
  late final MediaTransferQueueService mediaTransferQueueService;

  void initialize() {
    _initialized = true;
    // Connection state and discovery exist before the player is built so a
    // restored remote session can recover a moved/restarted desktop from its
    // stable paired device identity at the lowest audio-load layer.
    mediaHubConnectionStore = FileMediaHubConnectionStore();
    final discoveryService = UdpMediaHubDiscoveryService();
    mediaHubClientService = HttpMediaHubClientService(
      discoveryService: discoveryService,
      onConnectionResolved: (connection) {
        // Older UI surfaces still write the connection argument they started
        // with immediately after connectTo returns. Persist the verified /
        // auto-discovered endpoint on the next event turn so it remains the
        // final cached value without forcing a destructive rewrite of them.
        unawaited(
          Future<void>.delayed(
            Duration.zero,
            () => mediaHubConnectionStore.saveConnection(connection),
          ),
        );
      },
    );
    final rawAudioPlayer = JustAudioPlayerService();
    ktvMicrophoneService = RecordSoloudKtvMicrophoneService(
      preferenceStore: const FileKtvMicrophonePreferenceStore(),
    );
    unawaited(ktvMicrophoneService.refreshInputDevices());
    audioPlayerService = MediaHubRebindingAudioPlayerService(
      delegate: rawAudioPlayer,
      client: mediaHubClientService,
      connectionStore: mediaHubConnectionStore,
    );
    audioPreviewService = ExclusiveAudioPreviewService(
      delegate: JustAudioAudioPreviewService(),
      primaryPlayer: audioPlayerService,
    );

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
    lyricFileExportService = const LocalLyricFileExportService();
    final filePlayHistoryRepository = FilePlayHistoryRepository();
    playHistoryRepository = filePlayHistoryRepository;
    localMediaRelinkService = FileLocalMediaRelinkService(
      libraryRepository: localMediaLibraryRepository,
      collectionRepository: localMediaCollectionRepository,
      metadataRepository: localMediaMetadataRepository,
      historyRepository: filePlayHistoryRepository,
      supportedExtensions: audioLibraryImportService.supportedExtensions,
    );
    playbackSessionStore = FilePlaybackSessionStore();
    final basePlaybackSession = DefaultPlaybackSessionService(
      audioPlayerService,
      playHistoryRepository: playHistoryRepository,
      localMediaMetadataRepository: localMediaMetadataRepository,
      sessionStore: playbackSessionStore,
    );
    final metadataPlaybackSession = LibraryMetadataPlaybackSessionService(
      delegate: basePlaybackSession,
      libraryRepository: localMediaLibraryRepository,
    );
    final remoteResolver = MediaHubRemotePlaybackItemResolver(
      client: mediaHubClientService,
      connectionStore: mediaHubConnectionStore,
    );
    playbackSessionService = RemoteRebindingPlaybackSessionService(
      delegate: metadataPlaybackSession,
      resolver: remoteResolver,
    );

    audioPathCanonicalizer = const FileAudioPathCanonicalizer();
    projectRepository = FileProjectRepository(
      mediaMetadataRepository: localMediaMetadataRepository,
      playbackSession: playbackSessionService,
      pathCanonicalizer: audioPathCanonicalizer,
    );

    final rawMediaHub = HttpMediaHubService(
      onIncomingFile: (path) async {
        if (!_isSupportedIncomingAudio(path)) {
          throw UnsupportedError('不支持的音频格式');
        }
        await localMediaLibraryRepository.addPaths([path]);
      },
    );
    mediaHubService = DiscoverableMediaHubService(
      delegate: rawMediaHub,
      identityStore: FileMediaHubDeviceIdentityStore(),
    );
    mediaShareCatalog = LocalLibraryMediaShareCatalog(
      libraryRepository: localMediaLibraryRepository,
      metadataRepository: localMediaMetadataRepository,
    );
    mediaTransferService = LocalMediaTransferService(
      client: mediaHubClientService,
      libraryRepository: localMediaLibraryRepository,
    );
    mediaTransferQueueService = FileMediaTransferQueueService(
      transfers: mediaTransferService,
      client: mediaHubClientService,
    );
    unawaited(mediaTransferQueueService.initialize());
    transcriptionProfileResolver = NativeTranscriptionProfileResolver();
    asrManagedStorageService = LocalAsrManagedStorageService();
    asrStoragePreflightService = LocalAsrStoragePreflightService(
      profileResolver: transcriptionProfileResolver,
      managedRootResolver: asrManagedStorageService.resolveRoot,
    );
    final downloadHttpClientFactory = AsrDownloadHttpClientFactory();
    asrDownloadConnectionChecker = HttpAsrDownloadConnectionChecker(
      clientFactory: downloadHttpClientFactory,
    );
    final runtimeInstaller = ManagedAsrRuntimeManager(
      profileResolver: transcriptionProfileResolver,
      managedRootResolver: asrManagedStorageService.resolveRoot,
      httpClientFactory: downloadHttpClientFactory,
    );
    final managedRuntime = ManagedModelAsrRuntimeManager(
      delegate: runtimeInstaller,
      profileResolver: transcriptionProfileResolver,
      managedRootResolver: asrManagedStorageService.resolveRoot,
      httpClientFactory: downloadHttpClientFactory,
    );
    final retryingRuntime = RetryingAsrRuntimeManager(delegate: managedRuntime);
    final resilientRuntime = ResilientAsrRuntimeManager(
      delegate: retryingRuntime,
      managedRootResolver: asrManagedStorageService.resolveRoot,
      httpClientFactory: downloadHttpClientFactory,
    );
    asrRuntimeManager = StoragePreflightAsrRuntimeManager(
      delegate: resilientRuntime,
      storagePreflightService: asrStoragePreflightService,
    );
    final qwenNativeTranscriptionService = Qwen3AsrNativeTranscriptionService();
    this.qwenNativeTranscriptionService = qwenNativeTranscriptionService;
    // Whole song in one pass: the wrapper only kicks in above 20 minutes, where
    // resuming a long inference run beats keeping the song seamless. Both
    // engines already window audio internally, so chunking here would put a
    // second, coarser split above them and create the seams we were fixing.
    transcriptionService = ResumableChunkedTranscriptionService(
      delegate: HighQualityTranscriptionService(
        primary: qwenNativeTranscriptionService,
        fallback: WhisperCppTranscriptionService(),
      ),
    );
    final transcriptionSettings = FileTranscriptionSettingsStore();
    transcriptionSettingsStore = transcriptionSettings;
    transcriptionDownloadProxyStore = transcriptionSettings;
    ktvRecordingService = assembleKtvRecordingService(
      audioService: audioPlayerService,
      microphoneService: ktvMicrophoneService,
      settingsStore: transcriptionSettingsStore,
    );
    ktvTakeHistoryStore = const FileKtvTakeHistoryStore();
    asrResourceCoordinator = AsrResourceCoordinator();
    asrEndToEndSmokeTestService = LocalAsrEndToEndSmokeTestService(
      projectRepository: projectRepository,
      workflow: createProjectTranscriptionWorkflow(),
      settingsStore: transcriptionSettingsStore,
      runtimeManager: asrRuntimeManager,
    );
    transcriptionQueue = FileBatchTranscriptionQueue(
      projectRepository: projectRepository,
      workflow: createProjectTranscriptionWorkflow(),
    );
    unawaited(transcriptionQueue.initialize());
  }

  /// Per-consumer cancellation ownership with one shared resource gate.
  ProjectTranscriptionWorkflow createProjectTranscriptionWorkflow() =>
      LocalProjectTranscriptionWorkflow(
        projectRepository: projectRepository,
        transcriptionService: transcriptionService,
        settingsStore: transcriptionSettingsStore,
        profileResolver: transcriptionProfileResolver,
        runtimeManager: asrRuntimeManager,
        resources: asrResourceCoordinator,
        mediaMetadataRepository: localMediaMetadataRepository,
        playbackSession: playbackSessionService,
        pathCanonicalizer: audioPathCanonicalizer,
      );
}

bool _isSupportedIncomingAudio(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return false;
  final extension = path.substring(dot + 1).toLowerCase();
  return const {
    'mp3',
    'flac',
    'wav',
    'm4a',
    'mp4',
    'ogg',
    'aac',
  }.contains(extension);
}
