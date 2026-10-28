import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_transfer_batch.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_transfer_queue.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/remote_audio_track.dart';

void main() {
  test('remote artwork metadata survives persistent queue JSON round trip', () {
    final now = DateTime(2026, 10, 8, 1, 20);
    final item = MediaTransferQueueItem(
      id: 'download:track-1',
      direction: MediaTransferDirection.downloadFromDesktop,
      title: 'Track',
      status: MediaTransferQueueStatus.queued,
      createdAt: now,
      updatedAt: now,
      remoteTrack: const RemoteAudioTrack(
        id: 'track-1',
        title: 'Track',
        artist: 'Artist',
        album: 'Album',
        format: 'flac',
        byteLength: 1234,
        streamPath: '/v1/tracks/track-1/audio',
        downloadPath: '/v1/tracks/track-1/audio?download=1',
        hasArtwork: true,
        artworkPath: '/v1/tracks/track-1/artwork',
      ),
    );

    final restored = MediaTransferQueueItem.fromJson(item.toJson());

    expect(restored.remoteTrack, isNotNull);
    expect(restored.remoteTrack!.hasArtwork, isTrue);
    expect(restored.remoteTrack!.artworkPath, '/v1/tracks/track-1/artwork');
  });
}
