import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/media_file_names.dart';

void main() {
  const pickerName = 'image_20312602-F017-4D87-A99C-F527F145A697_1795329754';

  group('isGeneratedMediaName', () {
    test('spots names a picker made up', () {
      expect(isGeneratedMediaName(pickerName), isTrue);
      expect(
        isGeneratedMediaName('20312602-F017-4D87-A99C-F527F145A697'),
        isTrue,
      );
      expect(isGeneratedMediaName('1795329754'), isTrue);
      expect(isGeneratedMediaName(''), isTrue);
    });

    test('keeps names a person chose', () {
      expect(isGeneratedMediaName('周杰伦 - 晴天'), isFalse);
      expect(isGeneratedMediaName('IMG_1234'), isFalse);
      expect(isGeneratedMediaName('2024 live'), isFalse);
    });
  });

  group('readableMediaName', () {
    test('drops the made-up parts and keeps the rest', () {
      expect(readableMediaName(pickerName), isNull);
      expect(readableMediaName('trim.20312602-F017-4D87-A99C-F527F145A697'),
          isNull);
      expect(
        readableMediaName('晴天_20312602-F017-4D87-A99C-F527F145A697'),
        '晴天',
      );
      expect(readableMediaName(' 晴天 '), '晴天');
    });
  });

  test('songTitleFromPath names a picker file 未命名歌曲', () {
    expect(
      songTitleFromPath('/docs/Imported Audio/$pickerName.m4a'),
      untitledSongTitle,
    );
    expect(songTitleFromPath(r'C:\music\晴天.mp3'), '晴天');
    expect(songTitleFromPath('/music/.hidden'), '.hidden');
  });

  test('importedMediaStem dates a made-up name', () {
    final now = DateTime(2026, 1, 2, 3, 4);
    expect(
      importedMediaStem(pickerName, video: true, now: now),
      '导入的视频 2026-01-02 03.04',
    );
    expect(
      importedMediaStem('1795329754', video: false, now: now),
      '导入的音频 2026-01-02 03.04',
    );
    expect(importedMediaStem('晴天', video: true, now: now), '晴天');
  });
}
