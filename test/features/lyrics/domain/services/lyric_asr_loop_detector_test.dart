import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_asr_loop_detector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_word_timing_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
LyricLine row(String text, int second, {String? id}) => LyricLine(
  text: text,
  startTime: Duration(seconds: second),
  endTime: Duration(seconds: second, milliseconds: 900),
  id: id ?? 'r$second',
);

LyricDocument doc(List<String> texts) => LyricDocument(
  language: 'zh',
  lines: [for (var i = 0; i < texts.length; i++) row(texts[i], i * 2)],
);

void main() {
  const detector = LyricAsrLoopDetector();

  group('tokens', () {
    test('Han characters are single tokens, Latin words stay whole', () {
      expect(
        detector.tokens("我爱你, don't stop lovin'").map((t) => t.key),
        ['我', '爱', '你', "don't", 'stop', 'lovin'],
      );
      expect(detector.rowKey('Baby, BABY!'), detector.rowKey('baby baby'));
    });
  });

  group('in-row loops', () {
    test('a phrase repeated many times is cut to two', () {
      final runs = detector.loops('我爱你我爱你我爱你我爱你我爱你我爱你我爱你');
      expect(runs, hasLength(1));
      expect(runs.single.unit, '我爱你');
      expect(runs.single.repeats, 7);
      expect(detector.collapse('我爱你我爱你我爱你我爱你我爱你我爱你我爱你', runs), '我爱你我爱你');
    });

    test('a held character needs eight repeats and keeps four', () {
      expect(detector.loops('啦啦啦啦啦啦'), isEmpty);
      final text = '等你啊啊啊啊啊啊啊啊啊啊啊啊回来';
      final runs = detector.loops(text);
      expect(runs.single.unit, '啊');
      expect(runs.single.repeats, 12);
      expect(detector.collapse(text, runs), '等你啊啊啊啊回来');
    });

    test('ordinary repetition in a lyric is not a loop', () {
      expect(detector.loops('爱你爱你爱你'), isEmpty);
      expect(detector.loops('我爱你 我爱你 我爱你'), isEmpty);
      expect(detector.loops('baby baby baby'), isEmpty);
    });

    test('Latin loops keep their spacing', () {
      const text = 'oh baby, baby baby baby baby baby baby please';
      final runs = detector.loops(text);
      expect(runs.single.unit, 'baby');
      expect(runs.single.repeats, 7);
      expect(detector.collapse(text, runs), 'oh baby, baby please');
    });
  });

  group('plan', () {
    test('lists in-row loops with a strength', () {
      final plan = detector.plan(
        doc([
          '我爱你我爱你我爱你我爱你',
          '普通的一句',
          '我爱你我爱你我爱你我爱你我爱你我爱你',
        ]),
      );
      expect(plan.issues, hasLength(2));
      expect(plan.issues.first.kind, LyricAsrLoopKind.inRowRepeat);
      expect(plan.issues.first.strong, isFalse);
      expect(plan.issues.last.strong, isTrue);
      expect(plan.defaultPositions, [1]);
    });

    test('a run of identical rows keeps the first two', () {
      final document = doc([
        '开始',
        '谢谢你',
        '谢谢你。',
        '谢谢你',
        '谢谢 你',
        '谢谢你',
        '谢谢你',
        '结束',
      ]);
      final plan = detector.plan(document);
      final issue = plan.issues.single;
      expect(issue.kind, LyricAsrLoopKind.repeatedRows);
      expect(issue.runIndices, [1, 2, 3, 4, 5, 6]);
      expect(issue.removedIndices, [3, 4, 5, 6]);
      expect(issue.strong, isTrue);

      final applied = plan.applyTo(document, {0});
      expect(applied.lines.map((l) => l.text), ['开始', '谢谢你', '谢谢你。', '结束']);
      expect(applied.lines[1].id, 'r2');
    });

    test('four identical rows are listed but not selected', () {
      final plan = detector.plan(doc(['一起唱', '一起唱', '一起唱', '一起唱']));
      expect(plan.issues.single.strong, isFalse);
      expect(plan.defaultPositions, isEmpty);
      expect(plan.fixablePositions, [0]);
      expect(detector.plan(doc(['一起唱', '一起唱', '一起唱'])).issues, isEmpty);
    });

    test('hand-edited rows are never changed', () {
      final loop = '啊啊啊啊啊啊啊啊啊啊啊啊';
      final plan = detector.plan(doc([loop]), protectedIndices: {0});
      expect(plan.issues.single.protected, isTrue);
      expect(plan.issues.single.fixable, isFalse);

      final rows = detector.plan(
        doc(['一起唱', '一起唱', '一起唱', '一起唱', '一起唱', '一起唱']),
        protectedIndices: {3},
      );
      expect(rows.issues.single.removedIndices, [2, 4, 5]);
    });

    test('a kept row of a run that loops inside is fixed too', () {
      final loop = '啊啊啊啊啊啊啊啊啊啊啊啊';
      final document = doc([loop, loop, loop, loop, loop, loop]);
      final plan = detector.plan(document);
      expect(plan.issues.map((i) => i.kind), [
        LyricAsrLoopKind.repeatedRows,
        LyricAsrLoopKind.inRowRepeat,
        LyricAsrLoopKind.inRowRepeat,
      ]);
      final all = plan.fixablePositions.toSet();
      expect(plan.countFor(all), (rewritten: 2, removed: 4));
      final applied = plan.applyTo(document, all);
      expect(applied.lines.map((l) => l.text), ['啊啊啊啊', '啊啊啊啊']);
    });

    test('a rewritten row keeps its words, which then stop matching', () {
      final line = LyricLine(
        text: '啊啊啊啊啊啊啊啊',
        startTime: Duration.zero,
        endTime: const Duration(seconds: 4),
        words: [
          for (var i = 0; i < 8; i++)
            LyricWordTiming(
              text: '啊',
              start: Duration(milliseconds: i * 500),
              end: Duration(milliseconds: i * 500 + 500),
            ),
        ],
      );
      final document = LyricDocument(language: 'zh', lines: [line]);
      final plan = detector.plan(document);
      final applied = plan.applyTo(document, {0});
      expect(applied.lines.single.text, '啊啊啊啊');
      expect(applied.lines.single.words, hasLength(8));
      expect(
        const LyricWordTimingService().isUsable(applied.lines.single),
        isFalse,
      );
    });
  });

  test('draft health counts loop rows', () {
    final health = const LyricDraftHealthService().analyze(
      doc(['我爱你我爱你我爱你我爱你我爱你我爱你', '一句', '一句', '一句', '一句', '一句']),
    );
    expect(health.loopRows, 1 + 3);
    expect(health.hasIssues, isTrue);
  });
}
