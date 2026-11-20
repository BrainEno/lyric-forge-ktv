import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/local_library_semantics.dart';

// The local library's cards as a screen reader reads them (audit A-04).

void main() {
  group('spoken', () {
    test('turns the visible dots into commas', () {
      expect(LocalLibrarySemantics.spoken('12 首 · 3 张专辑'), '12 首，3 张专辑');
      expect(LocalLibrarySemantics.spoken('#3 · FLAC'), '#3，FLAC');
    });

    test('drops empty pieces', () {
      expect(LocalLibrarySemantics.spoken(' · MP3'), 'MP3');
      expect(LocalLibrarySemantics.spoken(''), isEmpty);
    });
  });

  group('catalogCard', () {
    test('an artist card', () {
      expect(
        LocalLibrarySemantics.catalogCard(title: '周杰伦', detail: '12 首 · 3 张专辑'),
        '周杰伦，12 首，3 张专辑',
      );
    });

    test('an album card', () {
      expect(
        LocalLibrarySemantics.catalogCard(title: '叶惠美', detail: '周杰伦 · 11 首'),
        '叶惠美，周杰伦，11 首',
      );
    });

    test('a blank title is named', () {
      expect(
        LocalLibrarySemantics.catalogCard(title: ' ', detail: '1 首'),
        '未命名，1 首',
      );
    });
  });

  test('miniAlbum', () {
    expect(
      LocalLibrarySemantics.miniAlbum(title: '范特西', songs: 10),
      '范特西，10 首',
    );
  });

  group('playlistCard', () {
    test('without missing songs', () {
      expect(
        LocalLibrarySemantics.playlistCard(name: '通勤', songs: 24, missing: 0),
        '通勤，24 首歌曲',
      );
    });

    test('says how many songs are unavailable', () {
      expect(
        LocalLibrarySemantics.playlistCard(name: '通勤', songs: 24, missing: 2),
        '通勤，24 首歌曲，2 首不可用',
      );
    });
  });

  group('songCard', () {
    test('a playable song with its details', () {
      expect(
        LocalLibrarySemantics.songCard(
          title: '晴天',
          artist: '周杰伦',
          playable: true,
          details: ['#3 · FLAC', '已编辑', '有歌词'],
        ),
        '晴天，周杰伦，#3，FLAC，已编辑，有歌词',
      );
    });

    test('a song without an artist reads as local music', () {
      expect(
        LocalLibrarySemantics.songCard(
          title: '录音',
          artist: ' ',
          playable: true,
          details: ['M4A'],
        ),
        '录音，本地音乐，M4A',
      );
    });

    test('an unavailable song says so instead of the artist', () {
      expect(
        LocalLibrarySemantics.songCard(
          title: '晴天',
          artist: '周杰伦',
          playable: false,
          details: ['MP3'],
        ),
        '晴天，${LocalLibrarySemantics.unavailableLabel}，MP3',
      );
    });
  });
}
