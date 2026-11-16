import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/timing_provenance.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_timeline_repair_planner.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
LyricLine line(String text, int startMs, int endMs, {String? id}) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
  id: id,
);

LyricDocument document(List<LyricLine> lines) =>
    LyricDocument(language: 'zh', lines: lines);

Duration ms(int value) => Duration(milliseconds: value);

void main() {
  const planner = LyricTimelineRepairPlanner();

  group('LyricTimelineRepairPlanner fixes', () {
    test('trims an end that runs into the next row', () {
      final plan = planner.plan(
        document([line('第一句歌词', 0, 3000), line('第二句歌词', 2500, 5000)]),
      );
      expect(plan.fixes, hasLength(1));
      final fix = plan.fixes.single;
      expect(fix.index, 0);
      expect(fix.after.startTime, Duration.zero);
      expect(fix.after.endTime, ms(2500));
      expect(fix.reasons, {LyricTimelineFixReason.overlapsNext});
      expect(fix.confident, isTrue);
      expect(fix.movesStart, isFalse);
      expect(plan.manualIssues, isEmpty);
    });

    test('closes a hairline gap', () {
      final plan = planner.plan(
        document([line('第一句', 0, 2950), line('第二句', 3000, 5000)]),
      );
      expect(plan.fixes.single.after.endTime, ms(3000));
      expect(plan.fixes.single.reasons, {LyricTimelineFixReason.shortGap});
    });

    test('estimates a missing end from the text, bounded by the next row', () {
      final open = planner.plan(
        document([line('前一句', 0, 3000), line('你好', 4000, 4000)]),
      );
      // Two sung characters estimate 0.7 s, raised to the 1 s minimum.
      expect(open.fixes.single.after.endTime, ms(5000));
      expect(open.fixes.single.reasons, {LyricTimelineFixReason.zeroDuration});

      final bounded = planner.plan(
        document([
          line('前一句', 0, 3000),
          line('你好', 4000, 3900),
          line('后一句', 4600, 7000),
        ]),
      );
      expect(bounded.fixes.single.index, 1);
      expect(bounded.fixes.single.after.endTime, ms(4600));
    });

    test('moves a negative start to 0:00', () {
      final plan = planner.plan(
        document([line('开头', -500, 2000), line('后面', 3000, 5000)]),
      );
      final fix = plan.fixes.single;
      expect(fix.after.startTime, Duration.zero);
      expect(fix.after.endTime, ms(2000));
      expect(fix.reasons, {LyricTimelineFixReason.negativeStart});
      expect(fix.movesStart, isTrue);
    });

    test('clips a tail past the audio end only when the audio is known', () {
      final lines = [line('前一句', 160000, 168000), line('最后', 170000, 185000)];
      expect(planner.plan(document(lines)).isEmpty, isTrue);

      final plan = planner.plan(
        document(lines),
        audioDuration: const Duration(seconds: 180),
      );
      expect(plan.fixes.single.index, 1);
      expect(plan.fixes.single.after.endTime, const Duration(seconds: 180));
      expect(plan.fixes.single.reasons, {LyricTimelineFixReason.pastAudioEnd});
    });

    test('re-slots the row that clearly breaks the order', () {
      final plan = planner.plan(
        document([
          line('第一句', 10000, 13000),
          line('第二句', 50000, 53000),
          line('第三句', 14000, 17000),
          line('第四句', 18000, 21000),
        ]),
      );
      expect(plan.fixes, hasLength(1));
      final fix = plan.fixes.single;
      expect(fix.index, 1);
      expect(fix.after.startTime, ms(13000));
      expect(fix.after.endTime, ms(14000));
      expect(fix.reasons, {LyricTimelineFixReason.outOfOrder});
      expect(fix.confident, isFalse);
      expect(plan.manualIssues, isEmpty);
    });

    test('a duplicated start moves the lower row after the upper one', () {
      final plan = planner.plan(
        document([
          line('第一句', 10000, 12000),
          line('第二句', 14000, 16000),
          line('第三句', 14000, 15000),
          line('第四句', 20000, 22000),
        ]),
      );
      final reslot = plan.fixes.firstWhere((fix) => fix.index == 2);
      expect(reslot.after.startTime, ms(16000));
      expect(reslot.after.endTime, ms(17000));
      expect(reslot.reasons, contains(LyricTimelineFixReason.outOfOrder));
    });

    test('an ambiguous order is left for manual timing', () {
      final plan = planner.plan(
        document([
          line('第一句', 10000, 12000),
          line('第二句', 20000, 22000),
          line('第三句', 15000, 17000),
          line('第四句', 30000, 32000),
        ]),
      );
      expect(plan.fixes, isEmpty);
      expect(plan.manualIssues.map((issue) => issue.index), [1, 2]);
      expect(plan.problemRowCount, 2);
    });
  });

  group('LyricTimelineRepairPlanner protection and apply', () {
    test('hand-edited rows are never moved and are reported as skipped', () {
      final plan = planner.plan(
        document([line('第一句', 0, 3000), line('第二句', 2500, 5000)]),
        protectedIndices: {0},
      );
      expect(plan.fixes, isEmpty);
      expect(plan.skippedProtectedIndices, {0});
      expect(plan.manualIssues.map((issue) => issue.index), [1]);
    });

    test('applies only the selected fixes and records the provenance', () {
      final source = document([
        line('第一句', 0, 3000, id: 'a'),
        line('第二句', 2500, 5000, id: 'b'),
        line('第三句', 4800, 7000, id: 'c'),
      ]);
      final plan = planner.plan(source);
      expect(plan.fixes.map((fix) => fix.index), [0, 1]);

      final onlySecond = plan.applyTo(source, {1});
      expect(onlySecond.lines[0].endTime, ms(3000));
      expect(onlySecond.lines[1].endTime, ms(4800));
      expect(onlySecond.lines.map((l) => l.text), ['第一句', '第二句', '第三句']);
      expect(onlySecond.metadata[kLyricTimingProvenanceKey], {
        'b': LyricTimingProvenance.autoRepaired.name,
      });
      expect(plan.selectionAfterApply({1}), 1);
      expect(plan.selectionAfterApply({0, 1}), 0);
      expect(identical(plan.applyTo(source, const {}), source), isTrue);

      expect(planner.remainingIssues(source, plan, {0, 1}), isEmpty);
      expect(
        planner.remainingIssues(source, plan, {1}).map((i) => i.lineIndex),
        containsAll([0, 1]),
      );
    });

    test('keeps existing provenance entries of other rows', () {
      final source = LyricDocument(
        language: 'zh',
        lines: [
          line('第一句', 0, 3000, id: 'a'),
          line('第二句', 2500, 5000),
        ],
        metadata: const {
          kLyricTimingProvenanceKey: {'z': 'reference'},
        },
      );
      final plan = planner.plan(source);
      final applied = plan.applyTo(source, {0});
      expect(applied.metadata[kLyricTimingProvenanceKey], {
        'z': 'reference',
        'a': LyricTimingProvenance.autoRepaired.name,
      });
    });

    test('estimates durations within 1 to 6 seconds', () {
      expect(planner.estimateDuration('你好'), const Duration(seconds: 1));
      expect(planner.estimateDuration('hello world'), ms(1750));
      expect(
        planner.estimateDuration('一二三四五六七八九十一二三四五六七八九十一二三四'),
        const Duration(seconds: 6),
      );
    });

    test('a clean timeline has nothing to plan', () {
      final plan = planner.plan(
        document([line('第一句', 0, 3000), line('第二句', 4000, 6000)]),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.manualIssues, isEmpty);
      expect(planner.plan(document(const [])).isEmpty, isTrue);
    });
  });

  test('draft health counts rows with timeline problems', () {
    final health = const LyricDraftHealthService().analyze(
      document([
        line('第一句', 0, 3000),
        line('第二句', 2500, 5000),
        line('第三句', 6000, 6000),
      ]),
    );
    expect(health.timelineRows, 2);
    expect(health.hasIssues, isTrue);
  });
}
