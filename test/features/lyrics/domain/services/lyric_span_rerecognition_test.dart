import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_span_rerecognition.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

Duration ms(int value) => Duration(milliseconds: value);

LyricLine row(
  String text,
  int start,
  int end, {
  String? id,
  bool chorus = false,
  List<LyricWordTiming> words = const [],
}) => LyricLine(
  text: text,
  startTime: ms(start),
  endTime: ms(end),
  id: id,
  isChorus: chorus,
  words: words,
);

LyricDocument doc(List<LyricLine> lines, {Duration? offset}) =>
    LyricDocument(language: 'en', lines: lines, globalOffset: offset);

void main() {
  const planner = LyricSpanRerecognitionPlanner();

  final song = doc([
    row('first line', 10000, 13000, id: 'a'),
    row('garbled garbled garbled', 14000, 18000, id: 'b'),
    row('third line', 22000, 25000, id: 'c'),
    row('last line', 26000, 29000, id: 'd'),
  ]);

  group('window', () {
    test('pads the chosen rows but never reaches into a neighbour', () {
      final result = planner.window(
        song,
        first: 1,
        last: 1,
        lead: LyricSpanReach.two,
        tail: LyricSpanReach.two,
      );
      expect(result.failure, isNull);
      // 2 s before row 2 would be 12.0 s, inside row 1 (ends 13.0 s).
      expect(result.window!.start, ms(13000));
      expect(result.window!.end, ms(20000));
      expect(result.window!.rowCount, 1);
    });

    test('reaching to the neighbour covers the whole gap', () {
      final result = planner.window(
        song,
        first: 1,
        last: 1,
        lead: LyricSpanReach.neighbour,
        tail: LyricSpanReach.neighbour,
      );
      expect(result.window!.start, ms(13000));
      expect(result.window!.end, ms(22000));
    });

    test('the last row reaches to the end of the audio', () {
      final result = planner.window(
        song,
        first: 3,
        last: 3,
        lead: LyricSpanReach.none,
        tail: LyricSpanReach.neighbour,
        audioDuration: ms(40000),
      );
      expect(result.window!.start, ms(26000));
      expect(result.window!.end, ms(40000));
    });

    test('padding stops at the audio edges', () {
      final result = planner.window(
        doc([row('only', 300, 2000)]),
        first: 0,
        last: 0,
        lead: LyricSpanReach.two,
        tail: LyricSpanReach.two,
        audioDuration: ms(3000),
      );
      expect(result.window!.start, Duration.zero);
      expect(result.window!.end, ms(3000));
    });

    test('overlapping neighbours keep the chosen rows whole', () {
      final overlapping = doc([
        row('one', 0, 5000),
        row('two', 4000, 8000),
        row('three', 7000, 10000),
      ]);
      final result = planner.window(
        overlapping,
        first: 1,
        last: 1,
        lead: LyricSpanReach.one,
        tail: LyricSpanReach.one,
      );
      expect(result.window!.start, ms(4000));
      expect(result.window!.end, ms(8000));
    });

    test('rejects invalid, too short and too long stretches', () {
      expect(
        planner.window(song, first: 2, last: 1).failure,
        LyricSpanWindowFailure.invalidRange,
      );
      expect(
        planner.window(song, first: 0, last: 9).failure,
        LyricSpanWindowFailure.invalidRange,
      );
      expect(
        planner
            .window(
              doc([row('a', 1000, 1200)]),
              first: 0,
              last: 0,
              lead: LyricSpanReach.none,
              tail: LyricSpanReach.none,
            )
            .failure,
        LyricSpanWindowFailure.tooShort,
      );
      expect(
        planner
            .window(
              doc([row('a', 0, 50000), row('b', 50000, 100000)]),
              first: 0,
              last: 1,
            )
            .failure,
        LyricSpanWindowFailure.tooLong,
      );
    });

    test('maps onto the audio timeline with the global offset', () {
      const window = LyricSpanWindow(
        first: 0,
        last: 0,
        start: Duration(seconds: 1),
        end: Duration(seconds: 4),
      );
      final audio = window.onAudio(const Duration(milliseconds: 500));
      expect(audio.start, ms(1500));
      expect(audio.end, ms(4500));
      expect(window.onAudio(const Duration(seconds: -2)).start, Duration.zero);
    });
  });

  group('replacement', () {
    final window = planner
        .window(
          song,
          first: 1,
          last: 1,
          lead: LyricSpanReach.neighbour,
          tail: LyricSpanReach.neighbour,
        )
        .window!;

    test('replaces the chosen rows with clipped, ordered new rows', () {
      final plan = planner.replacement(
        song,
        window: window,
        recognized: [
          row('the real second line', 14100, 17800),
          row('a chant they skipped', 18200, 21500),
          // Mostly outside the window: clipped to a 100 ms fragment.
          row('third', 21900, 25000),
        ],
      );
      expect(plan.newLines.map((line) => line.text), [
        'the real second line',
        'a chant they skipped',
      ]);
      expect(plan.clippedCount, 1);
      expect(plan.canReplaceTextOnly, isFalse);
      expect(plan.changesText, isTrue);

      final applied = plan.applyTo(song);
      expect(applied.lines.map((line) => line.text), [
        'first line',
        'the real second line',
        'a chant they skipped',
        'third line',
        'last line',
      ]);
      // Untouched rows keep their ids; new rows get fresh ones.
      expect(applied.lines.first.id, 'a');
      expect(applied.lines[3].id, 'c');
      expect(applied.lines[1].id, isNotNull);
      expect(applied.lines[1].id, isNot('b'));
    });

    test('clips rows and words to the window and removes overlaps', () {
      final plan = planner.replacement(
        song,
        window: window,
        recognized: [
          row(
            'early start',
            12000,
            16000,
            words: [
              LyricWordTiming(text: 'early', start: ms(12000), end: ms(14500)),
              LyricWordTiming(text: 'start', start: ms(14500), end: ms(16000)),
            ],
          ),
          row('overlap', 15500, 19000),
        ],
      );
      expect(plan.newLines.first.startTime, ms(13000));
      expect(plan.newLines.first.words.first.start, ms(13000));
      expect(plan.newLines[1].startTime, ms(16000));
      expect(plan.newLines[1].endTime, ms(19000));
    });

    test('drops word timing that lost words to the clip', () {
      final plan = planner.replacement(
        song,
        window: window,
        recognized: [
          row(
            'cut word',
            12000,
            16000,
            words: [
              LyricWordTiming(text: 'cut', start: ms(12000), end: ms(12900)),
              LyricWordTiming(text: 'word', start: ms(13500), end: ms(16000)),
            ],
          ),
        ],
      );
      expect(plan.newLines.single.words, isEmpty);
    });

    test('new rows stay chorus rows when every chosen row was one', () {
      final chorusSong = doc([
        row('la la', 0, 2000, chorus: true),
        row('la la la', 2000, 4000, chorus: true),
      ]);
      final chorusWindow = planner
          .window(chorusSong, first: 0, last: 1)
          .window!;
      final plan = planner.replacement(
        chorusSong,
        window: chorusWindow,
        recognized: [row('la la la la', 100, 3900)],
      );
      expect(plan.newLines.single.isChorus, isTrue);
    });

    test('text-only keeps timing and ids, and drops stale word timing', () {
      final words = [
        LyricWordTiming(text: 'first', start: ms(10000), end: ms(11000)),
        LyricWordTiming(text: 'line', start: ms(11000), end: ms(13000)),
      ];
      final twoRows = doc([
        row('first line', 10000, 13000, id: 'a', words: words),
        row('secnd lien', 14000, 18000, id: 'b', words: words),
      ]);
      final twoWindow = planner.window(twoRows, first: 0, last: 1).window!;
      final plan = planner.replacement(
        twoRows,
        window: twoWindow,
        recognized: [
          row('first line', 9800, 12500),
          row('second line', 14200, 17000),
        ],
      );
      expect(plan.canReplaceTextOnly, isTrue);
      final applied = plan.applyTo(twoRows, textOnly: true);
      expect(applied.lines[0].text, 'first line');
      expect(applied.lines[0].words, words);
      expect(applied.lines[1].text, 'second line');
      expect(applied.lines[1].startTime, ms(14000));
      expect(applied.lines[1].endTime, ms(18000));
      expect(applied.lines[1].id, 'b');
      expect(applied.lines[1].words, isEmpty);
    });

    test('counts protected rows and reports an empty result', () {
      final plan = planner.replacement(
        song,
        window: window,
        recognized: [row('  ', 14000, 15000)],
        protectedIndices: {1, 3},
      );
      expect(plan.protectedCount, 1);
      expect(plan.isEmpty, isTrue);
      expect(plan.applyTo(song), same(song));
    });

    test('similarity ignores case, spaces and punctuation', () {
      expect(
        LyricSpanRerecognitionPlanner.similarity(
          'Hello, World!',
          'hello world',
        ),
        1,
      );
      expect(LyricSpanRerecognitionPlanner.similarity('abcd', 'abcf'), 0.75);
      expect(LyricSpanRerecognitionPlanner.similarity('', 'abc'), 0);
      expect(LyricSpanRerecognitionPlanner.similarity('', ''), 1);
      expect(LyricSpanRerecognitionPlanner.similarity('我们', '我门'), 0.5);
    });
  });

  group('realignment', () {
    final edited = doc([
      row('before', 0, 2000, id: 'x'),
      row('Hello, world', 3000, 6000, id: 'y'),
      row('♪', 6000, 7000, id: 'z'),
      row('good night', 7000, 10000, id: 'w'),
      row('after', 12000, 14000),
    ]);
    final window = planner
        .window(
          edited,
          first: 1,
          last: 3,
          lead: LyricSpanReach.neighbour,
          tail: LyricSpanReach.neighbour,
        )
        .window!;

    test('sends only rows with sung text to the aligner', () {
      expect(planner.alignmentText(edited, window), 'Hello, world\ngood night');
    });

    test('re-times rows and words, keeping the text', () {
      final plan = planner.realignment(
        edited,
        window: window,
        spans: [
          ForcedAlignedSpan(text: 'hello', start: ms(3200), end: ms(3800)),
          ForcedAlignedSpan(text: 'world', start: ms(3900), end: ms(5100)),
          ForcedAlignedSpan(text: 'good', start: ms(7400), end: ms(8000)),
          ForcedAlignedSpan(text: 'night', start: ms(8100), end: ms(9500)),
        ],
      );
      expect(plan.isReady, isTrue);
      expect(plan.rows.map((row) => row.index), [1, 3]);
      final applied = plan.applyTo(edited);
      expect(applied.lines[1].text, 'Hello, world');
      expect(applied.lines[1].startTime, ms(3200));
      expect(applied.lines[1].endTime, ms(5100));
      expect(applied.lines[1].words.map((word) => word.text), [
        'hello',
        'world',
      ]);
      expect(applied.lines[1].id, 'y');
      // The row without sung text is left alone.
      expect(applied.lines[2].startTime, ms(6000));
      expect(applied.lines[3].startTime, ms(7400));
      expect(applied.lines[3].endTime, ms(9500));
      expect(plan.changedCount(edited), 2);
    });

    test('a merged word running across a row end times both rows', () {
      final plan = planner.realignment(
        edited,
        window: window,
        spans: [
          ForcedAlignedSpan(text: 'hello', start: ms(3200), end: ms(3800)),
          ForcedAlignedSpan(text: 'world good', start: ms(3900), end: ms(7600)),
          ForcedAlignedSpan(text: 'night', start: ms(8100), end: ms(9500)),
        ],
      );
      expect(plan.isReady, isTrue);
      expect(plan.rows.first.words.last.text, 'world');
      expect(plan.rows.last.words.first.text, 'good');
      expect(plan.rows.last.start, ms(7600));
    });

    test('fails closed on a mismatch or an incomplete alignment', () {
      final mismatch = planner.realignment(
        edited,
        window: window,
        spans: [
          ForcedAlignedSpan(text: 'hello', start: ms(3200), end: ms(3800)),
          ForcedAlignedSpan(text: 'word', start: ms(3900), end: ms(5100)),
        ],
      );
      expect(mismatch.status, LyricSpanRealignmentStatus.textMismatch);
      expect(mismatch.failedIndex, 1);
      expect(mismatch.applyTo(edited), same(edited));

      final incomplete = planner.realignment(
        edited,
        window: window,
        spans: [
          ForcedAlignedSpan(text: 'hello', start: ms(3200), end: ms(3800)),
          ForcedAlignedSpan(text: 'world', start: ms(3900), end: ms(5100)),
        ],
      );
      expect(incomplete.status, LyricSpanRealignmentStatus.incomplete);
      expect(incomplete.failedIndex, 3);

      final extra = planner.realignment(
        edited,
        window: window,
        spans: [
          ForcedAlignedSpan(
            text: 'hello world',
            start: ms(3200),
            end: ms(5000),
          ),
          ForcedAlignedSpan(text: 'good night', start: ms(7000), end: ms(9000)),
          ForcedAlignedSpan(text: 'again', start: ms(9100), end: ms(9500)),
        ],
      );
      expect(extra.status, LyricSpanRealignmentStatus.textMismatch);

      expect(
        planner.realignment(edited, window: window, spans: const []).status,
        LyricSpanRealignmentStatus.noSpans,
      );
    });

    test('rows without sung text cannot be aligned', () {
      final silent = doc([row('♪ ♪', 0, 3000)]);
      final silentWindow = planner.window(silent, first: 0, last: 0).window!;
      expect(planner.alignmentText(silent, silentWindow), isEmpty);
      expect(
        planner
            .realignment(
              silent,
              window: silentWindow,
              spans: [ForcedAlignedSpan(text: 'x', start: ms(10), end: ms(20))],
            )
            .status,
        LyricSpanRealignmentStatus.nothingToAlign,
      );
    });
  });
}
