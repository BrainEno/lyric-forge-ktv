import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_export_encoder.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_karaoke_timing_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
LyricLine line(String text, int startMs, int endMs) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
);

List<(String, double)> units(String text) => [
  for (final unit in const LyricKaraokeTimingService().units(text))
    (unit.text, unit.weight),
];

List<(String, int, int)> syllables(String text, int startMs, int endMs) => [
  for (final syllable in const LyricKaraokeTimingService().syllables(
    text,
    Duration(milliseconds: startMs),
    Duration(milliseconds: endMs),
  ))
    (
      syllable.text,
      syllable.start.inMilliseconds,
      syllable.duration.inMilliseconds,
    ),
];

void main() {
  group('LyricKaraokeTimingService.units', () {
    test('Han characters are single units and punctuation rides along', () {
      expect(units('我爱你，'), [('我', 1.0), ('爱', 1.0), ('你，', 1.0)]);
      expect(units('「你好」'), [('「你', 1.0), ('好」', 1.0)]);
    });

    test('Latin words are weighted by their vowel groups', () {
      expect(units('Hello world'), [('Hello ', 2.0), ('world', 1.0)]);
      expect(units("don't stop"), [("don't ", 1.0), ('stop', 1.0)]);
      expect(units('beautiful love'), [('beautiful ', 3.0), ('love', 1.0)]);
    });

    test('digits weigh one unit each; text without sung units stays', () {
      expect(units('2026年'), [('2026', 4.0), ('年', 1.0)]);
      expect(units('...'), [('...', 0.0)]);
      expect(units(''), isEmpty);
    });
  });

  group('LyricKaraokeTimingService.syllables', () {
    test('spreads the row over its units by weight', () {
      expect(syllables('我爱你', 1000, 2500), [
        ('我', 1000, 500),
        ('爱', 1500, 500),
        ('你', 2000, 500),
      ]);
      expect(syllables('Hello world', 0, 3000), [
        ('Hello ', 0, 2000),
        ('world', 2000, 1000),
      ]);
    });

    test('rounding error is carried so the units add up exactly', () {
      final result = syllables('一二三', 0, 1000);
      expect(result.map((s) => s.$3), [330, 340, 330]);
      expect(result.fold<int>(0, (sum, s) => sum + s.$3), 1000);
      expect(result.last.$2 + result.last.$3, 1000);
    });

    test('a row without a usable end gets zero durations', () {
      expect(syllables('我爱', 2000, 2000), [('我', 2000, 0), ('爱', 2000, 0)]);
    });
  });

  group('karaoke export formats', () {
    const encoder = LyricExportEncoder();

    test('word-timed LRC keeps the line stamp and closes with the end', () {
      final text = encoder.encode(
        LyricDocument(language: 'zh', lines: [line('我爱你', 1000, 2500)]),
        LyricExportFormat.karaokeLrc,
      );
      expect(
        text,
        '[lang:zh]\n[re:Elysium Player]\n[ve:1]\n'
        '[00:01.000]<00:01.000>我<00:01.500>爱<00:02.000>你<00:02.500>\n',
      );
    });

    test('ASS rows sweep per unit with a lead-in bounded by the row above', () {
      final text = encoder.encode(
        LyricDocument(
          language: 'zh',
          lines: [line('我爱你', 2000, 3500), line('{a}\\b', 3600, 4000)],
        ),
        LyricExportFormat.ass,
        metadata: const LyricExportMetadata(title: '测试歌', artist: '歌手'),
      );
      expect(text, contains('Title: 测试歌 - 歌手\n'));
      expect(text, contains('[V4+ Styles]'));
      expect(text, contains('Style: Karaoke,'));
      expect(
        text,
        contains(
          'Dialogue: 0,0:00:01.00,0:00:03.50,Karaoke,,0,0,0,,'
          '{\\k100}{\\kf50}我{\\kf50}爱{\\kf50}你\n',
        ),
      );
      // The second row may not appear before the first has ended, and the
      // braces and backslash of its text cannot start override tags.
      expect(
        text,
        contains(
          'Dialogue: 0,0:00:03.50,0:00:04.00,Karaoke,,0,0,0,,'
          '{\\k10}{\\kf20}｛a｝＼{\\kf20}b\n',
        ),
      );
    });

    test('ASS lead-in can be turned off', () {
      final text = encoder.encode(
        LyricDocument(language: 'zh', lines: [line('我爱', 2000, 3000)]),
        LyricExportFormat.ass,
        options: const LyricExportOptions(assLeadIn: Duration.zero),
      );
      expect(
        text,
        contains(
          'Dialogue: 0,0:00:02.00,0:00:03.00,Karaoke,,0,0,0,,'
          '{\\kf50}我{\\kf50}爱\n',
        ),
      );
      expect(text, contains('Title: Elysium Player\n'));
    });

    test('ASS timestamps use h:mm:ss.cc', () {
      expect(
        LyricExportEncoder.assTimestamp(
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 456),
        ),
        '1:02:03.46',
      );
      expect(LyricExportEncoder.assTimestamp(Duration.zero), '0:00:00.00');
    });

    test('karaoke formats are syllable-timed and keep their extensions', () {
      expect(LyricExportFormat.karaokeLrc.syllableTimed, isTrue);
      expect(LyricExportFormat.ass.syllableTimed, isTrue);
      expect(LyricExportFormat.lrc.syllableTimed, isFalse);
      expect(LyricExportFormat.ass.extension, 'ass');
      expect(LyricExportFormat.karaokeLrc.extension, 'lrc');
    });
  });
}
