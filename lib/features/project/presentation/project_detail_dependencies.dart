import '../domain/repositories/project_repository.dart';
import '../domain/services/project_accompaniment_importer.dart';
import '../../transcription/domain/services/asr_runtime_manager.dart';
import '../../transcription/domain/services/project_transcription_workflow.dart';
import '../../transcription/domain/services/transcription_settings_store.dart';
import '../../transcription/presentation/transcription_screen_dependencies.dart';

/// Services required by the project detail and local transcription actions.
class ProjectDetailDependencies {
  final ProjectRepository projectRepository;
  final ProjectAccompanimentImporter accompanimentImporter;
  final ProjectTranscriptionWorkflow transcriptionWorkflow;
  final AsrRuntimeSetupDependencies asrRuntimeSetupDependencies;

  TranscriptionSettingsStore get transcriptionSettingsStore =>
      asrRuntimeSetupDependencies.transcriptionSettingsStore;
  AsrRuntimeManager get asrRuntimeManager =>
      asrRuntimeSetupDependencies.asrRuntimeManager;

  const ProjectDetailDependencies({
    required this.projectRepository,
    required this.accompanimentImporter,
    required this.transcriptionWorkflow,
    required this.asrRuntimeSetupDependencies,
  });
}
