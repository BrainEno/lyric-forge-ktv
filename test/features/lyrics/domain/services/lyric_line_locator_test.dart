import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_line_locator.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

/// Rows 4 s apart, each sung for 2 s: row i covers [4i+1, 4i+3) seconds.
LyricDocument _document(int count) {
  return LyricDocument(
    language: 'zh',
    lines: [
      for (var index = 0; index < count; index++)
        LyricLine(
          text: '第$index句',
          startTime: Duration(seconds: index * 4 + 1),
          endTime: Duration(seconds: index * 4 + 3),
        ),
    ],
  );
}

void main() {
  final document = _document(30);

  int? row(String text) => LyricLineLocator.locate(document, text).index;

  group('row numbers', () {
    test('count from one, as the list shows them', () {
      expect(row('1'), 0);
      expect(row('12'), 11);
      expect(row(' 30 '), 29);
    });

    test('accept 第 N 行, #N and full-width digits', () {
      expect(row('第12行'), 11);
      expect(row('第 12 行'), 11);
      expect(row('#7'), 6);
      expect(row('１２'), 11);
      expect(row('12行'), 11);
    });

    test('outside the song say how many rows there are', () {
      final location = LyricLineLocator.locate(document, '31');
      expect(location.isValid, isFalse);
      expect(location.problem, '没有第 31 行，这首歌一共 30 行');
      expect(
        LyricLineLocator.locate(document, '0').problem,
        contains('一共 30 行'),
      );
    });
  });

  group('times', () {
    test('a time finds the row sung then', () {
      final location = LyricLineLocator.locate(document, '0:09.5');
      expect(location.index, 2);
      expect(location.time, const Duration(milliseconds: 9500));
    });

    test('minutes and seconds, seconds with a unit or a decimal point', () {
      expect(row('1:05'), 16);
      expect(row('65s'), 16);
      expect(row('65 秒'), 16);
      expect(row('65.0'), 16);
      expect(row('1：05'), 16);
    });

    test('a gap between rows goes to the next row', () {
      expect(row('0:04'), 1);
    });

    test('past the last row goes to the last row', () {
      expect(row('9:00'), 29);
    });

    test('negative or unreadable input explains itself', () {
      expect(LyricLineLocator.locate(document, '-3').problem, '时间不能是负数');
      expect(
        LyricLineLocator.locate(document, 'abc').problem,
        contains('请填行号'),
      );
    });
  });

  test('empty input shows the hint, an empty song says so', () {
    expect(LyricLineLocator.locate(document, '  ').problem, contains('1–30'));
    const empty = LyricDocument(language: 'zh', lines: []);
    expect(LyricLineLocator.locate(empty, '1').problem, '还没有歌词行');
  });

  test('overlapping rows prefer the one that started last', () {
    const overlapping = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: 'a',
          startTime: Duration(seconds: 1),
          endTime: Duration(seconds: 10),
        ),
        LyricLine(
          text: 'b',
          startTime: Duration(seconds: 4),
          endTime: Duration(seconds: 6),
        ),
      ],
    );
    expect(LyricLineLocator.rowAt(overlapping, const Duration(seconds: 5)), 1);
    expect(LyricLineLocator.rowAt(overlapping, const Duration(seconds: 8)), 0);
  });
}
