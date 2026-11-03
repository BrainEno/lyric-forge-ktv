import '../features/transfer/presentation/transfer_screen_dependencies.dart';
import 'app_services.dart';

DesktopMediaHubDependencies assembleDesktopMediaHubDependencies(
  AppServices services,
) {
  return DesktopMediaHubDependencies(
    hub: services.mediaHubService,
    catalog: services.mediaShareCatalog,
  );
}

MobileMediaTransferDependencies assembleMobileMediaTransferDependencies(
  AppServices services,
) {
  return MobileMediaTransferDependencies(
    client: services.mediaHubClientService,
    transferQueue: services.mediaTransferQueueService,
    audioLibraryImport: services.audioLibraryImportService,
  );
}

MobileRemoteLibraryDependencies assembleMobileRemoteLibraryDependencies(
  AppServices services,
) {
  return MobileRemoteLibraryDependencies(
    client: services.mediaHubClientService,
    connectionStore: services.mediaHubConnectionStore,
    transferQueue: services.mediaTransferQueueService,
    localLibrary: services.localMediaLibraryRepository,
    playbackSession: services.playbackSessionService,
  );
}
