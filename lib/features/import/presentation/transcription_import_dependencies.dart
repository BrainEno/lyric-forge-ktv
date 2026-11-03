import '../../player/domain/services/audio_library_import_service.dart';
import '../../transcription/domain/services/asr_runtime_manager.dart';
import '../../transcription/domain/services/batch_transcription_queue.dart';
import '../../transcription/domain/services/transcription_settings_store.dart';
import '../../transcription/presentation/transcription_screen_dependencies.dart';

/// Shared app-scoped collaborators for the import readiness and batch surfaces.
class TranscriptionImportDependencies {
  final AudioLibraryImportService audioLibraryImportService;
  final BatchTranscriptionQueue transcriptionQueue;
  final AsrRuntimeSetupDependencies asrRuntimeSetupDependencies;

  TranscriptionSettingsStore get transcriptionSettingsStore =>
      asrRuntimeSetupDependencies.transcriptionSettingsStore;
  AsrRuntimeManager get asrRuntimeManager =>
      asrRuntimeSetupDependencies.asrRuntimeManager;

  const TranscriptionImportDependencies({
    required this.audioLibraryImportService,
    required this.transcriptionQueue,
    required this.asrRuntimeSetupDependencies,
  });
}
