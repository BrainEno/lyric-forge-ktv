import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_export_encoder.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_karaoke_timing_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_line_structure_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_word_timing_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
Duration ms(int value) => Duration(milliseconds: value);

LyricWordTiming word(String text, int startMs, int endMs) =>
    LyricWordTiming(text: text, start: ms(startMs), end: ms(endMs));

/// 我 1000–1400, 爱 1400–1800, 你 2000–3000.
LyricLine timedRow({String text = '我爱你', int start = 1000, int end = 3000}) =>
    LyricLine(
      text: text,
      startTime: ms(start),
      endTime: ms(end),
      id: 'row',
      words: [
        word('我', 1000, 1400),
        word('爱', 1400, 1800),
        word('你', 2000, 3000),
      ],
    );

List<int> starts(List<LyricCharacterTime>? times) => [
  for (final time in times!) time.start.inMilliseconds,
];

void main() {
  const service = LyricWordTimingService();

  group('LyricWordTiming JSON', () {
    test('round-trips through the document JSON and skips bad entries', () {
      final document = LyricDocument(language: 'zh', lines: [timedRow()]);
      final decoded = LyricDocument.fromJson(
        jsonDecode(jsonEncode(document.toJson())) as Map<String, dynamic>,
      );
      final words = decoded.lines.single.words;
      expect(words.map((w) => w.text), ['我', '爱', '你']);
      expect(words.last.start, ms(2000));
      expect(words.last.end, ms(3000));

      final json = timedRow().toJson()
        ..['words'] = [
          {'text': '我', 'start': 1000, 'end': 1400},
          {'text': 7, 'start': 1, 'end': 2},
          'nonsense',
        ];
      expect(LyricLine.fromJson(json).words.map((w) => w.text), ['我']);
    });

    test('rows without words omit the key', () {
      const plain = LyricLine(
        text: '我爱你',
        startTime: Duration.zero,
        endTime: Duration(seconds: 1),
      );
      expect(plain.toJson().containsKey('words'), isFalse);
      expect(LyricLine.fromJson(plain.toJson()).words, isEmpty);
    });
  });

  group('LyricWordTimingService.characterTimes', () {
    test('uses words inside the row as they are', () {
      expect(starts(service.characterTimes(timedRow())), [1000, 1400, 2000]);
    });

    test('divides a multi-character word evenly', () {
      final row = LyricLine(
        text: '我爱你',
        startTime: ms(0),
        endTime: ms(900),
        words: [word('我爱', 0, 600), word('你', 600, 900)],
      );
      expect(starts(service.characterTimes(row)), [0, 300, 600]);
    });

    test('follows a row that was moved or stretched', () {
      final moved = timedRow().copyWith(startTime: ms(11000), endTime: ms(13000));
      expect(starts(service.characterTimes(moved)), [11000, 11400, 12000]);

      final stretched = timedRow().copyWith(endTime: ms(5000));
      // Still inside the row, so the words stay where they were sung.
      expect(starts(service.characterTimes(stretched)), [1000, 1400, 2000]);

      final doubled = timedRow().copyWith(startTime: ms(2000), endTime: ms(6000));
      expect(starts(service.characterTimes(doubled)), [2000, 2800, 4000]);
    });

    test('survives punctuation and homophone fixes, not added characters', () {
      expect(service.isUsable(timedRow(text: '我爱你！')), isTrue);
      expect(service.isUsable(timedRow(text: '我碍你')), isTrue);
      expect(service.isUsable(timedRow(text: '我爱你们')), isFalse);
      expect(service.isUsable(timedRow(text: '爱你')), isFalse);
      expect(
        service.isUsable(
          const LyricLine(
            text: '我爱你',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
          ),
        ),
        isFalse,
      );
    });

    test('Latin words count their letters', () {
      final row = LyricLine(
        text: 'hold me',
        startTime: ms(0),
        endTime: ms(1000),
        words: [word('hold', 0, 600), word('me', 600, 1000)],
      );
      expect(service.characterTimes(row), hasLength(6));
      expect(service.characterStart(row, 4), ms(600));
    });
  });

  group('slice and normalized', () {
    test('slices keep the original word grouping on the row timeline', () {
      final moved = timedRow().copyWith(startTime: ms(11000), endTime: ms(13000));
      final tail = service.slice(moved, 1, 3);
      expect(tail.map((w) => w.text), ['爱', '你']);
      expect(tail.first.start, ms(11400));
      expect(service.normalized(moved).first.start, ms(11000));
    });

    test('a slice through a word keeps only its part', () {
      final row = LyricLine(
        text: '我爱你',
        startTime: ms(0),
        endTime: ms(900),
        words: [word('我爱你', 0, 900)],
      );
      final second = service.slice(row, 1, 3);
      expect(second.single.text, '爱你');
      expect(second.single.start, ms(300));
    });
  });

  group('structure edits carry word timing', () {
    const structure = LyricLineStructureService();

    test('split breaks at the first word of the second half', () {
      final row = timedRow(text: '我爱 你');
      final result = structure.split(row, textOffset: 2);
      final split = result.split!;
      expect(split.timingSource, LyricSplitTimingSource.wordTiming);
      expect(split.first.endTime, ms(2000));
      expect(split.second.startTime, ms(2000));
      expect(split.first.words.map((w) => w.text), ['我', '爱']);
      expect(split.second.words.map((w) => w.text), ['你']);
    });

    test('a paused playhead still wins over word timing', () {
      final result = structure.split(
        timedRow(text: '我爱 你'),
        textOffset: 2,
        playbackPosition: ms(1900),
      );
      expect(result.split!.timingSource, LyricSplitTimingSource.playback);
    });

    test('merge joins the words of both rows', () {
      final split = structure.split(timedRow(text: '我爱 你'), textOffset: 2);
      final merged = structure.merge(split.split!.first, split.split!.second);
      expect(merged.words.map((w) => w.text), ['我', '爱', '你']);
      expect(service.isUsable(merged), isTrue);

      final plain = merged.copyWith(words: const []);
      expect(structure.merge(plain, split.split!.second).words, isEmpty);
    });
  });

  group('karaoke export', () {
    test('syllables start where their characters were sung', () {
      final syllables = const LyricKaraokeTimingService().syllables(
        '我爱你',
        ms(1000),
        ms(3000),
        characterStarts: [ms(1000), ms(1400), ms(2000)],
      );
      expect(
        [
          for (final s in syllables)
            (s.text, s.start.inMilliseconds, s.duration.inMilliseconds),
        ],
        [('我', 1000, 400), ('爱', 1400, 600), ('你', 2000, 1000)],
      );
    });

    test('mismatched character times fall back to the estimate', () {
      final syllables = const LyricKaraokeTimingService().syllables(
        '我爱你',
        ms(0),
        ms(1500),
        characterStarts: [ms(0)],
      );
      expect([for (final s in syllables) s.start.inMilliseconds], [0, 500, 1000]);
    });

    test('a Latin word starts at its first letter', () {
      final syllables = const LyricKaraokeTimingService().syllables(
        'hold me',
        ms(0),
        ms(1000),
        characterStarts: [
          ms(0),
          ms(100),
          ms(200),
          ms(300),
          ms(700),
          ms(850),
        ],
      );
      expect(
        [for (final s in syllables) (s.text, s.start.inMilliseconds)],
        [('hold ', 0), ('me', 700)],
      );
    });

    test('word-timed LRC and ASS use the real times with the offset', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [timedRow()],
        globalOffset: ms(500),
      );
      const encoder = LyricExportEncoder();
      final lrc = encoder.encodeKaraokeLrc(document);
      expect(
        lrc,
        contains('[00:01.500]<00:01.500>我<00:01.900>爱<00:02.500>你<00:03.500>'),
      );
      final ass = encoder.encodeAss(document, leadIn: Duration.zero);
      expect(ass, contains('{\\kf40}我{\\kf60}爱{\\kf100}你'));
    });

    test('rows without word timing are still estimated', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [timedRow().copyWith(words: const [])],
      );
      expect(
        const LyricExportEncoder().encodeKaraokeLrc(document),
        contains('<00:01.000>我<00:01.670>爱<00:02.330>你'),
      );
    });
  });
}
