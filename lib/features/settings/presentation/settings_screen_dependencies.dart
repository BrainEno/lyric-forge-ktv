import '../../transcription/domain/services/asr_end_to_end_smoke_test_service.dart';
import '../../transcription/presentation/transcription_screen_dependencies.dart';

/// App-scoped collaborators used by the settings screen and its ASR sections.
class SettingsScreenDependencies {
  final AsrRuntimeSetupDependencies asrRuntimeSetupDependencies;
  final AsrEndToEndSmokeTestService smokeTestService;

  const SettingsScreenDependencies({
    required this.asrRuntimeSetupDependencies,
    required this.smokeTestService,
  });
}
