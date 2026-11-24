import '../core/onboarding/getting_started_store.dart';
import '../features/player/presentation/widgets/library_lyrics_link_text.dart';
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
    diagnostics: services.diagnostics,
    libraryFolder: services.libraryFolderSettings,
    findLibraryLyrics: () async {
      final pass = await services.libraryLyricsAutoLinker.linkAll();
      return LibraryLyricsLinkText.summary(pass);
    },
    countAutoPairedLyrics: services.libraryLyricsAutoLinker.autoPairedCount,
    appearance: services.appearance,
    showGettingStarted: () =>
        showGettingStartedAgain(services.gettingStartedStore),
  );
}
