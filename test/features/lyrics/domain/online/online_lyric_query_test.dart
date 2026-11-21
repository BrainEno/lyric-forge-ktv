import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_query.dart';

void main() {
  group('OnlineLyricQuery.fromProject', () {
    test('文件名去掉扩展名、曲目编号和括号里的版本说明', () {
      final query = OnlineLyricQuery.fromProject(
        name: '03. 夜航 (Live) [MV].mp3',
        artist: '林小雨',
      );
      expect(query.title, '夜航');
      expect(query.artist, '林小雨');
    });

    test('没有歌手时把「歌手 - 歌名」拆开', () {
      final query = OnlineLyricQuery.fromProject(name: '林小雨 - 夜航.flac');
      expect(query.artist, '林小雨');
      expect(query.title, '夜航');
    });

    test('已知歌手出现在名字里时只保留歌名', () {
      final left = OnlineLyricQuery.fromProject(
        name: '林小雨 - 夜航',
        artist: '林小雨',
      );
      expect(left.title, '夜航');
      final right = OnlineLyricQuery.fromProject(
        name: '夜航 - 林小雨',
        artist: '林小雨',
      );
      expect(right.title, '夜航');
    });

    test('去掉 feat. 署名', () {
      final query = OnlineLyricQuery.fromProject(
        name: 'Night Flight feat. Someone',
        artist: 'Lin',
      );
      expect(query.title, 'Night Flight');
    });

    test('只剩括号时保留括号内容，避免歌名为空', () {
      expect(OnlineLyricQuery.cleanTitle('【夜航】'), isNotEmpty);
    });

    test('非正的时长视为未知', () {
      final query = OnlineLyricQuery.fromProject(
        name: '夜航',
        duration: Duration.zero,
      );
      expect(query.duration, isNull);
    });

    test('空名字不可搜索', () {
      expect(OnlineLyricQuery.fromProject(name: '  ').isSearchable, isFalse);
    });
  });

  test('keywords 合并歌名和歌手', () {
    expect(
      const OnlineLyricQuery(title: '夜航', artist: '林小雨').keywords,
      '夜航 林小雨',
    );
    expect(const OnlineLyricQuery(title: '夜航').keywords, '夜航');
  });

  test('copyWith 保留时长', () {
    const query = OnlineLyricQuery(
      title: '夜航',
      duration: Duration(seconds: 200),
    );
    final changed = query.copyWith(title: '晚安', artist: '某人');
    expect(changed.title, '晚安');
    expect(changed.artist, '某人');
    expect(changed.duration, const Duration(seconds: 200));
  });
}
