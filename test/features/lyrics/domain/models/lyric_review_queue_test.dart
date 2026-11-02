import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricLine _line(
  String text, {
  int confidence = 95,
  LyricConfidenceSource source = LyricConfidenceSource.model,
  int startSeconds = 0,
  String? id,
}) {
  return LyricLine(
    text: text,
    startTime: Duration(seconds: startSeconds),
    endTime: Duration(seconds: startSeconds + 4),
    confidence: confidence,
    confidenceSource: source,
    id: id,
  );
}

void main() {
  group('unscored documents', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [
        _line(
          '月亮代表我的心',
          confidence: unscoredConfidencePlaceholder,
          source: LyricConfidenceSource.unscored,
        ),
        _line(
          '今天天气真好',
          confidence: unscoredConfidencePlaceholder,
          source: LyricConfidenceSource.unscored,
          startSeconds: 4,
        ),
      ],
    );

    test('reports the missing scores instead of inventing low ones', () {
      final queue = LyricReviewQueue.build(document);

      expect(queue.totalLines, 2);
      expect(queue.scoredLines, 0);
      expect(queue.unscoredLines, 2);
      expect(queue.hasAnyScore, isFalse);
      // The placeholder 50 is below the 70 threshold, but it is not a score.
      expect(queue.lowConfidenceCount, 0);
      expect(queue.canFilterByConfidence, isFalse);
    });

    test('still queues a line when there is structural evidence', () {
      final withEmptyLine = LyricDocument(
        language: 'zh',
        lines: [
          _line(
            '',
            confidence: unscoredConfidencePlaceholder,
            source: LyricConfidenceSource.unscored,
          ),
        ],
      );

      final queue = LyricReviewQueue.build(withEmptyLine);

      expect(queue.needsReviewCount, 1);
      // Structural evidence is not confidence evidence.
      expect(queue.lowConfidenceCount, 0);
    });
  });

  group('scored documents', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [
        _line('月亮代表我的心', confidence: 40),
        _line('今天天气真好', confidence: 95, startSeconds: 4),
        _line('好一朵美丽的茉莉花', confidence: 95, startSeconds: 8),
      ],
    );

    test('one queue drives both counts, so they cannot disagree', () {
      final queue = LyricReviewQueue.build(document);

      expect(queue.needsReviewCount, 1);
      expect(queue.lowConfidenceCount, 1);
      expect(queue.canFilterByConfidence, isTrue);
      expect(queue.unscoredLines, 0);
      // The defining invariant: low confidence is a subset of the queue.
      expect(
        queue.lowConfidenceIndices.difference(queue.indices),
        isEmpty,
      );
    });

    test('a healthy document reports nothing to review', () {
      final healthy = LyricDocument(
        language: 'zh',
        lines: [
          _line('月亮代表我的心'),
          _line('今天天气真好', startSeconds: 4),
        ],
      );

      final queue = LyricReviewQueue.build(healthy);

      expect(queue.needsReviewCount, 0);
      expect(queue.lowConfidenceCount, 0);
      expect(queue.canFilterByConfidence, isTrue);
    });

    test('a reviewed line leaves both the queue and the subset', () {
      const decisions = LyricReviewDecisionService();
      final withIds = LyricDocument(
        language: 'zh',
        lines: [
          _line('月亮代表我的心', confidence: 40, id: 'line-1'),
          _line('今天天气真好', id: 'line-2', startSeconds: 4),
        ],
      );
      expect(LyricReviewQueue.build(withIds).needsReviewCount, 1);

      final reviewed = decisions.setReviewed(withIds, 0, reviewed: true);
      final queue = LyricReviewQueue.build(reviewed);

      expect(queue.reviewedLines, 1);
      expect(queue.needsReviewCount, 0);
      expect(queue.lowConfidenceCount, 0);
    });

    test('the queue is ordered by score so the worst line comes first', () {
      final mixed = LyricDocument(
        language: 'zh',
        lines: [
          _line('月亮代表我的心', confidence: 62),
          _line('今天天气真好', confidence: 20, startSeconds: 4),
          _line('好一朵美丽的茉莉花', confidence: 95, startSeconds: 8),
        ],
      );

      final queue = LyricReviewQueue.build(mixed);

      expect(queue.needsReviewCount, 2);
      expect(queue.items.first.lineIndex, 1);
      expect(queue.items.first.score, greaterThan(queue.items.last.score));
    });
  });

  test('lookups agree with the counters', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [
        _line('月亮代表我的心', confidence: 30),
        _line('今天天气真好', confidence: 95, startSeconds: 4),
      ],
    );

    final queue = LyricReviewQueue.build(document);

    expect(queue.needsReview(0), isTrue);
    expect(queue.isLowConfidence(0), isTrue);
    expect(queue.needsReview(1), isFalse);
    expect(queue.isLowConfidence(1), isFalse);
    expect(queue.byIndex.length, queue.needsReviewCount);
  });
}
