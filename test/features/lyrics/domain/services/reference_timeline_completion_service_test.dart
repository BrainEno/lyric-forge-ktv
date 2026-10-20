import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_alignment_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_timeline_completion_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const alignmentService = LyricAlignmentService();
  const completionService = ReferenceTimelineCompletionService();

  LyricDocument buildDocument(List<LyricLine> lines) {
    return LyricDocument(language: 'zh', lines: lines);
  }

  ReferenceLineCompletionPlan buildPlan(
    LyricDocument document,
    List<ReferenceLyricLine> referenceLines,
  ) {
    return completionService.buildPlan(
      document: document,
      alignment: alignmentService.align(
        document: document,
        referenceLines: referenceLines,
      ),
    );
  }

  test('两条锚点之间的一条漏行按空隙推断时间', () {
    final document = buildDocument(const [
      LyricLine(
        text: '第一句歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
      ),
      LyricLine(
        text: '第三句歌词',
        startTime: Duration(seconds: 8),
        endTime: Duration(seconds: 12),
      ),
    ]);

    final plan = buildPlan(document, const [
      ReferenceLyricLine(text: '第一句歌词'),
      ReferenceLyricLine(text: '第二句歌词'),
      ReferenceLyricLine(text: '第三句歌词'),
    ]);

    expect(plan.insertions, hasLength(1));
    final insertion = plan.insertions.single;
    expect(insertion.referenceIndex, 1);
    expect(insertion.text, '第二句歌词');
    expect(insertion.insertBeforeAsrLineIndex, 1);
    expect(insertion.startTime, const Duration(seconds: 4));
    expect(insertion.endTime, const Duration(seconds: 8));
    expect(insertion.previousAsrLineIndex, 0);
    expect(insertion.nextAsrLineIndex, 1);
    expect(insertion.requiresConfirmation, isFalse);
  });

  test('连续漏行按参考顺序均分同一段空隙', () {
    final document = buildDocument(const [
      LyricLine(
        text: '第一句歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 2),
      ),
      LyricLine(
        text: '第五句歌词',
        startTime: Duration(seconds: 10),
        endTime: Duration(seconds: 12),
      ),
    ]);

    final plan = buildPlan(document, const [
      ReferenceLyricLine(text: '第一句歌词'),
      ReferenceLyricLine(text: '第二句歌词'),
      ReferenceLyricLine(text: '第三句歌词'),
      ReferenceLyricLine(text: '第四句歌词'),
      ReferenceLyricLine(text: '第五句歌词'),
    ]);

    expect(plan.insertions, hasLength(3));
    expect(plan.insertions.map((insertion) => insertion.referenceIndex), [
      1,
      2,
      3,
    ]);
    expect(
      plan.insertions.every(
        (insertion) => insertion.insertBeforeAsrLineIndex == 1,
      ),
      isTrue,
    );
    expect(plan.insertions.first.startTime, const Duration(seconds: 2));
    expect(plan.insertions.last.endTime, const Duration(seconds: 10));
    for (var index = 1; index < plan.insertions.length; index++) {
      expect(
        plan.insertions[index].startTime,
        greaterThanOrEqualTo(plan.insertions[index - 1].endTime),
      );
    }
  });

  test('开头漏行从零开始分配', () {
    final document = buildDocument(const [
      LyricLine(
        text: '第二句歌词',
        startTime: Duration(seconds: 5),
        endTime: Duration(seconds: 9),
      ),
    ]);

    final plan = buildPlan(document, const [
      ReferenceLyricLine(text: '第一句歌词'),
      ReferenceLyricLine(text: '第二句歌词'),
    ]);

    final insertion = plan.insertions.single;
    expect(insertion.insertBeforeAsrLineIndex, 0);
    expect(insertion.startTime, Duration.zero);
    expect(insertion.endTime, const Duration(seconds: 5));
    expect(insertion.requiresConfirmation, isFalse);
  });

  test('末尾漏行从上一行结束时间开始并默认延长五秒', () {
    final document = buildDocument(const [
      LyricLine(
        text: '第一句歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
      ),
    ]);

    final plan = buildPlan(document, const [
      ReferenceLyricLine(text: '第一句歌词'),
      ReferenceLyricLine(text: '第二句歌词'),
    ]);

    final insertion = plan.insertions.single;
    expect(insertion.insertBeforeAsrLineIndex, 1);
    expect(insertion.startTime, const Duration(seconds: 4));
    expect(insertion.endTime, const Duration(seconds: 9));
    expect(insertion.requiresConfirmation, isFalse);
  });

  test('锚点之间夹着未匹配行时标记为需确认', () {
    final document = buildDocument(const [
      LyricLine(
        text: '第一句歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
      ),
      LyricLine(
        text: '完全无关的幻觉行',
        startTime: Duration(seconds: 4),
        endTime: Duration(seconds: 8),
      ),
      LyricLine(
        text: '第三句歌词',
        startTime: Duration(seconds: 8),
        endTime: Duration(seconds: 12),
      ),
    ]);

    final plan = buildPlan(document, const [
      ReferenceLyricLine(text: '第一句歌词'),
      ReferenceLyricLine(text: '第二句歌词'),
      ReferenceLyricLine(text: '第三句歌词'),
    ]);

    final insertion = plan.insertions.single;
    expect(insertion.insertBeforeAsrLineIndex, 2);
    expect(insertion.requiresConfirmation, isTrue);
  });

  test('带时间戳的漏行优先使用参考时间', () {
    final document = buildDocument(const [
      LyricLine(
        text: '第一句歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
      ),
      LyricLine(
        text: '第三句歌词',
        startTime: Duration(seconds: 8),
        endTime: Duration(seconds: 12),
      ),
    ]);

    final plan = buildPlan(document, const [
      ReferenceLyricLine(
        text: '第一句歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
      ),
      ReferenceLyricLine(
        text: '第二句歌词',
        startTime: Duration(milliseconds: 4500),
        endTime: Duration(milliseconds: 7500),
      ),
      ReferenceLyricLine(
        text: '第三句歌词',
        startTime: Duration(seconds: 8),
        endTime: Duration(seconds: 12),
      ),
    ]);

    final insertion = plan.insertions.single;
    expect(insertion.startTime, const Duration(milliseconds: 4500));
    expect(insertion.endTime, const Duration(milliseconds: 7500));
    expect(insertion.requiresConfirmation, isFalse);
  });

  test('空隙不足时标记为需确认并保证最小时长', () {
    final document = buildDocument(const [
      LyricLine(
        text: '第一句歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 5),
      ),
      LyricLine(
        text: '第三句歌词',
        startTime: Duration(seconds: 5),
        endTime: Duration(seconds: 10),
      ),
    ]);

    final plan = buildPlan(document, const [
      ReferenceLyricLine(text: '第一句歌词'),
      ReferenceLyricLine(text: '第二句歌词'),
      ReferenceLyricLine(text: '第三句歌词'),
    ]);

    final insertion = plan.insertions.single;
    expect(insertion.requiresConfirmation, isTrue);
    expect(
      insertion.endTime - insertion.startTime,
      greaterThanOrEqualTo(ReferenceTimelineCompletionService.minimumDuration),
    );
  });

  test('多个漏行组分别插入到各自的后锚点之前', () {
    final document = buildDocument(const [
      LyricLine(
        text: '第一句歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
      ),
      LyricLine(
        text: '第三句歌词',
        startTime: Duration(seconds: 8),
        endTime: Duration(seconds: 12),
      ),
      LyricLine(
        text: '第五句歌词',
        startTime: Duration(seconds: 16),
        endTime: Duration(seconds: 20),
      ),
    ]);

    final plan = buildPlan(document, const [
      ReferenceLyricLine(text: '第一句歌词'),
      ReferenceLyricLine(text: '第二句歌词'),
      ReferenceLyricLine(text: '第三句歌词'),
      ReferenceLyricLine(text: '第四句歌词'),
      ReferenceLyricLine(text: '第五句歌词'),
    ]);

    expect(plan.insertions, hasLength(2));
    expect(plan.insertions[0].referenceIndex, 1);
    expect(plan.insertions[0].insertBeforeAsrLineIndex, 1);
    expect(plan.insertions[0].startTime, const Duration(seconds: 4));
    expect(plan.insertions[0].endTime, const Duration(seconds: 8));
    expect(plan.insertions[1].referenceIndex, 3);
    expect(plan.insertions[1].insertBeforeAsrLineIndex, 2);
    expect(plan.insertions[1].startTime, const Duration(seconds: 12));
    expect(plan.insertions[1].endTime, const Duration(seconds: 16));
  });

  test('没有漏行时返回空计划', () {
    final document = buildDocument(const [
      LyricLine(
        text: '第一句歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
      ),
    ]);

    final plan = buildPlan(document, const [ReferenceLyricLine(text: '第一句歌词')]);

    expect(plan.isEmpty, isTrue);
  });
}
