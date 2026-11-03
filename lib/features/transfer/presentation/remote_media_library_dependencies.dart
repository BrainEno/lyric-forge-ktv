import '../../player/domain/services/audio_player_service.dart';
import '../domain/services/media_hub_client_service.dart';
import '../domain/services/media_hub_connection_store.dart';

/// Collaborators used by the remote media library's connection and playback.
class RemoteMediaLibraryDependencies {
  final MediaHubClientService client;
  final AudioPlayerService audioPlayer;
  final MediaHubConnectionStore connectionStore;

  const RemoteMediaLibraryDependencies({
    required this.client,
    required this.audioPlayer,
    required this.connectionStore,
  });
}
