import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/reference_lyric_text_parser.dart';

void main() {
  final parser = ReferenceLyricTextParser(LocalLyricFileImportService());

  group('detectExtension', () {
    test('识别带时间戳的 LRC', () {
      expect(
        ReferenceLyricTextParser.detectExtension('[00:12.34]月亮代表我的心'),
        'lrc',
      );
    });

    test('仅有 LRC 元数据也按 LRC 处理', () {
      expect(ReferenceLyricTextParser.detectExtension('[ti:月亮代表我的心]'), 'lrc');
    });

    test('识别 SRT / WebVTT / ASS 字幕', () {
      expect(
        ReferenceLyricTextParser.detectExtension(
          '1\n00:00:01,000 --> 00:00:03,000\n你好',
        ),
        'srt',
      );
      expect(
        ReferenceLyricTextParser.detectExtension(
          'WEBVTT\n\n00:01.000 --> 00:03.000\n你好',
        ),
        'vtt',
      );
      expect(
        ReferenceLyricTextParser.detectExtension(
          '[Events]\nFormat: Text\nDialogue: 0,0:00:01.00,0:00:03.00,,你好',
        ),
        'ass',
      );
    });

    test('其他文本按纯文本处理', () {
      expect(ReferenceLyricTextParser.detectExtension('月亮代表我的心'), 'txt');
    });
  });

  group('parsePasted', () {
    test('纯文本只有文字，无时间戳', () {
      final input = parser.parsePasted('月亮代表我的心\n轻轻的一个吻');

      expect(input.timed, isFalse);
      expect(input.format, 'plainText');
      expect(input.offset, Duration.zero);
      expect(input.sourcePath, isNull);
      expect(input.lineCount, 2);
      expect(input.lines.first.text, '月亮代表我的心');
      expect(input.lines.first.startTime, isNull);
    });

    test('纯文本忽略整体偏移，空行被过滤', () {
      final input = parser.parsePasted(
        '第一句\n\n   \n第二句\n',
        offset: const Duration(milliseconds: 500),
      );

      expect(input.timed, isFalse);
      expect(input.lineCount, 2);
      expect(input.offset, Duration.zero);
    });

    test('LRC 解析为带时间戳的参考行并回填标题', () {
      final input = parser.parsePasted(
        '[ti:月亮代表我的心]\n[ar:邓丽君]\n[00:01.00]第一句\n[00:05.00]第二句\n',
      );

      expect(input.timed, isTrue);
      expect(input.format, 'lrc');
      expect(input.title, '月亮代表我的心');
      expect(input.artist, '邓丽君');
      expect(input.lines[0].startTime, const Duration(seconds: 1));
      expect(input.lines[0].endTime, const Duration(seconds: 5));
      expect(input.lines[1].startTime, const Duration(seconds: 5));
      expect(input.lines[1].endTime, const Duration(seconds: 10));
    });

    test('用户传入的歌名/艺术家优先于 LRC 标签', () {
      final input = parser.parsePasted(
        '[ti:原名]\n[00:01.00]第一句\n',
        title: '工程名',
        artist: '工程歌手',
      );

      expect(input.title, '工程名');
      expect(input.artist, '工程歌手');
    });

    test('整体偏移同时作用于开始与结束时间', () {
      final input = parser.parsePasted(
        '[00:01.00]第一句\n[00:05.00]第二句\n',
        offset: const Duration(milliseconds: 500),
      );

      expect(input.offset, const Duration(milliseconds: 500));
      expect(input.lines[0].startTime, const Duration(milliseconds: 1500));
      expect(input.lines[0].endTime, const Duration(milliseconds: 5500));
      expect(input.lines[1].startTime, const Duration(milliseconds: 5500));
      expect(input.lines[1].endTime, const Duration(milliseconds: 10500));
    });

    test('LRC offset 标签与用户偏移叠加，负偏移不小于零', () {
      final input = parser.parsePasted(
        '[offset:-500]\n[00:00.20]第一句\n[00:03.00]第二句\n',
        offset: const Duration(milliseconds: -100),
      );

      expect(input.offset, const Duration(milliseconds: -600));
      expect(input.lines[0].startTime, Duration.zero);
      expect(input.lines[0].endTime, const Duration(milliseconds: 2400));
    });

    test('SRT 粘贴走字幕解析并保留时间戳', () {
      final input = parser.parsePasted(
        '1\n00:00:01,000 --> 00:00:03,000\n你好\n',
      );

      expect(input.timed, isTrue);
      expect(input.format, 'srt');
      expect(input.lineCount, 1);
      expect(input.lines.first.startTime, const Duration(seconds: 1));
      expect(input.lines.first.endTime, const Duration(seconds: 3));
    });

    test('空文本与纯空白文本报错', () {
      expect(
        () => parser.parsePasted('   '),
        throwsA(isA<ReferenceLyricParseException>()),
      );
    });

    test('只有 LRC 元数据报错', () {
      expect(
        () => parser.parsePasted('[ti:歌名]\n[ar:歌手]'),
        throwsA(isA<ReferenceLyricParseException>()),
      );
    });

    test('纯文本里只有空白行报错', () {
      expect(
        () => parser.parsePasted('   \n\n \n'),
        throwsA(isA<ReferenceLyricParseException>()),
      );
    });
  });

  group('parseFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ref_lyric_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('读取本地文件并带上来源路径', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}ref.lrc');
      await file.writeAsString('[00:01.00]第一句\n');

      final input = await parser.parseFile(
        file.path,
        offset: const Duration(seconds: 1),
      );

      expect(input.timed, isTrue);
      expect(input.format, 'lrc');
      expect(input.sourcePath, file.path);
      expect(input.lines.single.startTime, const Duration(seconds: 2));
    });
  });
}
