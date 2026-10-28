import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_library_browse_item.dart';

void main() {
  final now = DateTime(2026, 10, 4, 12);

  LocalLibraryBrowseItem item(
    String title, {
    String? artist,
    String? album,
    List<String> genres = const [],
    List<String> playlists = const [],
    DateTime? addedAt,
    DateTime? lastPlayedAt,
    bool hasLyrics = false,
    bool edited = false,
    bool missing = false,
  }) {
    return LocalLibraryBrowseItem(
      sourcePath: '/music/$title.mp3',
      title: title,
      artist: artist,
      album: album,
      genres: genres,
      playlistNames: playlists,
      addedAt: addedAt ?? now,
      lastPlayedAt: lastPlayedAt,
      hasLyrics: hasLyrics,
      hasUserOverride: edited,
      isMissing: missing,
    );
  }

  test('global search includes playlist names and Unicode metadata', () {
    final songs = [
      item(
        'First Love',
        artist: '宇多田ヒカル',
        album: 'First Love',
        playlists: const ['深夜阅读'],
      ),
      item('普通歌曲', artist: '测试艺人'),
    ];

    final byPlaylist = queryLocalLibrary<LocalLibraryBrowseItem>(
      items: songs,
      browseItem: (value) => value,
      query: '深夜阅读',
    );
    final byArtist = queryLocalLibrary<LocalLibraryBrowseItem>(
      items: songs,
      browseItem: (value) => value,
      query: '宇多田',
    );

    expect(byPlaylist.map((value) => value.title), ['First Love']);
    expect(byArtist.map((value) => value.title), ['First Love']);
  });

  test('recently added uses a 30-day window', () {
    final songs = [
      item('new', addedAt: now.subtract(const Duration(days: 29))),
      item('boundary', addedAt: now.subtract(const Duration(days: 30))),
      item('old', addedAt: now.subtract(const Duration(days: 31))),
    ];

    final result = queryLocalLibrary<LocalLibraryBrowseItem>(
      items: songs,
      browseItem: (value) => value,
      smartView: LocalLibrarySmartView.recentlyAdded,
      now: now,
    );

    expect(result.map((value) => value.title).toSet(), {'new', 'boundary'});
  });

  test('smart lyric/edit/missing views are independent filters', () {
    final songs = [
      item('lyrics', hasLyrics: true),
      item('edited', edited: true),
      item('missing', missing: true),
      item('plain'),
    ];

    List<String> titles(LocalLibrarySmartView view) =>
        queryLocalLibrary<LocalLibraryBrowseItem>(
          items: songs,
          browseItem: (value) => value,
          smartView: view,
          now: now,
        ).map((value) => value.title).toList(growable: false);

    expect(titles(LocalLibrarySmartView.withLyrics), ['lyrics']);
    expect(titles(LocalLibrarySmartView.withoutLyrics).toSet(), {
      'edited',
      'missing',
      'plain',
    });
    expect(titles(LocalLibrarySmartView.editedMetadata), ['edited']);
    expect(titles(LocalLibrarySmartView.missingFiles), ['missing']);
  });

  test('recently played sorts newest first and null last', () {
    final songs = [
      item('never'),
      item('older', lastPlayedAt: now.subtract(const Duration(hours: 4))),
      item('newer', lastPlayedAt: now.subtract(const Duration(minutes: 5))),
    ];

    final result = queryLocalLibrary<LocalLibraryBrowseItem>(
      items: songs,
      browseItem: (value) => value,
      sortMode: LocalLibrarySortMode.recentlyPlayed,
    );

    expect(result.map((value) => value.title), ['newer', 'older', 'never']);
  });

  test('artist and album sorting place missing metadata last', () {
    final songs = [
      item('unknown'),
      item('b', artist: 'B', album: 'Z'),
      item('a', artist: 'A', album: 'A'),
    ];

    final byArtist = queryLocalLibrary<LocalLibraryBrowseItem>(
      items: songs,
      browseItem: (value) => value,
      sortMode: LocalLibrarySortMode.artist,
    );
    final byAlbum = queryLocalLibrary<LocalLibraryBrowseItem>(
      items: songs,
      browseItem: (value) => value,
      sortMode: LocalLibrarySortMode.album,
    );

    expect(byArtist.map((value) => value.title), ['a', 'b', 'unknown']);
    expect(byAlbum.map((value) => value.title), ['a', 'b', 'unknown']);
  });
}
