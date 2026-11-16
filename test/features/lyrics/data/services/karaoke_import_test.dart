import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_export_encoder.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_karaoke_tag_parser.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_word_timing_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
Duration ms(int value) => Duration(milliseconds: value);

List<(String, int, int)> wordsOf(LyricLine line) => [
  for (final word in line.words)
    (word.text, word.start.inMilliseconds, word.end.inMilliseconds),
];

void main() {
  const parser = LyricKaraokeTagParser();
  final importer = LocalLyricFileImportService();

  group('tag parser', () {
    test('enhanced LRC stamps time each piece and close the row', () {
      final tags = parser.lrc(
        '<00:01.00>我<00:01.40>爱<00:01.80>你，<00:02.50>',
        ms(1000),
      );
      expect(tags.text, '我爱你，');
      expect(tags.end, ms(2500));
      expect(wordsOf(_line(tags, 1000, 3000)), [
        ('我', 1000, 1400),
        ('爱', 1400, 1800),
        ('你，', 1800, 2500),
      ]);
    });

    test('inline square stamps and Latin words with spaces', () {
      final tags = parser.lrc(
        'Hold [00:05.50]me [00:06.00]tight[00:07.25]',
        ms(5000),
      );
      expect(tags.text, 'Hold me tight');
      expect(wordsOf(_line(tags, 5000, 8000)), [
        ('Hold', 5000, 5500),
        ('me', 5500, 6000),
        ('tight', 6000, 7250),
      ]);
    });

    test('a row without word stamps has no pieces', () {
      final tags = parser.lrc('  普通的一行 ', ms(0));
      expect(tags.text, '普通的一行');
      expect(tags.pieces, isEmpty);
      expect(parser.words(tags, rowEnd: ms(1000)), isEmpty);
    });

    test('stamps going backwards leave the row untimed', () {
      final tags = parser.lrc('<00:02.00>我<00:01.00>爱', ms(2000));
      expect(tags.text, '我爱');
      expect(parser.words(tags, rowEnd: ms(3000)), isEmpty);
    });

    test('ASS karaoke durations count from the event start', () {
      final tags = parser.ass(
        r'{\an8}{\k100}{\kf40}我{\K40}爱{\ko70}你，\N{\k30}啊',
        ms(10000),
      );
      expect(tags.text, '我爱你，\n啊');
      expect(parser.firstSungStart(tags), ms(11000));
      expect(wordsOf(_line(tags, 10000, 13000)), [
        ('我', 11000, 11400),
        ('爱', 11400, 11800),
        ('你，', 11800, 12500),
        ('啊', 12500, 12800),
      ]);
    });

    test('WebVTT cue timestamps start at the cue and strip markup', () {
      final tags = parser.vtt(
        '<c>Hold</c> <00:00:05.500><c>me</c> <00:00:06.000>&amp; go',
        ms(5000),
      );
      expect(tags.text, 'Hold me & go');
      expect(wordsOf(_line(tags, 5000, 7000)), [
        ('Hold', 5000, 5500),
        ('me', 5500, 6000),
        ('& go', 6000, 7000),
      ]);
    });

    test('timestamps parse in the formats the files use', () {
      expect(LyricKaraokeTagParser.lrcStamp('01:02.5'), ms(62500));
      expect(LyricKaraokeTagParser.lrcStamp('01:02:34'), ms(62340));
      expect(LyricKaraokeTagParser.lrcStamp('01:75.00'), isNull);
      expect(LyricKaraokeTagParser.clockStamp('01:00:02.345'), ms(3602345));
      expect(LyricKaraokeTagParser.clockStamp('00:02.345'), ms(2345));
      expect(LyricKaraokeTagParser.clockStamp('1:61:00.000'), isNull);
    });
  });

  group('import', () {
    test('word-timed LRC keeps the word timing and the closing stamp', () {
      final result = importer.parseText(
        '[ti:Test]\n'
        '[00:01.00]<00:01.00>我<00:01.40>爱<00:01.80>你<00:02.50>\n'
        '[00:04.00]<00:04.00>Hold <00:04.60>me<00:05.20>\n',
        extension: 'lrc',
      );
      final lines = result.document.lines;
      expect(lines.map((l) => l.text), ['我爱你', 'Hold me']);
      expect(lines.first.endTime, ms(2500));
      expect(wordsOf(lines.first).last, ('你', 1800, 2500));
      expect(wordsOf(lines[1]), [('Hold', 4000, 4600), ('me', 4600, 5200)]);
      expect(result.wordTimedRows, 2);
      expect(const LyricWordTimingService().isUsable(lines.first), isTrue);
    });

    test('a row listed under two stamps gets its words at both', () {
      final result = importer.parseText(
        '[00:01.00][00:11.00]<00:01.00>啦<00:01.50>啦<00:02.00>\n',
        extension: 'lrc',
      );
      final lines = result.document.lines;
      expect(wordsOf(lines.first), [('啦', 1000, 1500), ('啦', 1500, 2000)]);
      expect(wordsOf(lines[1]), [('啦', 11000, 11500), ('啦', 11500, 12000)]);
    });

    test('plain LRC is unchanged and has no word timing', () {
      final result = importer.parseText(
        '[00:01.00]第一行\n[00:03.00]第二行\n',
        extension: 'lrc',
      );
      expect(result.document.lines.map((l) => l.words.isEmpty), [true, true]);
      expect(result.document.lines.first.endTime, ms(3000));
      expect(result.wordTimedRows, 0);
    });

    test('ASS karaoke starts the row where the singing does', () {
      final result = importer.parseText(
        '[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        r'Dialogue: 0,0:00:01.00,0:00:03.00,Karaoke,,0,0,0,,{\k100}{\kf50}我{\kf50}爱',
        extension: 'ass',
      );
      final line = result.document.lines.single;
      expect(line.text, '我爱');
      expect(line.startTime, ms(2000));
      expect(wordsOf(line), [('我', 2000, 2500), ('爱', 2500, 3000)]);
    });

    test('WebVTT inline timestamps become word timing', () {
      final result = importer.parseText(
        'WEBVTT\n\n00:00:05.000 --> 00:00:07.000\nHold <00:00:05.500>me\n',
        extension: 'vtt',
      );
      final line = result.document.lines.single;
      expect(line.text, 'Hold me');
      expect(wordsOf(line), [('Hold', 5000, 5500), ('me', 5500, 7000)]);
    });

    test('karaoke LRC and ASS exports import back with the same timing', () {
      final source = LyricDocument(
        language: 'zh',
        lines: [
          LyricLine(
            text: '我爱你，',
            startTime: ms(3000),
            endTime: ms(4500),
            words: [
              LyricWordTiming(text: '我', start: ms(3000), end: ms(3300)),
              LyricWordTiming(text: '爱', start: ms(3300), end: ms(3900)),
              LyricWordTiming(text: '你，', start: ms(3900), end: ms(4500)),
            ],
          ),
          LyricLine(
            text: 'Hold me',
            startTime: ms(6000),
            endTime: ms(7000),
            words: [
              LyricWordTiming(text: 'Hold', start: ms(6000), end: ms(6400)),
              LyricWordTiming(text: 'me', start: ms(6400), end: ms(7000)),
            ],
          ),
        ],
      );
      const encoder = LyricExportEncoder();
      final expected = [for (final line in source.lines) _times(line)];
      final lrc = importer.parseText(
        encoder.encodeKaraokeLrc(source),
        extension: 'lrc',
      );
      expect([for (final line in lrc.document.lines) _times(line)], expected);
      final ass = importer.parseText(
        encoder.encodeAss(source),
        extension: 'ass',
      );
      expect([for (final line in ass.document.lines) _times(line)], expected);
      expect(ass.document.lines.map((l) => l.startTime), [ms(3000), ms(6000)]);
    });
  });
}

LyricLine _line(LyricKaraokeTags tags, int startMs, int endMs) => LyricLine(
  text: tags.text,
  startTime: ms(startMs),
  endTime: ms(endMs),
  words: const LyricKaraokeTagParser().words(tags, rowEnd: ms(endMs)),
);

List<(int, int)> _times(LyricLine line) => [
  for (final word in line.words)
    (word.start.inMilliseconds, word.end.inMilliseconds),
];
