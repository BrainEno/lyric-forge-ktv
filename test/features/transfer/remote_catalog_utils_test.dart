import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/remote_audio_track.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/screens/remote_catalog_utils.dart';

void main() {
  RemoteAudioTrack track({
    required String id,
    String title = 'Song',
    String? artist,
    String? album,
    String format = 'flac',
  }) {
    return RemoteAudioTrack(
      id: id,
      title: title,
      artist: artist,
      album: album,
      format: format,
      byteLength: 10,
      streamPath: '/stream/$id',
      downloadPath: '/download/$id',
    );
  }

  test('groups remote catalog by artist with unknown fallback', () {
    final groups = groupRemoteCatalog(
      [
        track(id: '1', title: 'B', artist: 'Bowie'),
        track(id: '2', title: 'A', artist: 'Bowie'),
        track(id: '3', artist: null),
      ],
      RemoteCatalogGrouping.artists,
    );

    expect(groups.keys, containsAll(<String>['Bowie', '未知艺人']));
    expect(groups['Bowie']!.map((item) => item.title), <String>['A', 'B']);
  });

  test('groups remote catalog by album', () {
    final groups = groupRemoteCatalog(
      [
        track(id: '1', album: 'Low'),
        track(id: '2', album: 'Heroes'),
      ],
      RemoteCatalogGrouping.albums,
    );
    expect(groups.keys.toList(), <String>['Heroes', 'Low']);
  });

  test('recognises app-managed download paths on iOS and Windows', () {
    expect(
      isManagedRemoteDownloadPath('/var/mobile/Documents/LyricForge/Downloads/a.flac'),
      isTrue,
    );
    expect(
      isManagedRemoteDownloadPath(r'C:\Users\me\LyricForge\Downloads\a.flac'),
      isTrue,
    );
    expect(isManagedRemoteDownloadPath('/Music/a.flac'), isFalse);
  });

  test('matches downloaded entry by stable remote id suffix', () {
    final now = DateTime(2026, 10, 8);
    final entry = LocalMediaLibraryEntry(
      sourcePath: '/docs/LyricForge/Downloads/Song_abcdef12.flac',
      format: 'flac',
      addedAt: now,
      lastSeenAt: now,
    );
    expect(
      remoteTrackMatchesDownloadedEntry(
        track(id: 'abcdef1234567890'),
        entry,
      ),
      isTrue,
    );
  });
}
