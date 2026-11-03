import '../domain/repositories/project_repository.dart';
import '../../transcription/domain/services/asr_runtime_manager.dart';
import '../../transcription/domain/services/project_transcription_workflow.dart';
import '../../transcription/domain/services/transcription_settings_store.dart';

/// Services required by the project detail and local transcription actions.
class ProjectDetailDependencies {
  final ProjectRepository projectRepository;
  final ProjectTranscriptionWorkflow transcriptionWorkflow;
  final TranscriptionSettingsStore transcriptionSettingsStore;
  final AsrRuntimeManager asrRuntimeManager;

  const ProjectDetailDependencies({
    required this.projectRepository,
    required this.transcriptionWorkflow,
    required this.transcriptionSettingsStore,
    required this.asrRuntimeManager,
  });
}
