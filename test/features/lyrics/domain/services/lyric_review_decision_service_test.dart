import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const service = LyricReviewDecisionService();
  final reviewedAt = DateTime.utc(2026, 10, 21, 17);

  LyricLine line(
    String id,
    String text, {
    int startMs = 1000,
    int endMs = 2000,
  }) => LyricLine(
    id: id,
    text: text,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: endMs),
  );

  test('records a reviewed decision by stable ID and restores it by current index', () {
    final document = LyricDocument(
      language: 'en',
      lines: [line('line-a', 'first'), line('line-b', 'second', startMs: 2000, endMs: 3000)],
    );
    final reviewed = service.setReviewed(
      document,
      0,
      reviewed: true,
      reviewedAt: reviewedAt,
    );

    expect(service.isReviewed(reviewed, 0), isTrue);
    expect(service.isReviewed(reviewed, 1), isFalse);
    expect(
      (reviewed.metadata[LyricReviewDecisionService.metadataKey] as Map)['line-a']['reviewedAt'],
      reviewedAt.toIso8601String(),
    );

    final reordered = reviewed.copyWith(lines: [reviewed.lines[1], reviewed.lines[0]]);
    expect(service.isReviewed(reordered, 0), isFalse);
    expect(service.isReviewed(reordered, 1), isTrue);
  });

  test('text or timing changes invalidate a review decision automatically', () {
    final document = LyricDocument(
      language: 'en',
      lines: [line('stable-id', 'original')],
    );
    final reviewed = service.setReviewed(document, 0, reviewed: true);

    final editedText = reviewed.copyWith(
      lines: [reviewed.lines.single.copyWith(text: 'corrected')],
    );
    expect(service.isReviewed(editedText, 0), isFalse);

    final editedTiming = reviewed.copyWith(
      lines: [
        reviewed.lines.single.copyWith(
          endTime: const Duration(milliseconds: 2200),
        ),
      ],
    );
    expect(service.isReviewed(editedTiming, 0), isFalse);
  });

  test('can explicitly clear a decision and leaves the input immutable', () {
    final document = LyricDocument(
      language: 'en',
      lines: [line('line-a', 'first')],
    );
    final reviewed = service.setReviewed(document, 0, reviewed: true);
    final cleared = service.setReviewed(reviewed, 0, reviewed: false);

    expect(service.isReviewed(reviewed, 0), isTrue);
    expect(service.isReviewed(cleared, 0), isFalse);
    expect(cleared.metadata.containsKey(LyricReviewDecisionService.metadataKey), isFalse);
    expect(document.metadata.containsKey(LyricReviewDecisionService.metadataKey), isFalse);
  });

  test('invalid index, missing stable ID and malformed metadata are safe', () {
    const missingId = LyricLine(
      text: 'no id',
      startTime: Duration(seconds: 1),
      endTime: Duration(seconds: 2),
    );
    final document = LyricDocument(
      language: 'en',
      lines: [missingId],
      metadata: const {LyricReviewDecisionService.metadataKey: 'corrupt'},
    );

    expect(service.isReviewed(document, 0), isFalse);
    expect(service.isReviewed(document, -1), isFalse);
    expect(service.isReviewed(document, 1), isFalse);
    expect(service.setReviewed(document, 0, reviewed: true), same(document));
    expect(service.reviewedIndices(document), isEmpty);
  });

  test('ignores unknown keys in legacy or malformed review records', () {
    final first = line('line-a', 'first');
    final document = LyricDocument(
      language: 'en',
      lines: [first, line('line-b', 'second', startMs: 2000, endMs: 3000)],
      metadata: {
        LyricReviewDecisionService.metadataKey: {
          'line-a': {
            'fingerprint': service.fingerprint(first),
            'reviewedAt': reviewedAt.toIso8601String(),
            42: 'unknown legacy value',
          },
        },
      },
    );

    final updated = service.setReviewed(
      document,
      1,
      reviewed: true,
      reviewedAt: reviewedAt,
    );

    expect(service.isReviewed(updated, 0), isTrue);
    expect(service.isReviewed(updated, 1), isTrue);
  });

  test('stale decisions are pruned when the same line is re-reviewed', () {
    final document = LyricDocument(
      language: 'en',
      lines: [line('line-a', 'first'), line('line-b', 'second', startMs: 2000, endMs: 3000)],
    );
    final reviewed = service.setReviewed(document, 0, reviewed: true);
    final changed = reviewed.copyWith(
      lines: [reviewed.lines[0].copyWith(text: 'edited'), reviewed.lines[1]],
    );
    final next = service.setReviewed(changed, 1, reviewed: true);

    final decisions = next.metadata[LyricReviewDecisionService.metadataKey] as Map;
    expect(decisions.keys, ['line-b']);
  });
}
