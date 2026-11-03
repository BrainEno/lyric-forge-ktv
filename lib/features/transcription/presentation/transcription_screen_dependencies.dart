import '../domain/services/asr_download_connection_checker.dart';
import '../domain/services/asr_managed_storage_service.dart';
import '../domain/services/asr_runtime_manager.dart';
import '../domain/services/asr_storage_preflight_service.dart';
import '../domain/services/transcription_profile_resolver.dart';
import '../domain/services/transcription_settings_store.dart';

/// Collaborators used by the advanced transcription configuration dialog.
class TranscriptionConfigDialogDependencies {
  final TranscriptionProfileResolver profileResolver;
  final AsrDownloadConnectionChecker downloadConnectionChecker;
  final TranscriptionDownloadProxyStore downloadProxyStore;

  const TranscriptionConfigDialogDependencies({
    required this.profileResolver,
    required this.downloadConnectionChecker,
    required this.downloadProxyStore,
  });
}

/// Shared runtime and persistence collaborators for setup and settings surfaces.
class AsrRuntimeSetupDependencies {
  final AsrRuntimeManager asrRuntimeManager;
  final AsrStoragePreflightService asrStoragePreflightService;
  final AsrManagedStorageService asrManagedStorageService;
  final TranscriptionSettingsStore transcriptionSettingsStore;
  final TranscriptionConfigDialogDependencies configDialogDependencies;

  const AsrRuntimeSetupDependencies({
    required this.asrRuntimeManager,
    required this.asrStoragePreflightService,
    required this.asrManagedStorageService,
    required this.transcriptionSettingsStore,
    required this.configDialogDependencies,
  });
}
