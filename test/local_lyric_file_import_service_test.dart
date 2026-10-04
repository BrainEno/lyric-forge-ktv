import 'dart:io';

import 'package:charset/charset.dart' as charset;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';

void main() {
  group('LocalLyricFileImportService', () {
    late LocalLyricFileImportService service;
    late Directory directory;

    setUp(() async {
      service = LocalLyricFileImportService();
      directory = await Directory.systemTemp.createTemp('lyricforge-lyrics-');
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('parses LRC metadata offset and multiple timestamps', () {
      final result = service.parseText(
        '[ti:夜に駆ける]\n'
        '[ar:YOASOBI]\n'
        '[al:THE BOOK]\n'
        '[offset:250]\n'
        '[00:01.00][00:03.50]沈むように溶けてゆくように\n'
        '[00:08.25]二人だけの空が広がる夜に',
        extension: 'lrc',
      );

      expect(result.format, LyricImportFormat.lrc);
      expect(result.title, '夜に駆ける');
      expect(result.artist, 'YOASOBI');
      expect(result.album, 'THE BOOK');
      expect(result.document.globalOffset, const Duration(milliseconds: 250));
      expect(result.document.lines, hasLength(3));
      expect(result.document.lines[0].startTime, const Duration(seconds: 1));
      expect(
        result.document.lines[1].startTime,
        const Duration(seconds: 3, milliseconds: 500),
      );
      expect(result.document.lines[2].text, '二人だけの空が広がる夜に');
    });

    test('parses SRT multiline cues', () {
      final result = service.parseText(
        '1\n'
        '00:00:01,250 --> 00:00:03,000\n'
        '第一行\n第二行\n\n'
        '2\n'
        '00:00:04,000 --> 00:00:06,500\n'
        '続き',
        extension: 'srt',
      );

      expect(result.document.lines, hasLength(2));
      expect(result.document.lines.first.text, '第一行\n第二行');
      expect(
        result.document.lines.first.startTime,
        const Duration(seconds: 1, milliseconds: 250),
      );
      expect(
        result.document.lines.last.endTime,
        const Duration(seconds: 6, milliseconds: 500),
      );
    });

    test('parses WebVTT cue identifiers and settings', () {
      final result = service.parseText(
        'WEBVTT\n\n'
        'cue-1\n'
        '00:01.000 --> 00:03.000 position:50%\n'
        '<b>Hello 世界</b>',
        extension: 'vtt',
      );

      expect(result.format, LyricImportFormat.webvtt);
      expect(result.document.lines.single.text, 'Hello 世界');
      expect(
        result.document.lines.single.startTime,
        const Duration(seconds: 1),
      );
    });

    test('parses ASS dialogue and strips override tags', () {
      final result = service.parseText(
        '[Script Info]\nTitle: Test\n\n'
        '[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        r'Dialogue: 0,0:00:01.20,0:00:04.50,Default,,0,0,0,,{\an8}上段\N下段',
        extension: 'ass',
      );

      expect(result.format, LyricImportFormat.ass);
      expect(result.document.lines, hasLength(1));
      expect(result.document.lines.single.text, '上段\n下段');
      expect(
        result.document.lines.single.startTime,
        const Duration(seconds: 1, milliseconds: 200),
      );
    });

    test('keeps plain text explicitly unsynchronised', () {
      final result = service.parseText(
        '第一句\n\n第二句\n第三句',
        extension: 'txt',
      );

      expect(result.format, LyricImportFormat.plainText);
      expect(result.document.lines, hasLength(3));
      expect(
        result.document.lines.every(
          (line) => line.startTime == Duration.zero,
        ),
        isTrue,
      );
      expect(result.document.metadata['timed'], isFalse);
    });

    test('imports a GBK encoded Chinese LRC with an explicit hint', () async {
      final file = File('${directory.path}${Platform.pathSeparator}中文歌词.lrc');
      await file.writeAsBytes(
        charset.gbk.encode('[00:01.00]中文歌词测试\n[00:03.00]下一句'),
      );

      final result = await service.importFile(file.path, encodingHint: 'gbk');

      expect(result.detectedEncoding.toLowerCase(), 'gbk');
      expect(result.document.lines.first.text, '中文歌词测试');
      expect(result.document.lines.last.text, '下一句');
    });

    test('imports a Shift-JIS Japanese LRC with an explicit hint', () async {
      final file = File('${directory.path}${Platform.pathSeparator}日本語.lrc');
      await file.writeAsBytes(
        charset.shiftJis.encode('[00:01.00]夜空を見上げる\n[00:04.00]君を想う'),
      );

      final result = await service.importFile(
        file.path,
        encodingHint: 'shift_jis',
      );

      expect(result.document.lines.first.text, '夜空を見上げる');
      expect(result.document.lines.last.text, '君を想う');
    });

    test('rejects unsupported lyric formats', () async {
      final file = File('${directory.path}${Platform.pathSeparator}lyrics.docx');
      await file.writeAsString('not lyrics');

      await expectLater(
        service.importFile(file.path),
        throwsA(isA<LyricImportException>()),
      );
    });
  });
}
