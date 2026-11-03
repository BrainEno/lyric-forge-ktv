import '../features/import/presentation/transcription_import_dependencies.dart';
import '../features/project/presentation/project_detail_dependencies.dart';
import '../features/transfer/presentation/remote_media_library_dependencies.dart';
import 'app_services.dart';
import 'transcription_assembly.dart';

/// Builds dependencies for screens outside the playback and library surfaces.
ProjectDetailDependencies assembleProjectDetailDependencies(
  AppServices services,
) {
  return ProjectDetailDependencies(
    projectRepository: services.projectRepository,
    transcriptionWorkflow: services.projectTranscriptionWorkflow,
    asrRuntimeSetupDependencies: assembleAsrRuntimeSetupDependencies(services),
  );
}

TranscriptionImportDependencies assembleTranscriptionImportDependencies(
  AppServices services,
) {
  return TranscriptionImportDependencies(
    audioLibraryImportService: services.audioLibraryImportService,
    transcriptionQueue: services.transcriptionQueue,
    asrRuntimeSetupDependencies: assembleAsrRuntimeSetupDependencies(services),
  );
}

RemoteMediaLibraryDependencies assembleRemoteMediaLibraryDependencies(
  AppServices services,
) {
  return RemoteMediaLibraryDependencies(
    client: services.mediaHubClientService,
    audioPlayer: services.audioPlayerService,
    connectionStore: services.mediaHubConnectionStore,
  );
}
