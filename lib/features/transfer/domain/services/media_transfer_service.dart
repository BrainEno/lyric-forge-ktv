import '../models/media_transfer_batch.dart';
import '../models/remote_audio_track.dart';

typedef MediaTransferProgressCallback = void Function(
  MediaTransferItemProgress progress,
);

abstract class MediaTransferService {
  Future<MediaTransferBatchResult> downloadRemoteTracks(
    List<RemoteAudioTrack> tracks, {
    MediaTransferProgressCallback? onProgress,
  });
}
