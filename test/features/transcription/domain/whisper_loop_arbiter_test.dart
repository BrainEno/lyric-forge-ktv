import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_segment_loop_detector.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/whisper_loop_arbiter.dart';

import 'whisper_loop_fixtures.dart';

void main() {
  const arbiter = WhisperLoopArbiter();

  test('leaves loop-free output untouched', () {
    final lines = [
      loopLine('city lights are calling', 0, 3000),
      loopLine('every window burning gold', 3000, 6000),
    ];
    final result = arbiter.arbitrate(primary: lines, secondary: lines);
    expect(identical(result.lines, lines), isTrue);
    expect(result.decisions, isEmpty);
    expect(result.changed, isFalse);
    expect(result.sourceIndices, [0, 1]);
  });

  group('with a second engine', () {
    test('replaces a disproved loop with the second engine\'s rows', () {
      final whisper = whisperLoopedSong();
      final qwen = qwenOverLoopedSong();
      final result = arbiter.arbitrate(primary: whisper, secondary: qwen);

      final decision = result.decisions.single;
      expect(decision.verdict, WhisperLoopVerdict.replacedBySecondary);
      expect(decision.reason, 'whisper_cross_segment_loop_replaced_by_qwen');
      expect(decision.secondaryIndices, [4, 5, 6, 7, 8]);
      expect(decision.secondaryRowsInSpan, 5);
      expect(decision.secondaryLoops, isFalse);
      expect(result.changed, isTrue);

      expect(result.lines.map((line) => line.text), [
        'Wake me up when the city is quiet',
        'Carry me home on a paper balloon',
        'Now the river is wide and the morning is near',
        'Tell me again why the road never ends',
        'How far is the harbour, is it under the water?',
        'I hope we arrive in time',
        'Now you never look back on the way',
        'Oh, and the lanterns that you hold, we never mean to fold',
        'Oh, but the people you know, they say what they want to',
        'What they say, oh, the truth is we never care',
        'And that is quite enough of that',
      ]);
      expect(result.sourceIndices, [
        0,
        1,
        2,
        3,
        null,
        null,
        null,
        null,
        null,
        32,
        33,
      ]);

      // Every inserted row is queued with the looped text it replaced.
      expect(result.reviewRows.map((row) => row.lineIndex), [4, 5, 6, 7, 8]);
      for (final row in result.reviewRows) {
        expect(row.fromSecondary, isTrue);
        expect(row.loopedText, '$loopChant / $loopVerse');
        final line = result.lines[row.lineIndex];
        expect(line.confidenceSource, LyricConfidenceSource.heuristic);
        expect(
          line.confidence,
          lessThanOrEqualTo(WhisperLoopArbiter.reviewConfidenceCeiling),
        );
      }

      final metadata = result.toMetadata().single;
      expect(metadata['verdict'], 'replacedBySecondary');
      expect(metadata['repeats'], 11);
      expect(metadata['secondaryIndices'], [4, 5, 6, 7, 8]);
    });

    test('keeps a repetition the second engine hears too', () {
      final whisper = [
        loopLine('verse line one', 0, 4000),
        for (var i = 0; i < 6; i++)
          loopLine('we will rise again', 4000 + i * 2500, 6500 + i * 2500),
        loopLine('outro line', 19000, 23000),
      ];
      final qwen = [
        loopLine('verse line one', 0, 4000),
        loopLine('We will rise again, we will rise again.', 4000, 9000),
        loopLine('We will rise again, we will rise again,', 9000, 14000),
        loopLine('we will rise again, we will rise again', 14000, 19000),
        loopLine('outro line', 19000, 23000),
      ];
      final result = arbiter.arbitrate(primary: whisper, secondary: qwen);
      expect(result.decisions.single.verdict, WhisperLoopVerdict.keptAsSung);
      expect(result.decisions.single.secondaryMatchingRows, 6);
      expect(identical(result.lines, whisper), isFalse);
      expect(result.lines, whisper);
      expect(result.reviewRows, isEmpty);
      expect(result.changed, isFalse);
    });

    test('collapses a strong loop when the second engine loops too', () {
      final whisper = whisperLoopedSong();
      final qwen = [
        for (var i = 0; i < 8; i++)
          loopLine(
            'Now you never look back',
            90000 + i * 3000,
            93000 + i * 3000,
          ),
      ];
      final result = arbiter.arbitrate(primary: whisper, secondary: qwen);
      final decision = result.decisions.single;
      expect(decision.verdict, WhisperLoopVerdict.collapsedUnverified);
      expect(decision.secondaryLoops, isTrue);
      // The lead-in stays, one repetition of the block stays, flagged.
      expect(result.lines, hasLength(whisper.length - 20));
      expect(result.lines[10].text, loopChant);
      expect(result.lines[11].text, loopVerse);
      expect(result.lines[12].text, startsWith('What they say'));
      expect(result.reviewRows.map((row) => row.lineIndex), [10, 11]);
      expect(
        result.lines[11].confidenceSource,
        LyricConfidenceSource.heuristic,
      );
    });

    test('a chant is only flagged, even when the second engine drops it', () {
      final whisper = [
        loopLine('verse line one', 0, 4000),
        for (var i = 0; i < 8; i++)
          loopLine('Hey!', 4000 + i * 800, 4700 + i * 800),
        loopLine('outro line', 12000, 15000),
      ];
      final qwen = [
        loopLine('verse line one', 0, 4000),
        loopLine('Hey.', 4000, 5000),
        loopLine('outro line', 12000, 15000),
      ];
      final loop = const AsrSegmentLoopDetector().detect(whisper).single;
      expect(WhisperLoopArbiter.isChantLike(loop), isTrue);

      final result = arbiter.arbitrate(primary: whisper, secondary: qwen);
      expect(result.decisions.single.verdict, WhisperLoopVerdict.flaggedOnly);
      expect(result.lines, whisper);
      expect(result.reviewRows.single.lineIndex, 1);
      expect(result.changed, isFalse);
    });

    test('a weak loop the second engine disputes is flagged, not removed', () {
      final whisper = [
        loopLine('verse line one', 0, 4000),
        for (var i = 0; i < 3; i++)
          loopLine('I miss the summer rain', 4000 + i * 3000, 7000 + i * 3000),
        loopLine('outro line', 13000, 16000),
      ];
      final qwen = [
        loopLine('verse line one', 0, 4000),
        loopLine('I miss the summer rain', 4000, 7000),
        loopLine('and the sound of your name', 7000, 13000),
        loopLine('outro line', 13000, 16000),
      ];
      final result = arbiter.arbitrate(primary: whisper, secondary: qwen);
      expect(result.decisions.single.verdict, WhisperLoopVerdict.flaggedOnly);
      expect(result.lines, whisper);
    });

    test('a secondary row is never used for two loops', () {
      final whisper = [
        for (var i = 0; i < 6; i++)
          loopLine('static noise forever more', i * 1000, i * 1000 + 1000),
        for (var i = 0; i < 6; i++)
          loopLine('silent echo calling out', 6000 + i * 1000, 7000 + i * 1000),
      ];
      final qwen = [
        loopLine('the morning finds us waiting', 1000, 5500),
        loopLine('the evening lets us go', 6500, 11500),
      ];
      final result = arbiter.arbitrate(primary: whisper, secondary: qwen);
      expect(result.decisions, hasLength(2));
      expect(result.decisions[0].secondaryIndices, [0]);
      expect(result.decisions[1].secondaryIndices, [1]);
      expect(result.lines.map((line) => line.text), [
        'the morning finds us waiting',
        'the evening lets us go',
      ]);
    });
  });

  group('without a second engine', () {
    test('cuts a strong loop down to one flagged repetition', () {
      final whisper = whisperLoopedSong();
      final result = arbiter.arbitrate(primary: whisper);
      final decision = result.decisions.single;
      expect(decision.verdict, WhisperLoopVerdict.collapsedUnverified);
      expect(decision.reason, 'whisper_cross_segment_loop_collapsed');
      expect(result.lines, hasLength(whisper.length - 20));
      expect(result.sourceIndices.sublist(9, 13), [9, 10, 11, 32]);
      expect(result.reviewRows.every((row) => !row.fromSecondary), isTrue);
    });

    test('only flags a weak loop', () {
      final whisper = [
        for (var i = 0; i < 3; i++)
          loopLine('let it go', i * 3000, i * 3000 + 3000),
      ];
      final result = arbiter.arbitrate(primary: whisper);
      expect(result.decisions.single.verdict, WhisperLoopVerdict.flaggedOnly);
      expect(
        result.decisions.single.reason,
        'whisper_cross_segment_repetition',
      );
      expect(result.lines, whisper);
      expect(result.reviewRows.single.lineIndex, 0);
    });
  });

  test('heardRepeats counts exact occurrences and close rows', () {
    final loop = const AsrSegmentLoopDetector().detect([
      for (var i = 0; i < 4; i++) ...[
        loopLine('hold the line', i * 4000, i * 4000 + 2000),
        loopLine('never let it go', i * 4000 + 2000, i * 4000 + 4000),
      ],
    ]).single;
    expect(
      WhisperLoopArbiter.heardRepeats(loop, [
        loopLine('Hold the line, never let it go. Hold the line!', 0, 8000),
        loopLine('Never let it go', 8000, 10000),
      ]),
      2,
    );
    expect(
      WhisperLoopArbiter.heardRepeats(loop, [
        loopLine('something else entirely', 0, 8000),
      ]),
      0,
    );
  });
}
