import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_export_encoder.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
LyricLine line(String text, int startMs, int endMs) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
);

void main() {
  const encoder = LyricExportEncoder();

  final song = LyricDocument(
    language: 'zh',
    lines: [
      line('第一句', 1000, 3000),
      line('第二句', 3500, 5000),
      line('   ', 5200, 5600),
      line('第三句', 10000, 12000),
    ],
  );

  group('LRC', () {
    test('matches the service encoding when end markers are off', () {
      const service = LocalLyricFileExportService();
      expect(
        encoder.encodeLrc(
          song,
          metadata: const LyricExportMetadata(title: '测试歌'),
        ),
        service.encodeLrc(song, title: '测试歌'),
      );
    });

    test(
      'end markers clear the lyric before pauses and after the last row',
      () {
        final encoded = encoder.encodeLrc(song, endMarkers: true);
        final body = encoded
            .split('\n')
            .where((l) => l.startsWith('[0'))
            .toList();
        expect(body, [
          '[00:01.000]第一句',
          '[00:03.500]第二句',
          '[00:05.000]',
          '[00:10.000]第三句',
          '[00:12.000]',
        ]);
      },
    );

    test('end markers survive an import round trip as row ends', () {
      final encoded = encoder.encode(
        song,
        LyricExportFormat.lrc,
        options: const LyricExportOptions(lrcEndMarkers: true),
      );
      final imported = LocalLyricFileImportService()
          .parseText(encoded, extension: 'lrc')
          .document;
      expect(imported.lines.map((l) => l.text), ['第一句', '第二句', '第三句']);
      expect(imported.lines.map((l) => l.endTime.inMilliseconds), [
        3500,
        5000,
        12000,
      ]);
    });
  });

  group('subtitles', () {
    test('SRT numbers cues and uses comma milliseconds', () {
      final encoded = encoder.encodeSrt(
        LyricDocument(
          language: 'zh',
          globalOffset: const Duration(milliseconds: 250),
          lines: [line('第一句', 1000, 3000), line('第二句', 3725000, 3727500)],
        ),
      );
      expect(
        encoded,
        '1\n'
        '00:00:01,250 --> 00:00:03,250\n'
        '第一句\n'
        '\n'
        '2\n'
        '01:02:05,250 --> 01:02:07,750\n'
        '第二句\n',
      );
    });

    test('cues never overlap and a missing end gets a fallback', () {
      final cues = encoder.subtitleCues(
        LyricDocument(
          language: 'zh',
          lines: [
            line('第一句', 0, 4000),
            line('第二句', 3000, 3000),
            line('第三句', 20000, 19000),
          ],
        ),
      );
      expect(cues.map((c) => (c.start.inMilliseconds, c.end.inMilliseconds)), [
        (0, 3000),
        (3000, 6000),
        (20000, 23000),
      ]);
    });

    test('WebVTT has a header, a title note and escaped text', () {
      final encoded = encoder.encodeVtt(
        LyricDocument(language: 'en', lines: [line('rock & <roll>', 0, 1500)]),
        metadata: const LyricExportMetadata(title: 'Demo', artist: 'Band'),
      );
      expect(
        encoded,
        'WEBVTT\n'
        '\n'
        'NOTE\n'
        'Demo - Band\n'
        '\n'
        '00:00:00.000 --> 00:00:01.500\n'
        'rock &amp; &lt;roll&gt;\n',
      );
    });

    test('WebVTT escaping is undone on import', () {
      final encoded = encoder.encodeVtt(
        LyricDocument(language: 'en', lines: [line('rock & <roll>', 0, 1500)]),
      );
      final imported = LocalLyricFileImportService()
          .parseText(encoded, extension: 'vtt')
          .document;
      expect(imported.lines.single.text, 'rock & <roll>');
    });

    test('SRT and WebVTT round-trip through the importer', () {
      final importer = LocalLyricFileImportService();
      for (final format in [LyricExportFormat.srt, LyricExportFormat.vtt]) {
        final imported = importer
            .parseText(
              encoder.encode(song, format),
              extension: format.extension,
            )
            .document;
        expect(imported.lines.map((l) => l.text), [
          '第一句',
          '第二句',
          '第三句',
        ], reason: format.name);
        expect(imported.lines.map((l) => l.startTime.inMilliseconds), [
          1000,
          3500,
          10000,
        ], reason: format.name);
        expect(imported.lines.map((l) => l.endTime.inMilliseconds), [
          3000,
          5000,
          12000,
        ], reason: format.name);
      }
    });
  });

  group('plain text', () {
    test('starts paragraphs at long pauses', () {
      expect(encoder.encodePlainText(song), '第一句\n第二句\n\n第三句\n');
      expect(
        encoder.encodePlainText(song, paragraphsAtPauses: false),
        '第一句\n第二句\n第三句\n',
      );
    });
  });

  test('cues clamp negative times and keep rows sharing a start in order', () {
    final cues = encoder.cues(
      LyricDocument(
        language: 'zh',
        globalOffset: const Duration(milliseconds: -500),
        lines: [
          line('乙\n行', 2000, 3000),
          line('甲', 200, 1000),
          line('丙', 2000, 2500),
        ],
      ),
    );
    expect(cues.map((c) => c.text), ['甲', '乙 行', '丙']);
    expect(cues.first.start, Duration.zero);
    expect(cues.first.end, const Duration(milliseconds: 500));
  });

  test('formats carry their extension and timed flag', () {
    expect(LyricExportFormat.values.map((f) => f.extension), [
      'lrc',
      'lrc',
      'ass',
      'srt',
      'vtt',
      'txt',
    ]);
    expect(LyricExportFormat.plainText.timed, isFalse);
    expect(LyricExportFormat.srt.timed, isTrue);
    expect(
      LocalLyricFileExportService.normalizedFileName(' a/b:c ', 'srt'),
      'a_b_c.srt',
    );
    expect(
      LocalLyricFileExportService.normalizedFileName('song.SRT', 'srt'),
      'song.SRT',
    );
  });
}
