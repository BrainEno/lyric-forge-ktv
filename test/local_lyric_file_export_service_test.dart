import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  group('LocalLyricFileExportService', () {
    const exporter = LocalLyricFileExportService();

    test(
      'encodes metadata and effective millisecond timestamps without offset tag',
      () {
        final document = LyricDocument(
          language: 'ja',
          globalOffset: const Duration(milliseconds: -120),
          lines: const [
            LyricLine(
              text: '世界へ\nhello',
              startTime: Duration(milliseconds: 61234),
              endTime: Duration(milliseconds: 64500),
            ),
            LyricLine(
              text: '第一行',
              startTime: Duration(milliseconds: 1250),
              endTime: Duration(milliseconds: 3000),
            ),
          ],
        );

        final encoded = exporter.encodeLrc(
          document,
          title: '夜に駆ける',
          artist: 'YOASOBI',
          album: 'THE BOOK',
        );

        expect(encoded, contains('[ti:夜に駆ける]'));
        expect(encoded, contains('[ar:YOASOBI]'));
        expect(encoded, contains('[al:THE BOOK]'));
        expect(encoded, contains('[lang:ja]'));
        expect(encoded, contains('[re:LyricForge]'));
        expect(encoded, contains('[ve:1]'));
        expect(encoded, isNot(contains('[offset:')));
        expect(encoded, contains('[00:01.130]第一行'));
        expect(encoded, contains('[01:01.114]世界へ hello'));
        expect(
          encoded.indexOf('[00:01.130]'),
          lessThan(encoded.indexOf('[01:01.114]')),
        );
      },
    );

    test(
      'round-trips effective playback timing through LRC import',
      () {
        final source = LyricDocument(
          language: 'zh',
          globalOffset: const Duration(milliseconds: 80),
          lines: const [
            LyricLine(
              text: '你好吗',
              startTime: Duration(milliseconds: 3456),
              endTime: Duration(milliseconds: 6400),
            ),
            LyricLine(
              text: 'I am fine',
              startTime: Duration(milliseconds: 7123),
              endTime: Duration(milliseconds: 9000),
            ),
          ],
        );

        final encoded = exporter.encodeLrc(source, title: 'demo');
        final imported = LocalLyricFileImportService().parseText(
          encoded,
          extension: 'lrc',
        );

        expect(imported.document.language, 'zh');
        expect(imported.document.globalOffset, isNull);
        expect(imported.document.lines, hasLength(2));
        expect(imported.document.lines[0].text, '你好吗');
        expect(
          imported.document.lines[0].startTime,
          const Duration(milliseconds: 3536),
        );
        expect(imported.document.lines[1].text, 'I am fine');
        expect(
          imported.document.lines[1].startTime,
          const Duration(milliseconds: 7203),
        );
      },
    );

    test('clamps negative effective timestamps to zero', () {
      final document = LyricDocument(
        language: 'en',
        globalOffset: const Duration(milliseconds: -100),
        lines: const [
          LyricLine(
            text: 'start',
            startTime: Duration(milliseconds: 50),
            endTime: Duration(seconds: 1),
          ),
        ],
      );

      final encoded = exporter.encodeLrc(document);

      expect(encoded, contains('[00:00.000]start'));
    });

    test('omits empty lyric rows from LRC output', () {
      final document = LyricDocument(
        language: 'und',
        lines: const [
          LyricLine(
            text: '   ',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
          ),
          LyricLine(
            text: 'kept',
            startTime: Duration(seconds: 1),
            endTime: Duration(seconds: 2),
          ),
        ],
      );

      final encoded = exporter.encodeLrc(document);

      expect(encoded, isNot(contains('[00:00.000]')));
      expect(encoded, contains('[00:01.000]kept'));
    });
  });
}
