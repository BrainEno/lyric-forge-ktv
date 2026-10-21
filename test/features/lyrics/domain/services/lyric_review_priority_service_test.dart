import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const service = LyricReviewPriorityService();

  LyricLine line(
    String text, {
    int confidence = 100,
    int startMs = 0,
    int endMs = 1000,
  }) => LyricLine(
    text: text,
    confidence: confidence,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: endMs),
  );

  test('prioritizes empty and very low-confidence lines above mild signals', () {
    final document = LyricDocument(
      language: 'en',
      lines: [
        line('A clean line'),
        line('low confidence', confidence: 20, startMs: 1000, endMs: 2000),
        line('', startMs: 2000, endMs: 3000),
        line('moderate confidence', confidence: 65, startMs: 3000, endMs: 4000),
      ],
    );

    final ranked = service.rank(document);

    expect(ranked.map((item) => item.lineIndex), [2, 1, 3]);
    expect(ranked.first.reasons, contains('歌词为空'));
    expect(ranked[1].reasons, contains('识别置信度极低（20）'));
    expect(ranked.every((item) => item.score <= 100), isTrue);
  });

  test('explains and ranks disagreement between two ASR engines', () {
    final document = LyricDocument(
      language: 'en',
      lines: [
        line('into the night', confidence: 58, startMs: 0, endMs: 1000),
        line('steady lyric', startMs: 1000, endMs: 2000),
      ],
      metadata: {
        'fallbackCandidates': [
          {
            'lineIndex': 0,
            'primaryEngine': 'qwen',
            'alternativeEngine': 'whisper',
            'primaryText': 'in the night',
            'alternativeText': 'into the night',
            'similarity': 0.42,
          },
        ],
      },
    );

    final ranked = service.rank(document);

    expect(ranked, hasLength(1));
    expect(ranked.single.lineIndex, 0);
    expect(ranked.single.reasons, contains('双引擎结果差异很大'));
    expect(ranked.single.level, LyricReviewRiskLevel.high);
  });

  test('flags serious timing conflicts and keeps their original line indices', () {
    final document = LyricDocument(
      language: 'en',
      lines: [
        line('first', startMs: 1000, endMs: 4000),
        line('second', startMs: 500, endMs: 400),
        line('third', startMs: 4000, endMs: 5000),
      ],
    );

    final ranked = service.rank(document);

    final second = ranked.firstWhere((item) => item.lineIndex == 1);
    expect(second.score, greaterThanOrEqualTo(65));
    expect(second.reasons, contains('歌词时间区间无效'));
    expect(second.reasons, contains('歌词顺序与时间顺序不一致'));
  });

  test('flags likely ASR repetition without assuming repeated lyrics are wrong', () {
    final document = LyricDocument(
      language: 'en',
      lines: [
        line('hello hello hello hello', confidence: 80),
        line('la la la la', confidence: 100, startMs: 1000, endMs: 2000),
        line('a genuinely different line', startMs: 2000, endMs: 3000),
      ],
    );

    final ranked = service.rank(document);

    expect(ranked.map((item) => item.lineIndex), [0]);
    expect(
      ranked.single.reasons,
      contains('出现连续重复词，建议确认是否为识别重复'),
    );
  });

  test('does not nag about a fully confident, clean lyric document', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [
        line('第一句歌词', startMs: 0, endMs: 1000),
        line('第二句歌词', startMs: 1100, endMs: 2200),
        line('第三句歌词', startMs: 2300, endMs: 3500),
      ],
    );

    expect(service.rank(document), isEmpty);
  });

  test('excludes explicitly reviewed lines until text or timing changes', () {
    final document = LyricDocument(
      language: 'en',
      lines: [
        LyricLine(
          id: 'reviewed-line',
          text: 'repeated repeated repeated',
          confidence: 45,
          startTime: Duration.zero,
          endTime: const Duration(seconds: 2),
        ),
        LyricLine(
          id: 'unreviewed-line',
          text: 'steady line',
          confidence: 40,
          startTime: const Duration(seconds: 2),
          endTime: const Duration(seconds: 4),
        ),
      ],
    );
    final decisions = const LyricReviewDecisionService();
    final reviewedDocument = decisions.setReviewed(
      document,
      0,
      reviewed: true,
      reviewedAt: DateTime.utc(2026, 10, 21),
    );

    expect(service.rank(reviewedDocument).map((item) => item.lineIndex), [1]);

    final edited = reviewedDocument.copyWith(
      lines: [
        reviewedDocument.lines[0].copyWith(
          endTime: const Duration(milliseconds: 2100),
        ),
        reviewedDocument.lines[1],
      ],
    );
    expect(service.rank(edited).map((item) => item.lineIndex), [0, 1]);
  });

  test('shows long and suspicious intervals with readable reasons', () {
    final document = LyricDocument(
      language: 'en',
      lines: [
        line('this lyric row has many words', confidence: 90, startMs: 0, endMs: 100),
        line('a long held vocal', startMs: 100, endMs: 25000),
      ],
    );

    final ranked = service.rank(document);

    expect(ranked.map((item) => item.lineIndex), [0, 1]);
    expect(ranked.first.reasons, contains('歌词文本较长但显示区间极短'));
    expect(ranked.last.reasons, contains('单行持续时间超过 20 秒'));
  });
}
