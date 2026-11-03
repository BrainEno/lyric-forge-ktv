import '../../player/domain/repositories/local_media_library_repository.dart';
import '../../player/domain/services/audio_library_import_service.dart';
import '../../player/domain/services/playback_session_service.dart';
import '../domain/services/media_hub_client_service.dart';
import '../domain/services/media_hub_connection_store.dart';
import '../domain/services/media_hub_service.dart';
import '../domain/services/media_share_catalog.dart';
import '../domain/services/media_transfer_queue_service.dart';

/// Collaborators for the desktop Media Hub consent-and-sharing surface.
class DesktopMediaHubDependencies {
  final MediaHubService hub;
  final MediaShareCatalog catalog;

  const DesktopMediaHubDependencies({required this.hub, required this.catalog});
}

/// Collaborators for the mobile transfer home (browse and upload actions).
class MobileMediaTransferDependencies {
  final MediaHubClientService client;
  final MediaTransferQueueService transferQueue;
  final AudioLibraryImportService audioLibraryImport;

  const MobileMediaTransferDependencies({
    required this.client,
    required this.transferQueue,
    required this.audioLibraryImport,
  });
}

/// Shared collaborators for the remote songs, grouped catalog and downloads.
class MobileRemoteLibraryDependencies {
  final MediaHubClientService client;
  final MediaHubConnectionStore connectionStore;
  final MediaTransferQueueService transferQueue;
  final LocalMediaLibraryRepository localLibrary;
  final PlaybackSessionService playbackSession;

  const MobileRemoteLibraryDependencies({
    required this.client,
    required this.connectionStore,
    required this.transferQueue,
    required this.localLibrary,
    required this.playbackSession,
  });
}
