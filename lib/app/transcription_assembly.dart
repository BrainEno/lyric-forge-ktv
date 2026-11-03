import '../features/settings/presentation/settings_screen_dependencies.dart';
import '../features/transcription/presentation/transcription_screen_dependencies.dart';
import 'app_services.dart';

TranscriptionConfigDialogDependencies
assembleTranscriptionConfigDialogDependencies(AppServices services) {
  return TranscriptionConfigDialogDependencies(
    profileResolver: services.transcriptionProfileResolver,
    downloadConnectionChecker: services.asrDownloadConnectionChecker,
    downloadProxyStore: services.transcriptionDownloadProxyStore,
  );
}

AsrRuntimeSetupDependencies assembleAsrRuntimeSetupDependencies(
  AppServices services,
) {
  return AsrRuntimeSetupDependencies(
    asrRuntimeManager: services.asrRuntimeManager,
    asrStoragePreflightService: services.asrStoragePreflightService,
    asrManagedStorageService: services.asrManagedStorageService,
    transcriptionSettingsStore: services.transcriptionSettingsStore,
    configDialogDependencies: assembleTranscriptionConfigDialogDependencies(
      services,
    ),
  );
}

SettingsScreenDependencies assembleSettingsScreenDependencies(
  AppServices services,
) {
  return SettingsScreenDependencies(
    asrRuntimeSetupDependencies: assembleAsrRuntimeSetupDependencies(services),
    smokeTestService: services.asrEndToEndSmokeTestService,
  );
}
