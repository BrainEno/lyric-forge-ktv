import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_line_structure_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
void main() {
  const service = LyricLineStructureService();

  LyricLine line(
    String text, {
    int startMs = 0,
    int endMs = 6000,
    int confidence = 90,
    LyricConfidenceSource source = LyricConfidenceSource.model,
    bool isChorus = false,
    String? id = 'row',
  }) => LyricLine(
    text: text,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: endMs),
    confidence: confidence,
    confidenceSource: source,
    isChorus: isChorus,
    id: id,
  );

  group('suggestSplitOffset', () {
    test('picks the punctuation break nearest the sung middle', () {
      expect(service.suggestSplitOffset('我爱你，你爱我'), 4);
      expect(service.hasNaturalBreak('我爱你，你爱我'), isTrue);
    });

    test('prefers the more central of several breaks', () {
      // Breaks after 一 (1|7) and after 一二三四 (4|4).
      expect(service.suggestSplitOffset('一 二三四 五六七八'), 6);
    });

    test('falls back to the middle of a Han run without breaks', () {
      expect(service.suggestSplitOffset('一二三四五六'), 3);
      expect(service.hasNaturalBreak('一二三四五六'), isFalse);
    });

    test('never splits inside a Latin word', () {
      expect(service.suggestSplitOffset('abcdefghij'), isNull);
      expect(service.suggestSplitOffset('hello world'), 6);
    });

    test('needs at least one sung character on each side', () {
      expect(service.suggestSplitOffset('一'), isNull);
      expect(service.suggestSplitOffset('，一'), isNull);
    });
  });

  group('split', () {
    test('divides the span in proportion to what is sung', () {
      final result = service.split(line('我爱你，你爱我'));
      final split = result.split!;
      expect(split.first.text, '我爱你');
      expect(split.second.text, '你爱我');
      expect(split.splitTime, const Duration(milliseconds: 3000));
      expect(split.timingSource, LyricSplitTimingSource.textProportion);
      expect(split.first.startTime, Duration.zero);
      expect(split.first.endTime, const Duration(milliseconds: 3000));
      expect(split.second.startTime, const Duration(milliseconds: 3000));
      expect(split.second.endTime, const Duration(milliseconds: 6000));
    });

    test('keeps the id on the first half and leaves the second unset', () {
      final split = service.split(line('我爱你，你爱我', isChorus: true)).split!;
      expect(split.first.id, 'row');
      expect(split.second.id, isNull);
      expect(split.second.isChorus, isTrue);
      expect(split.second.confidence, 90);
    });

    test('uses a playhead inside the line as the boundary', () {
      final split = service
          .split(
            line('我爱你，你爱我'),
            playbackPosition: const Duration(milliseconds: 2000),
          )
          .split!;
      expect(split.splitTime, const Duration(milliseconds: 2000));
      expect(split.timingSource, LyricSplitTimingSource.playback);
    });

    test('ignores a playhead outside the line', () {
      final split = service
          .split(
            line('我爱你，你爱我'),
            playbackPosition: const Duration(milliseconds: 7000),
          )
          .split!;
      expect(split.timingSource, LyricSplitTimingSource.textProportion);
      expect(split.splitTime, const Duration(milliseconds: 3000));
    });

    test('splits at an explicit cursor offset', () {
      final split = service
          .split(line('我爱你 hello', endMs: 1000), textOffset: 4)
          .split!;
      expect(split.first.text, '我爱你');
      expect(split.second.text, 'hello');
      // 3 Han characters against 5 letters at half weight: 3 / 5.5 of 1 s.
      expect(split.splitTime, const Duration(milliseconds: 550));
    });

    test('never leaves a half shorter than the minimum duration', () {
      final split = service
          .split(line('a 一二三四五六七八九十', endMs: 1000), textOffset: 2)
          .split!;
      expect(split.first.text, 'a');
      expect(split.splitTime, const Duration(milliseconds: 200));
    });

    test('refuses a break with nothing on one side', () {
      final result = service.split(line('我爱你'), textOffset: 0);
      expect(result.succeeded, isFalse);
      expect(result.failure, LyricLineSplitFailure.emptyPart);
      expect(
        service.split(line('我爱你，'), textOffset: 4).failure,
        LyricLineSplitFailure.emptyPart,
      );
    });

    test('refuses a line too short to split', () {
      expect(
        service.split(line('我爱你，你爱我', endMs: 300)).failure,
        LyricLineSplitFailure.tooShortToSplit,
      );
    });

    test('reports when no natural break exists', () {
      expect(
        service.split(line('abcdefgh')).failure,
        LyricLineSplitFailure.noNaturalBreak,
      );
    });

    test('moves a cursor off the middle of a surrogate pair', () {
      final split = service.split(line('𠀀𠀁'), textOffset: 1).split!;
      expect(split.first.text, '𠀀');
      expect(split.second.text, '𠀁');
      expect(split.textOffset, 2);
    });
  });

  group('merge', () {
    test('joins Han text directly and Latin text with a space', () {
      expect(service.joinText('我爱你', '你爱我'), '我爱你你爱我');
      expect(service.joinText('hello', 'world'), 'hello world');
      expect(service.joinText('我爱你', 'baby'), '我爱你 baby');
      expect(service.joinText('你好，', '世界'), '你好，世界');
      expect(service.joinText(' ', '世界 '), '世界');
    });

    test('spans both rows and keeps the first id', () {
      final merged = service.merge(
        line('hello', startMs: 1000, endMs: 2000, id: 'a'),
        line('world', startMs: 2100, endMs: 3000, id: 'b', isChorus: true),
      );
      expect(merged.text, 'hello world');
      expect(merged.startTime, const Duration(milliseconds: 1000));
      expect(merged.endTime, const Duration(milliseconds: 3000));
      expect(merged.id, 'a');
      expect(merged.isChorus, isTrue);
    });

    test('keeps the weaker real score', () {
      final merged = service.merge(
        line('a', confidence: 80),
        line('b', confidence: 60),
      );
      expect(merged.confidence, 60);
      expect(merged.confidenceSource, LyricConfidenceSource.model);
    });

    test('a placeholder score never outranks a real one', () {
      final merged = service.merge(
        line(
          'a',
          confidence: unscoredConfidencePlaceholder,
          source: LyricConfidenceSource.unscored,
        ),
        line('b', confidence: 90),
      );
      expect(merged.confidence, 90);
      expect(merged.confidenceSource, LyricConfidenceSource.model);

      final bothUnscored = service.merge(
        line('a', confidence: 50, source: LyricConfidenceSource.unscored),
        line('b', confidence: 40, source: LyricConfidenceSource.unscored),
      );
      expect(bothUnscored.confidenceSource, LyricConfidenceSource.unscored);
      expect(bothUnscored.confidence, 40);
    });

    test('a heuristic score stays marked as heuristic', () {
      final merged = service.merge(
        line('a', confidence: 70, source: LyricConfidenceSource.heuristic),
        line('b', confidence: 95),
      );
      expect(merged.confidence, 70);
      expect(merged.confidenceSource, LyricConfidenceSource.heuristic);
    });
  });
}
