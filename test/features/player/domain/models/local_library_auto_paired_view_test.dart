import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_library_browse_item.dart';

void main() {
  final added = DateTime(2026, 11, 1);

  LocalLibraryBrowseItem song(
    String title, {
    bool lyrics = false,
    bool autoPaired = false,
  }) {
    return LocalLibraryBrowseItem(
      sourcePath: '/music/$title.mp3',
      title: title,
      addedAt: added,
      hasLyrics: lyrics,
      hasAutoPairedLyrics: autoPaired,
    );
  }

  final songs = [
    song('手工歌词', lyrics: true),
    song('自动配对', lyrics: true, autoPaired: true),
    song('没有歌词'),
    // A stale flag without lyrics is not an automatic pairing.
    song('旧记录', autoPaired: true),
  ];

  List<String> titles(LocalLibrarySmartView view) {
    final found = queryLocalLibrary(
      items: songs,
      browseItem: (item) => item,
      smartView: view,
    );
    return [for (final item in found) item.title];
  }

  test('自动配对 lists songs whose lyrics came from a file name', () {
    expect(titles(LocalLibrarySmartView.autoPairedLyrics), ['自动配对']);
  });

  test('automatic pairings still count as songs with lyrics', () {
    expect(titles(LocalLibrarySmartView.withLyrics), ['手工歌词', '自动配对']);
    expect(titles(LocalLibrarySmartView.withoutLyrics), ['旧记录', '没有歌词']);
  });

  test('search works inside the view', () {
    final more = [
      ...songs,
      song('晴天', lyrics: true, autoPaired: true),
      song('稻香', lyrics: true, autoPaired: true),
    ];

    final found = queryLocalLibrary(
      items: more,
      browseItem: (item) => item,
      query: '晴',
      smartView: LocalLibrarySmartView.autoPairedLyrics,
    );

    expect(found.map((item) => item.title), ['晴天']);
  });

  test('the view sits next to the other lyric views', () {
    final views = LocalLibrarySmartView.values;

    expect(
      views.indexOf(LocalLibrarySmartView.autoPairedLyrics),
      views.indexOf(LocalLibrarySmartView.withoutLyrics) + 1,
    );
  });
}
