import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_indexed_review_metadata.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_missed_repeat_detector.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(
  String text,
  int startMs,
  int endMs, {
  String? id,
  List<LyricWordTiming> words = const [],
}) => LyricLine(
  text: text,
  startTime: _ms(startMs),
  endTime: _ms(endMs),
  id: id,
  words: words,
);

LyricWordTiming _w(String text, int startMs, int endMs) =>
    LyricWordTiming(text: text, start: _ms(startMs), end: _ms(endMs));

LyricDocument _doc(
  List<LyricLine> lines, {
  Map<String, dynamic> metadata = const {},
}) => LyricDocument(language: 'en', lines: lines, metadata: metadata);

void main() {
  const detector = LyricMissedRepeatDetector();

  group('chantReason', () {
    test('recognises vocables, back-to-back phrases and refrains', () {
      expect(detector.chantReason('whoa oh oh oh', 1), LyricChantReason.vocables);
      expect(detector.chantReason('Ooooh, yeahhh', 1), LyricChantReason.vocables);
      expect(detector.chantReason('la-la-la-la', 1), LyricChantReason.vocables);
      expect(detector.chantReason('lalala', 1), LyricChantReason.vocables);
      expect(detector.chantReason('啦啦啦啦', 1), LyricChantReason.vocables);
      expect(detector.chantReason('whoa', 1), LyricChantReason.vocables);
      expect(
        detector.chantReason('find the fire find the fire', 1),
        LyricChantReason.selfRepeat,
      );
      expect(detector.chantReason('hold me now', 3), LyricChantReason.refrain);
    });

    test('ordinary lines are not chants', () {
      expect(detector.chantReason('I walk the empty street', 1), isNull);
      expect(detector.chantReason('hold me now', 2), isNull);
      expect(detector.chantReason('my day is done', 1), isNull);
      expect(detector.chantReason('', 5), isNull);
      // Too long to be a refrain even when repeated.
      expect(
        detector.chantReason(
          'one two three four five six seven eight nine ten eleven',
          4,
        ),
        isNull,
      );
    });

    test('isVocable collapses held letters but keeps real words out', () {
      for (final token in ['oh', 'ooh', 'whoa', 'woah', 'yeah', 'nanana']) {
        expect(LyricMissedRepeatDetector.isVocable(token), isTrue, reason: token);
      }
      for (final token in ['no', 'a', 'my', 'day', 'do', 'hello', 'mama']) {
        expect(
          LyricMissedRepeatDetector.isVocable(token),
          isFalse,
          reason: token,
        );
      }
    });
  });

  group('gap after a chant', () {
    final ending = _doc([
      _line('I walk the empty street', 10000, 14000, id: 'a'),
      _line('and I keep the light', 15000, 19000, id: 'b'),
      _line('whoa oh oh oh', 80000, 83000, id: 'c'),
    ]);

    test('a chant before a silent ending is reported with the audio', () {
      final plan = detector.plan(ending, audioDuration: _ms(120000));
      final issue = plan.issues.single;
      expect(issue.kind, LyricMissedRepeatKind.gapAfterChant);
      expect(issue.index, 2);
      expect(issue.reason, LyricChantReason.vocables);
      expect(issue.toAudioEnd, isTrue);
      expect(issue.spanStart, _ms(83000));
      expect(issue.spanEnd, _ms(120000));
      // Copies every 4 s (3 s row + the song's 1 s pause), capped at 8.
      expect(issue.fill, hasLength(8));
      expect(issue.fill.first.startTime, _ms(84000));
      expect(issue.fill.first.endTime, _ms(87000));
      expect(issue.fill.first.text, 'whoa oh oh oh');
      expect(issue.fill.first.confidenceSource, LyricConfidenceSource.unscored);
      expect(issue.fixable, isTrue);
      // Filling needs listening first.
      expect(plan.defaultPositions, isEmpty);
      expect(plan.fixablePositions, [0]);
    });

    test('without the audio length the last row is not judged', () {
      expect(detector.plan(ending).issues, isEmpty);
      expect(detector.spotCount(ending), 0);
    });

    test('mid-song, only a chant that resumes after the gap counts', () {
      final plan = detector.plan(
        _doc([
          _line('first verse line', 0, 3000),
          _line('na na na na', 4000, 6000),
          _line('na na na na', 16000, 18000),
          _line('second verse line', 19000, 22000),
          _line('third verse line', 23000, 26000),
          // A mid-song chant before an instrumental break: not reported.
          _line('oh oh oh oh', 27000, 29000),
          _line('last line here', 60000, 63000),
        ]),
      );
      final issue = plan.issues.single;
      expect(issue.index, 1);
      expect(issue.resumes, isTrue);
      expect(issue.toAudioEnd, isFalse);
      expect(issue.spanEnd, _ms(16000));
      expect(issue.fill.map((line) => line.startTime), [
        _ms(7000),
        _ms(10000),
        _ms(13000),
      ]);
    });

    test('copies follow the spacing of an already repeated chant', () {
      final plan = detector.plan(
        _doc([
          _line('verse words go here', 0, 3000),
          _line('hey hey hey', 60000, 61000),
          _line('hey hey hey', 62500, 63500),
        ]),
        audioDuration: _ms(75000),
      );
      final issue = plan.issues.single;
      expect(issue.index, 2);
      expect(issue.fill.first.startTime, _ms(65000));
      expect(issue.fill[1].startTime, _ms(67500));
    });

    test('a refrain counts only near the end of the song', () {
      final plan = detector.plan(
        _doc([
          _line('hold me now', 0, 2000),
          _line('I was alone', 3000, 5000),
          _line('hold me now', 6000, 8000),
          _line('you were gone', 20000, 22000),
          _line('hold me now', 60000, 62000),
        ]),
        audioDuration: _ms(100000),
      );
      final issue = plan.issues.single;
      expect(issue.index, 4);
      expect(issue.reason, LyricChantReason.refrain);
    });

    test('a short gap or an ordinary line is not reported', () {
      final plan = detector.plan(
        _doc([
          _line('verse words go here', 0, 3000),
          _line('whoa oh oh', 60000, 62000),
          _line('and then we sang', 64000, 66000),
          _line('the end of it all', 80000, 82000),
        ]),
        audioDuration: _ms(110000),
      );
      expect(plan.issues, isEmpty);
    });
  });

  group('word timing', () {
    test('five or more words at one instant are crowded, fewer are not', () {
      final plan = detector.plan(
        _doc([
          _line(
            'whoa I am paddling on',
            1000,
            5000,
            words: [
              for (final word in ['whoa', 'I', 'am', 'paddling'])
                _w(word, 1000, 1000),
              _w('on', 1000, 5000),
            ],
          ),
          _line(
            'we go on',
            6000,
            8000,
            words: [_w('we', 6000, 6000), _w('go', 6000, 6000), _w('on', 6000, 8000)],
          ),
        ]),
      );
      final issue = plan.issues.single;
      expect(issue.kind, LyricMissedRepeatKind.crowdedWords);
      expect(issue.index, 0);
      expect(issue.crowdedCount, 5);
      expect(issue.crowdedAt, _ms(1000));
      expect(issue.crowdedAtStart, isTrue);
      expect(plan.defaultPositions, [0]);
    });

    test('crowdedRun finds the longest run', () {
      expect(detector.crowdedRun(const []), isNull);
      final run = detector.crowdedRun([
        _w('a', 0, 100),
        for (var i = 0; i < 6; i++) _w('b$i', 500 + i * 5, 500 + i * 5),
        _w('c', 900, 1000),
      ]);
      expect(run, (start: 1, count: 6));
    });

    final stretched = _doc([
      _line(
        'the night is young',
        0,
        26000,
        id: 'a',
        words: [
          _w('the', 0, 25600),
          _w('night', 25600, 25800),
          _w('is', 25800, 25900),
          _w('young', 25900, 26000),
        ],
      ),
      _line(
        'I have waited',
        30000,
        38000,
        id: 'b',
        words: [
          _w('I', 30000, 30200),
          _w('have', 30200, 30400),
          _w('waited', 30400, 38000),
        ],
      ),
      _line(
        'oh find the fire',
        40000,
        49300,
        id: 'c',
        words: [
          _w('oh', 40000, 40100),
          _w('find', 40100, 40300),
          _w('the', 40300, 49000),
          _w('fire', 49000, 49300),
        ],
      ),
    ]);

    test('a stretched word is reported by where it sits', () {
      final plan = detector.plan(stretched);
      expect(plan.issues.map((issue) => issue.kind), [
        LyricMissedRepeatKind.stretchedWord,
        LyricMissedRepeatKind.stretchedWord,
        LyricMissedRepeatKind.stretchedWord,
      ]);
      final [first, last, middle] = plan.issues;
      expect(first.position, LyricStretchedWordPosition.first);
      expect(first.wordText, 'the');
      expect(first.proposedStart, _ms(24800));
      expect(first.spanStart, Duration.zero);
      expect(first.spanEnd, _ms(25600));
      expect(last.position, LyricStretchedWordPosition.last);
      expect(last.proposedEnd, _ms(31200));
      expect(middle.position, LyricStretchedWordPosition.middle);
      expect(middle.fixable, isFalse);
      expect(middle.spanStart, _ms(40300));
      expect(middle.spanEnd, _ms(49000));
      // Only the stretched first word is trimmed by default: a long last
      // word may be a held note.
      expect(plan.defaultPositions, [0]);
      expect(plan.fixablePositions, [0, 1]);
    });

    test('trimming moves the row edge together with the word', () {
      final plan = detector.plan(stretched);
      final applied = plan.applyTo(stretched, {0, 1});
      final first = applied.lines[0];
      expect(first.startTime, _ms(24800));
      expect(first.endTime, _ms(26000));
      expect(first.words.first.start, _ms(24800));
      expect(first.words.first.end, _ms(25600));
      expect(first.id, 'a');
      final second = applied.lines[1];
      expect(second.startTime, _ms(30000));
      expect(second.endTime, _ms(31200));
      expect(second.words.last.end, _ms(31200));
      expect(applied.lines[2], same(stretched.lines[2]));
      expect(plan.countFor({0, 1}), (cleared: 0, retimed: 2, inserted: 0));
    });

    test('hand-edited rows and word times from before a move are left alone', () {
      final protectedPlan = detector.plan(stretched, protectedIndices: {0});
      expect(protectedPlan.issues.first.protected, isTrue);
      expect(protectedPlan.issues.first.fixable, isFalse);
      expect(protectedPlan.defaultPositions, isEmpty);

      final moved = _doc([
        _line(
          'the night is young',
          60000,
          86000,
          words: [_w('the', 0, 25600), _w('night', 25600, 26000)],
        ),
      ]);
      expect(detector.plan(moved).issues, isEmpty);
    });
  });

  group('applyTo', () {
    LyricDocument ending() => _doc(
      [
        _line('I walk the empty street', 10000, 14000, id: 'a'),
        _line('and I keep the light', 15000, 19000, id: 'b'),
        _line('whoa oh oh oh', 80000, 83000, id: 'c'),
        _line('whoa oh oh oh', 84000, 87000, id: 'd'),
        _line('goodbye now', 110000, 112000, id: 'e'),
      ],
      metadata: {
        LyricIndexedReviewMetadata.secondaryOnlyIndicesKey: [1, 4],
      },
    );

    test('inserts the chosen number of copies with fresh ids', () {
      final document = ending();
      final plan = detector.plan(document, audioDuration: _ms(120000));
      final position = plan.issues.indexWhere(
        (issue) => issue.kind == LyricMissedRepeatKind.gapAfterChant,
      );
      final issue = plan.issues[position];
      expect(issue.index, 3);
      expect(issue.fill.length, greaterThan(2));

      final applied = plan.applyTo(
        document,
        {position},
        fillCounts: {position: 2},
      );
      expect(applied.lines, hasLength(7));
      expect(applied.lines.map((line) => line.text).toList(), [
        'I walk the empty street',
        'and I keep the light',
        'whoa oh oh oh',
        'whoa oh oh oh',
        'whoa oh oh oh',
        'whoa oh oh oh',
        'goodbye now',
      ]);
      expect(applied.lines[4].startTime, _ms(88000));
      expect(applied.lines[5].startTime, _ms(92000));
      final ids = applied.lines.map((line) => line.id).toList();
      expect(ids.take(4), ['a', 'b', 'c', 'd']);
      expect(ids.last, 'e');
      expect(ids.toSet(), hasLength(7));
      expect(ids.every((id) => id != null), isTrue);
      // Row-indexed review data follows its rows.
      expect(
        applied.metadata[LyricIndexedReviewMetadata.secondaryOnlyIndicesKey],
        [1, 6],
      );
      expect(plan.selectionAfterApply({position}), 3);
      expect(
        plan.countFor({position}, fillCounts: {position: 2}),
        (cleared: 0, retimed: 0, inserted: 2),
      );
    });

    test('a fill count of zero or nothing selected changes nothing', () {
      final document = ending();
      final plan = detector.plan(document, audioDuration: _ms(120000));
      expect(plan.applyTo(document, const {}), same(document));
      expect(
        plan.applyTo(document, {0}, fillCounts: {0: 0}),
        same(document),
      );
      expect(plan.fillCountFor(0, {0: 99}), plan.issues[0].fill.length);
      expect(plan.fillCountFor(0, {0: -3}), 0);
    });

    test('crowded word timing is cleared, the text stays', () {
      final document = _doc([
        _line(
          'la la la la la',
          1000,
          4000,
          id: 'x',
          words: [
            for (var i = 0; i < 4; i++) _w('la', 1000, 1000),
            _w('la', 1000, 4000),
          ],
        ),
      ]);
      final plan = detector.plan(document);
      final applied = plan.applyTo(document, plan.defaultPositions.toSet());
      expect(applied.lines.single.words, isEmpty);
      expect(applied.lines.single.text, 'la la la la la');
      expect(applied.lines.single.id, 'x');
    });
  });

  test('draft health counts what the check would find without audio', () {
    final document = _doc([
      _line(
        'the night is young',
        0,
        26000,
        words: [
          _w('the', 0, 25600),
          _w('night', 25600, 25800),
          _w('is', 25800, 25900),
          _w('young', 25900, 26000),
        ],
      ),
    ]);
    final health = const LyricDraftHealthService().analyze(document);
    expect(health.missedRepeatSpots, 1);
    expect(health.hasIssues, isTrue);
  });

  test('typicalPause is the median short gap, clamped', () {
    expect(detector.typicalPause(_doc(const [])), _ms(400));
    expect(
      detector.typicalPause(
        _doc([
          _line('a b', 0, 1000),
          _line('c d', 1050, 2000),
          _line('e f', 2600, 3000),
          _line('g h', 3700, 4000),
          _line('i j', 9000, 10000),
        ]),
      ),
      _ms(600),
    );
  });
}
