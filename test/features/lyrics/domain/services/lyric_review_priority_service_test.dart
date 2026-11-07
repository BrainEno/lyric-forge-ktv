import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const service = LyricReviewPriorityService();

  void expectReason(
    LyricReviewPriority priority,
    LyricReviewPriorityReasonCode code, {
    int? confidence,
  }) {
    expect(
      priority.reasons,
      contains(LyricReviewPriorityReason(code, confidence: confidence)),
    );
  }

  LyricLine line(
    String text, {
    int confidence = 100,
    LyricConfidenceSource confidenceSource = LyricConfidenceSource.model,
    int startMs = 0,
    int endMs = 1000,
  }) => LyricLine(
    text: text,
    confidence: confidence,
    confidenceSource: confidenceSource,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: endMs),
  );

  test(
    'prioritizes empty and very low-confidence lines above mild signals',
    () {
      final document = LyricDocument(
        language: 'en',
        lines: [
          line('A clean line'),
          line('low confidence', confidence: 20, startMs: 1000, endMs: 2000),
          line('', startMs: 2000, endMs: 3000),
          line(
            'moderate confidence',
            confidence: 65,
            startMs: 3000,
            endMs: 4000,
          ),
        ],
      );

      final ranked = service.rank(document);

      expect(ranked.map((item) => item.lineIndex), [2, 1, 3]);
      expectReason(ranked.first, LyricReviewPriorityReasonCode.emptyLyrics);
      expectReason(
        ranked[1],
        LyricReviewPriorityReasonCode.confidenceExtremelyLow,
        confidence: 20,
      );
      expect(ranked.every((item) => item.score <= 100), isTrue);
    },
  );

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
    expectReason(
      ranked.single,
      LyricReviewPriorityReasonCode.enginesDifferGreatly,
    );
    expect(ranked.single.level, LyricReviewRiskLevel.high);
  });

  for (final confidence in [100, 99, 85, 70]) {
    test('unreviewed disagreement enters queue at confidence $confidence', () {
      final document = LyricDocument(
        language: 'en',
        lines: [
          line('into the night', confidence: confidence).copyWith(id: 'line-1'),
        ],
        metadata: const {
          'fallbackCandidates': [
            {
              'lineIndex': 0,
              'primaryText': 'in the night',
              'alternativeText': 'into the night',
              'similarity': 0.42,
            },
          ],
        },
      );
      final queue = LyricReviewQueue.build(document);
      expect(queue.needsReview(0), isTrue);
      expect(queue.lowConfidenceCount, 0);
      expectReason(
        queue.items.single,
        LyricReviewPriorityReasonCode.enginesDifferGreatly,
      );

      const decisions = LyricReviewDecisionService();
      final reviewed = decisions.setReviewed(document, 0, reviewed: true);
      expect(LyricReviewQueue.build(reviewed).needsReview(0), isFalse);
      final reopened = decisions.setReviewed(reviewed, 0, reviewed: false);
      expect(LyricReviewQueue.build(reopened).needsReview(0), isTrue);
      final changed = reviewed.copyWith(
        lines: [reviewed.lines.single.copyWith(text: 'manual edit')],
      );
      expect(LyricReviewQueue.build(changed).needsReview(0), isTrue);
    });
  }

  test('unscored disagreement is evidence without being low confidence', () {
    final document = LyricDocument(
      language: 'en',
      lines: [
        line(
          'first',
          confidence: 100,
          confidenceSource: LyricConfidenceSource.unscored,
        ),
      ],
      metadata: const {
        'fallbackCandidates': [
          {
            'lineIndex': 0,
            'primaryText': 'first',
            'alternativeText': 'second',
            'similarity': 0.6,
          },
        ],
      },
    );
    final queue = LyricReviewQueue.build(document);
    expect(queue.needsReview(0), isTrue);
    expect(queue.lowConfidenceCount, 0);
    expectReason(
      queue.items.single,
      LyricReviewPriorityReasonCode.enginesDifferClearly,
    );
  });

  test('confidence 100 without a real disagreement stays out of the queue', () {
    for (final candidate in [
      <String, dynamic>{
        'lineIndex': 0,
        'primaryText': 'same',
        'alternativeText': 'same',
      },
      <String, dynamic>{'lineIndex': 0, 'primaryText': 'same'},
    ]) {
      final document = LyricDocument(
        language: 'en',
        lines: [line('same', confidence: 100)],
        metadata: {
          'fallbackCandidates': [candidate],
        },
      );
      expect(service.rank(document), isEmpty);
    }
  });

  test(
    'flags serious timing conflicts and keeps their original line indices',
    () {
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
      expectReason(second, LyricReviewPriorityReasonCode.invalidTimeInterval);
      expectReason(second, LyricReviewPriorityReasonCode.nonMonotonicStart);
    },
  );

  test(
    'flags likely ASR repetition without assuming repeated lyrics are wrong',
    () {
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
      expectReason(ranked.single, LyricReviewPriorityReasonCode.repeatedWords);
    },
  );

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
        line(
          'this lyric row has many words',
          confidence: 90,
          startMs: 0,
          endMs: 100,
        ),
        line('a long held vocal', startMs: 100, endMs: 25000),
      ],
    );

    final ranked = service.rank(document);

    expect(ranked.map((item) => item.lineIndex), [0, 1]);
    expectReason(
      ranked.first,
      LyricReviewPriorityReasonCode.longTextWithShortInterval,
    );
    expectReason(
      ranked.last,
      LyricReviewPriorityReasonCode.intervalOverTwentySeconds,
    );
  });
  test('does not rank an unscored line as a low-confidence line', () {
    final document = LyricDocument(
      language: 'en',
      lines: [
        line(
          'unscored lyric',
          confidence: 50,
          confidenceSource: LyricConfidenceSource.unscored,
        ),
        line('low confidence', confidence: 50, startMs: 1000, endMs: 2000),
      ],
    );

    final ranked = service.rank(document);

    // Same placeholder number, different meaning: only the line that actually
    // carries an engine score is worth reviewing.
    expect(ranked.single.lineIndex, 1);
    expectReason(
      ranked.single,
      LyricReviewPriorityReasonCode.confidenceLow,
      confidence: 50,
    );
    expect(ranked.map((item) => item.lineIndex), isNot(contains(0)));
  });
}
