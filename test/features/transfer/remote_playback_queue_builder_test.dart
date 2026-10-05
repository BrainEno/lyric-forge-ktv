import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/remote_playback_source.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/remote_playback_queue_builder.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_connection.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/remote_audio_track.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_client_service.dart';

void main() {
  test('builds ephemeral remote playback queue with stream metadata', () {
    final client = _FakeClient();
    final builder = RemotePlaybackQueueBuilder(client);
    final tracks = [
      const RemoteAudioTrack(
        id: 'track-a',
        title: '中文歌曲',
        artist: 'Artist A',
        album: 'Album A',
        format: 'flac',
        byteLength: 123,
        duration: Duration(minutes: 4),
        streamPath: '/v1/tracks/track-a/audio',
        downloadPath: '/v1/tracks/track-a/download',
        hasLyrics: true,
        lyricsPath: '/v1/tracks/track-a/lyrics',
      ),
      const RemoteAudioTrack(
        id: 'track-b',
        title: 'Second',
        format: 'mp3',
        byteLength: 456,
        streamPath: '/v1/tracks/track-b/audio',
        downloadPath: '/v1/tracks/track-b/download',
      ),
    ];

    final queue = builder.buildQueue(tracks);

    expect(queue, hasLength(2));
    expect(queue.first.id, 'remote:track-a');
    expect(queue.first.projectId, 'mediahub:track-a');
    expect(queue.first.hasLyrics, isTrue);
    expect(queue.first.artist, 'Artist A');
    expect(queue.first.audioAsset.duration, const Duration(minutes: 4));
    expect(RemotePlaybackSource.isRemote(queue.first.audioAsset), isTrue);
    expect(
      RemotePlaybackSource.streamUri(queue.first.audioAsset).toString(),
      'http://127.0.0.1:9988/v1/tracks/track-a/audio?token=test-token',
    );
    expect(queue.first.audioAsset.metadata['album'], 'Album A');
  });

  test('remote track snapshot round-trips from playback item', () {
    final track = const RemoteAudioTrack(
      id: 'snapshot',
      title: 'Snapshot',
      artist: 'Artist',
      album: 'Album',
      format: 'm4a',
      byteLength: 999,
      duration: Duration(seconds: 90),
      streamPath: '/stream',
      downloadPath: '/download',
      hasLyrics: true,
      lyricsPath: '/lyrics',
    );

    final item = RemotePlaybackQueueBuilder(_FakeClient()).buildItem(track);
    final restored = RemotePlaybackQueueBuilder.trackFromItem(item);

    expect(restored, isNotNull);
    expect(restored!.id, track.id);
    expect(restored.title, track.title);
    expect(restored.artist, track.artist);
    expect(restored.album, track.album);
    expect(restored.format, track.format);
    expect(restored.byteLength, track.byteLength);
    expect(restored.duration, track.duration);
    expect(restored.hasLyrics, isTrue);
    expect(restored.lyricsPath, '/lyrics');
  });

  test('remote source only accepts http and https stream URIs', () {
    final client = _FakeClient(uri: Uri.parse('file:///tmp/not-remote.mp3'));
    final item = RemotePlaybackQueueBuilder(client).buildItem(
      const RemoteAudioTrack(
        id: 'bad',
        title: 'Bad',
        format: 'mp3',
        byteLength: 1,
        streamPath: '/stream',
        downloadPath: '/download',
      ),
    );

    expect(RemotePlaybackSource.isRemote(item.audioAsset), isTrue);
    expect(RemotePlaybackSource.streamUri(item.audioAsset), isNull);
  });
}

class _FakeClient implements MediaHubClientService {
  final Uri uri;

  _FakeClient({Uri? uri})
      : uri = uri ?? Uri.parse(
          'http://127.0.0.1:9988/v1/tracks/track-a/audio?token=test-token',
        );

  @override
  MediaHubConnection? get currentConnection => const MediaHubConnection(
        host: '127.0.0.1',
        port: 9988,
        token: 'test-token',
      );

  @override
  bool get isConnected => true;

  @override
  Uri playbackUriFor(RemoteAudioTrack track) {
    if (track.id == 'track-a') return uri;
    return Uri.parse(
      'http://127.0.0.1:9988/v1/tracks/${track.id}/audio?token=test-token',
    );
  }

  @override
  Future<MediaHubConnection> connect(Uri pairingUri) => throw UnimplementedError();

  @override
  Future<void> connectTo(MediaHubConnection connection) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> downloadTrack({
    required RemoteAudioTrack track,
    required String destinationPath,
    TransferProgressCallback? onProgress,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<RemoteAudioTrack>> fetchTracks() => throw UnimplementedError();

  @override
  Future<LyricDocument?> fetchLyrics(RemoteAudioTrack track) =>
      throw UnimplementedError();

  @override
  Future<void> uploadFile({
    required String sourcePath,
    String? remoteFileName,
    TransferProgressCallback? onProgress,
  }) =>
      throw UnimplementedError();
}
