import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/timing_provenance.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_pace_analyzer.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
LyricLine line(String text, int startMs, int endMs, {String? id}) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
  id: id,
);

/// Seven rows at 3 characters per second, one crowded row (12 characters
/// in one second), one sparse row (4 characters over ten seconds) and one
/// held exclamation that is too short to judge.
LyricDocument paceSong({Map<String, Object?> metadata = const {}}) =>
    LyricDocument(
      language: 'zh',
      metadata: metadata,
      lines: [
        line('春风吹过山岗', 0, 2000),
        line('细雨落在窗前', 3000, 5000),
        line('我们走过长街', 6000, 8000),
        line('一二三四五六七八九十百千', 9000, 10000, id: 'crowded'),
        line('灯火照亮归途', 12000, 14000),
        line('啊啊啊啊', 15000, 25000, id: 'sparse'),
        line('明天还会再见', 27000, 29000),
        line('星光洒满天空', 30000, 32000),
        line('故事还没说完', 33000, 35000),
        line('哦', 36000, 46000),
      ],
    );

void main() {
  const analyzer = LyricPaceAnalyzer();

  test('measures the song median and flags crowded and sparse rows', () {
    final plan = analyzer.plan(paceSong());
    expect(plan.measured, isTrue);
    expect(plan.medianRate, closeTo(3, 0.001));
    expect(plan.issues.map((i) => (i.index, i.kind)), [
      (3, LyricPaceIssueKind.crowded),
      (5, LyricPaceIssueKind.sparse),
    ]);
    final crowded = plan.issues.first;
    expect(crowded.rate, closeTo(12, 0.001));
    expect(crowded.factor(plan.medianRate), closeTo(4, 0.001));
    // Extended towards four seconds, stopped 100 ms before the next row.
    expect(crowded.proposedEnd, const Duration(milliseconds: 11900));
    final sparse = plan.issues.last;
    expect(sparse.expected.inMilliseconds, closeTo(1333, 1));
    // Pulled in to 1.4 × the median duration.
    expect(sparse.proposedEnd, const Duration(milliseconds: 16870));
    expect(plan.fixablePositions, [0, 1]);
  });

  test('applying the proposals moves only the ends and records them', () {
    final document = paceSong();
    final plan = analyzer.plan(document);
    final after = plan.applyTo(document, {0, 1});
    expect(after.lines[3].startTime, const Duration(milliseconds: 9000));
    expect(after.lines[3].endTime, const Duration(milliseconds: 11900));
    expect(after.lines[5].endTime, const Duration(milliseconds: 16870));
    expect(after.lines[5].text, '啊啊啊啊');
    final provenance = after.metadata[kLyricTimingProvenanceKey] as Map;
    expect(provenance['crowded'], LyricTimingProvenance.autoRepaired.name);
    expect(provenance['sparse'], LyricTimingProvenance.autoRepaired.name);
    expect(identical(plan.applyTo(document, {}), document), isTrue);
  });

  test('hand-timed and protected rows are reported without proposals', () {
    final plan = analyzer.plan(
      paceSong(
        metadata: {
          kLyricTimingProvenanceKey: {
            'crowded': LyricTimingProvenance.manual.name,
          },
        },
      ),
      protectedIndices: {5},
    );
    expect(plan.issues, hasLength(2));
    expect(plan.issues.every((issue) => !issue.fixable), isTrue);
    expect(plan.fixablePositions, isEmpty);
  });

  test('a crowded row with no room after it has no proposal', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [
        for (var i = 0; i < 6; i++) line('春风吹过山岗', i * 3000, i * 3000 + 2000),
        line('一二三四五六七八九十百千', 18000, 19000),
        line('春风吹过山岗', 19050, 21050),
      ],
    );
    final plan = analyzer.plan(document);
    expect(plan.issues.single.kind, LyricPaceIssueKind.crowded);
    expect(plan.issues.single.fixable, isFalse);
  });

  test('few measurable rows fall back to the default pace', () {
    final plan = analyzer.plan(
      LyricDocument(
        language: 'zh',
        lines: [line('春风吹过山岗', 0, 2000), line('啊啊啊啊', 3000, 15000)],
      ),
    );
    expect(plan.measured, isFalse);
    expect(plan.medianRate, LyricPaceAnalyzer.defaultRate);
    expect(plan.issues.single.kind, LyricPaceIssueKind.sparse);
  });

  test('draft health counts pace issues', () {
    final health = const LyricDraftHealthService().analyze(paceSong());
    expect(health.paceRows, 2);
    expect(health.hasIssues, isTrue);
  });
}
