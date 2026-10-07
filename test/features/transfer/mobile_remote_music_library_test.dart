import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/remote_audio_track.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/screens/mobile_remote_music_library_screen.dart';

void main() {
  group('remoteTrackMatchesLocalEntry', () {
    RemoteAudioTrack track({
      String id = 'abcdef1234567890',
      String format = 'FLAC',
    }) {
      return RemoteAudioTrack(
        id: id,
        title: 'A/B Song',
        format: format,
        byteLength: 42,
        streamPath: '/stream/$id',
        downloadPath: '/download/$id',
      );
    }

    LocalMediaLibraryEntry entry(String path) {
      final now = DateTime(2026, 10, 7);
      return LocalMediaLibraryEntry(
        sourcePath: path,
        format: 'flac',
        addedAt: now,
        lastSeenAt: now,
      );
    }

    test('matches stable id suffix regardless of sanitised title', () {
      expect(
        remoteTrackMatchesLocalEntry(
          track(),
          entry('/documents/LyricForge/Downloads/A_B Song_abcdef12.flac'),
        ),
        isTrue,
      );
    });

    test('supports Windows-style stored paths', () {
      expect(
        remoteTrackMatchesLocalEntry(
          track(),
          entry(r'C:\Music\A_B Song_abcdef12.flac'),
        ),
        isTrue,
      );
    });

    test('does not mark a different remote track as downloaded', () {
      expect(
        remoteTrackMatchesLocalEntry(
          track(id: '9999999934567890'),
          entry('/documents/LyricForge/Downloads/A_B Song_abcdef12.flac'),
        ),
        isFalse,
      );
    });
  });
}
