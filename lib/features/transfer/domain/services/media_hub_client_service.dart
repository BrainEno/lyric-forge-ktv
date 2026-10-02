import '../models/media_hub_connection.dart';
import '../models/remote_audio_track.dart';

typedef TransferProgressCallback = void Function(
  int bytesTransferred,
  int? totalBytes,
);

abstract class MediaHubClientService {
  MediaHubConnection? get currentConnection;

  bool get isConnected;

  Future<MediaHubConnection> connect(Uri pairingUri);

  Future<void> connectTo(MediaHubConnection connection);

  Future<void> disconnect();

  Future<List<RemoteAudioTrack>> fetchTracks();

  Uri playbackUriFor(RemoteAudioTrack track);

  Future<void> downloadTrack({
    required RemoteAudioTrack track,
    required String destinationPath,
    TransferProgressCallback? onProgress,
  });

  Future<void> dispose();
}
