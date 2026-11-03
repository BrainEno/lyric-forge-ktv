import '../features/home/presentation/dashboard_dependencies.dart';
import 'app_services.dart';
import 'transcription_assembly.dart';

DashboardDependencies assembleDashboardDependencies(AppServices services) {
  return DashboardDependencies(
    projectRepository: services.projectRepository,
    playHistoryRepository: services.playHistoryRepository,
    playbackSession: services.playbackSessionService,
    audioPlayer: services.audioPlayerService,
    transcriptionQueue: services.transcriptionQueue,
    transcriptionSettingsStore: services.transcriptionSettingsStore,
    configDialogDependencies: assembleTranscriptionConfigDialogDependencies(
      services,
    ),
  );
}
