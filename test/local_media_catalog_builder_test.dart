import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/local_media_catalog_builder.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';

void main() {
  const builder = LocalMediaCatalogBuilder();
  final timestamp = DateTime(2026, 10, 4);

  LocalMediaLibraryEntry entry(
    String path, {
    String? title,
    String? artist,
    String? album,
    int? track,
    int? year,
    bool missing = false,
  }) {
    return LocalMediaLibraryEntry(
      sourcePath: path,
      format: 'mp3',
      addedAt: timestamp,
      lastSeenAt: timestamp,
      isMissing: missing,
      embeddedTitle: title,
      embeddedArtist: artist,
      embeddedAlbum: album,
      embeddedTrackNumber: track,
      embeddedYear: year,
    );
  }

  test('groups Unicode artists and sorts album tracks by track number', () {
    final catalog = builder.build(
      entries: [
        entry(
          '/music/02.mp3',
          title: '群青',
          artist: 'YOASOBI',
          album: 'THE BOOK',
          track: 2,
        ),
        entry(
          '/music/01.mp3',
          title: '夜に駆ける',
          artist: 'YOASOBI',
          album: 'THE BOOK',
          track: 1,
        ),
        entry(
          '/music/03.mp3',
          title: '夜曲',
          artist: '周杰伦',
          album: '十一月的萧邦',
          track: 3,
        ),
      ],
      overrides: const [],
    );

    expect(catalog.artists.map((artist) => artist.name), ['YOASOBI', '周杰伦']);
    final album = catalog.albums.singleWhere((item) => item.title == 'THE BOOK');
    expect(album.tracks.map((track) => track.title), ['夜に駆ける', '群青']);
  });

  test('user artist and album overrides determine catalog grouping', () {
    final catalog = builder.build(
      entries: [
        entry(
          '/music/raw.mp3',
          title: 'Original title',
          artist: 'Wrong Artist',
          album: 'Wrong Album',
        ),
      ],
      overrides: [
        LocalMediaMetadata(
          sourcePath: '/music/raw.mp3',
          title: '修正タイトル',
          artist: '宇多田ヒカル',
          album: 'First Love',
          updatedAt: timestamp,
        ),
      ],
    );

    expect(catalog.tracks.single.title, '修正タイトル');
    expect(catalog.artists.single.name, '宇多田ヒカル');
    expect(catalog.albums.single.title, 'First Love');
  });

  test('same album title stays one album and reports multiple artists', () {
    final catalog = builder.build(
      entries: [
        entry(
          '/music/a.mp3',
          title: 'A',
          artist: 'Artist A',
          album: 'Compilation',
          track: 1,
        ),
        entry(
          '/music/b.mp3',
          title: 'B',
          artist: 'Artist B',
          album: 'Compilation',
          track: 2,
        ),
      ],
      overrides: const [],
    );

    expect(catalog.albums, hasLength(1));
    expect(catalog.albums.single.artistLabel, '多位艺人');
    expect(catalog.albums.single.artists, ['Artist A', 'Artist B']);
  });

  test('missing tracks remain visible but are excluded from available counts', () {
    final catalog = builder.build(
      entries: [
        entry(
          '/music/online.mp3',
          title: 'Online',
          artist: 'Artist',
          album: 'Album',
        ),
        entry(
          '/music/offline.mp3',
          title: 'Offline',
          artist: 'Artist',
          album: 'Album',
          missing: true,
        ),
      ],
      overrides: const [],
    );

    expect(catalog.artists.single.tracks, hasLength(2));
    expect(catalog.artists.single.availableTrackCount, 1);
    expect(catalog.albums.single.availableTrackCount, 1);
  });
}
