import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_segment_loop_detector.dart';

import 'whisper_loop_fixtures.dart';

void main() {
  const detector = AsrSegmentLoopDetector();

  group('loopKey', () {
    test('ignores case, punctuation, apostrophes and stutters', () {
      expect(AsrSegmentLoopDetector.loopKey('Oh-oh-oh-oh'), 'oh');
      expect(
        AsrSegmentLoopDetector.loopKey('Oh-oh-oh-oh-oh-oh-oh'),
        AsrSegmentLoopDetector.loopKey('oh, OH!'),
      );
      expect(
        AsrSegmentLoopDetector.loopKey("We don't need to stare."),
        'we dont need to stare',
      );
      expect(AsrSegmentLoopDetector.loopKey('♪♪♪'), isEmpty);
    });

    test('treats every CJK character as a word', () {
      expect(AsrSegmentLoopDetector.loopKey('我爱你，我爱你'), '我 爱 你 我 爱 你');
      expect(AsrSegmentLoopDetector.loopKey('啊啊啊啊'), '啊');
    });

    test('tokens keep repeats for counting', () {
      expect(AsrSegmentLoopDetector.tokens('Hey hey, HEY'), [
        'hey',
        'hey',
        'hey',
      ]);
    });
  });

  group('spoken units and density', () {
    test('counts words, CJK characters and contractions once', () {
      expect(AsrSegmentLoopDetector.spokenUnits("we don't stop"), 3);
      expect(AsrSegmentLoopDetector.spokenUnits('我爱你 baby'), 4);
    });

    test('flags a row that cannot be sung in its span', () {
      expect(
        AsrSegmentLoopDetector.isImplausiblyDense(loopLine(loopVerse, 0, 1000)),
        isTrue,
      );
      expect(
        AsrSegmentLoopDetector.isImplausiblyDense(loopLine(loopVerse, 0, 4000)),
        isFalse,
      );
      // Too few words to judge.
      expect(
        AsrSegmentLoopDetector.isImplausiblyDense(loopLine('oh yeah', 0, 100)),
        isFalse,
      );
    });
  });

  group('detect', () {
    test('finds the cross-segment block loop of a real failure', () {
      final lines = whisperLoopedSong();
      final loops = detector.detect(lines);

      expect(loops, hasLength(1));
      final loop = loops.single;
      expect(loop.kind, AsrSegmentLoopKind.repeatedBlock);
      expect(loop.blockRows, 2);
      expect(loop.repeats, 11);
      expect(loop.firstIndex, 10);
      expect(loop.endIndex, 32);
      expect(loop.unitText, [loopChant, loopVerse]);
      expect(loop.compressedTiming, isTrue);
      expect(loop.hasImplausibleTiming, isTrue);
      expect(loop.strong, isTrue);
      // The squeezed rows before the loop share its broken timestamps.
      expect(loop.leadInIndex, 4);
      expect(loop.spanStart, const Duration(milliseconds: 89280));
      // The loop claims the audio up to the next real row.
      expect(loop.end, lines[32].startTime);
      expect(loop.indices, [for (var i = 10; i < 32; i++) i]);
    });

    test('finds identical consecutive rows and grades their strength', () {
      final rows = [
        loopLine('first line of the verse', 0, 3000),
        for (var i = 0; i < 6; i++)
          loopLine(
            'I keep falling down again',
            3000 + i * 3000,
            6000 + i * 3000,
          ),
        loopLine('the bridge begins', 21000, 24000),
      ];
      final loop = detector.detect(rows).single;
      expect(loop.kind, AsrSegmentLoopKind.repeatedRows);
      expect(loop.repeats, 6);
      expect(loop.strong, isTrue);
      expect(loop.compressedTiming, isFalse);
      expect(loop.leadInIndex, loop.firstIndex);

      final weak = detector.detect(rows.sublist(0, 4)).single;
      expect(weak.repeats, 3);
      expect(weak.strong, isFalse);
    });

    test('ignores ordinary lyrics and twice-repeated choruses', () {
      final rows = [
        loopLine('city lights are calling', 0, 3000),
        loopLine('every window burning gold', 3000, 6000),
        loopLine('city lights are calling', 6000, 9000),
        loopLine('every window burning gold', 9000, 12000),
        loopLine('we run until the morning', 12000, 15000),
      ];
      expect(detector.detect(rows), isEmpty);
    });

    test('a periodic block is reported at its smallest size', () {
      final rows = [
        for (var i = 0; i < 8; i++)
          loopLine('na na na', i * 1000, i * 1000 + 900),
      ];
      final loop = detector.detect(rows).single;
      expect(loop.blockRows, 1);
      expect(loop.repeats, 8);
    });

    test('rows without words break a run', () {
      final rows = [
        loopLine('stay with me', 0, 2000),
        loopLine('stay with me', 2000, 4000),
        loopLine('♪', 4000, 6000),
        loopLine('stay with me', 6000, 8000),
        loopLine('stay with me', 8000, 10000),
      ];
      expect(detector.detect(rows), isEmpty);
    });

    test('a trailing partial block stays outside the loop', () {
      final rows = [
        for (var i = 0; i < 3; i++) ...[
          loopLine('hold the line', i * 4000, i * 4000 + 2000),
          loopLine('never let it go', i * 4000 + 2000, i * 4000 + 4000),
        ],
        loopLine('hold the line', 12000, 14000),
        loopLine('the song ends here', 14000, 18000),
      ];
      final loop = detector.detect(rows).single;
      expect(loop.repeats, 3);
      expect(loop.endIndex, 6);
      expect(loop.end, const Duration(milliseconds: 12000));
    });

    test('a lead-in never reaches into an earlier loop', () {
      final rows = [
        for (var i = 0; i < 4; i++)
          loopLine('again and again and again', i * 1000, i * 1000 + 1000),
        for (var i = 0; i < 4; i++)
          loopLine('over and over we go', 4000 + i * 1000, 5000 + i * 1000),
      ];
      final loops = detector.detect(rows);
      expect(loops, hasLength(2));
      expect(loops[1].firstIndex, 4);
      expect(loops[1].leadInIndex, 4);
    });

    test('metadata describes the loop without lyric-independent noise', () {
      final loop = detector.detect(whisperLoopedSong()).single;
      final metadata = loop.toMetadata();
      expect(metadata['kind'], 'repeatedBlock');
      expect(metadata['repeats'], 11);
      expect(metadata['blockRows'], 2);
      expect(metadata['leadInIndex'], 4);
      expect(metadata['spanStartMs'], 89280);
      expect(metadata['strong'], isTrue);
      expect(metadata['unit'], [loopChant, loopVerse]);
    });
  });
}
