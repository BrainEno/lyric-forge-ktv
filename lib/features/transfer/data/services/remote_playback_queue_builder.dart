import '../../../player/domain/models/remote_playback_source.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';

class RemotePlaybackQueueBuilder {
  final MediaHubClientService client;

  const RemotePlaybackQueueBuilder(this.client);

  PlaybackItem buildItem(RemoteAudioTrack track) {
    final streamUri = client.playbackUriFor(track);
    return PlaybackItem(
      id: 'remote:${track.id}',
      title: track.title,
      artist: track.artist ?? '桌面音乐',
      // A non-null projectId intentionally keeps ephemeral remote streams out
      // of local play history/metadata stores. The explicit remote marker lets
      // presentation/router code distinguish this from a real lyric project.
      projectId: 'mediahub:${track.id}',
      hasLyrics: track.hasLyrics,
      preferredSource: AudioSourceType.original,
      audioAsset: AudioAsset(
        originalPath: 'mediahub://${Uri.encodeComponent(track.id)}',
        format: track.format,
        duration: track.duration,
        metadata: {
          RemotePlaybackSource.markerKey: true,
          RemotePlaybackSource.streamUriKey: streamUri.toString(),
          RemotePlaybackSource.remoteTrackIdKey: track.id,
          RemotePlaybackSource.remoteTrackKey: track.toJson(),
          if (track.album?.trim().isNotEmpty == true) 'album': track.album!.trim(),
        },
      ),
    );
  }

  List<PlaybackItem> buildQueue(List<RemoteAudioTrack> tracks) =>
      tracks.map(buildItem).toList(growable: false);

  static RemoteAudioTrack? trackFromItem(PlaybackItem item) {
    if (!RemotePlaybackSource.isRemote(item.audioAsset)) return null;
    final raw = item.audioAsset.metadata[RemotePlaybackSource.remoteTrackKey];
    if (raw is! Map) return null;
    try {
      return RemoteAudioTrack.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }
}
