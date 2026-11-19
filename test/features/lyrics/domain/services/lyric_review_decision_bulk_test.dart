import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

const _service = LyricReviewDecisionService();
const _key = LyricReviewDecisionService.metadataKey;

LyricLine _line(String? id, String text, {int start = 0, int confidence = 30}) {
  return LyricLine(
    id: id,
    text: text,
    startTime: Duration(seconds: start),
    endTime: Duration(seconds: start + 3),
    confidence: confidence,
  );
}

LyricDocument _document(List<LyricLine> lines) =>
    LyricDocument(language: 'zh', lines: lines);

Map<String, dynamic> _decisions(LyricDocument document) =>
    Map<String, dynamic>.from(document.metadata[_key] as Map);

void main() {
  final earlier = DateTime.utc(2026, 11, 1, 8);
  final now = DateTime.utc(2026, 11, 25, 12);

  test('marks every line with an ID reviewed', () {
    final document = _document([
      _line('a', '第一行'),
      _line('b', '第二行', start: 3),
      _line('c', '第三行', start: 6),
    ]);

    final reviewed = _service.setAllReviewed(document, reviewedAt: now);

    expect(_service.reviewedIndices(reviewed), {0, 1, 2});
    expect(_decisions(reviewed).keys, unorderedEquals(['a', 'b', 'c']));
    expect(_decisions(reviewed)['b']['reviewedAt'], now.toIso8601String());
  });

  test('empties the review queue', () {
    final document = _document([
      _line('a', '第一行', confidence: 20),
      _line('b', '第二行', start: 3, confidence: 40),
    ]);
    expect(LyricReviewQueue.build(document).needsReviewCount, greaterThan(0));

    final reviewed = _service.setAllReviewed(document, reviewedAt: now);
    final queue = LyricReviewQueue.build(reviewed);

    expect(queue.needsReviewCount, 0);
    expect(queue.reviewedLines, 2);
  });

  test('keeps the timestamp of lines confirmed earlier', () {
    final document = _service.setReviewed(
      _document([_line('a', '第一行'), _line('b', '第二行', start: 3)]),
      0,
      reviewed: true,
      reviewedAt: earlier,
    );

    final reviewed = _service.setAllReviewed(document, reviewedAt: now);

    expect(_decisions(reviewed)['a']['reviewedAt'], earlier.toIso8601String());
    expect(_decisions(reviewed)['b']['reviewedAt'], now.toIso8601String());
  });

  test('re-confirms a line edited since its decision', () {
    final document = _service.setReviewed(
      _document([_line('a', '旧的文字')]),
      0,
      reviewed: true,
      reviewedAt: earlier,
    );
    final edited = document.copyWith(lines: [_line('a', '新的文字')]);
    expect(_service.reviewedIndices(edited), isEmpty);

    final reviewed = _service.setAllReviewed(edited, reviewedAt: now);

    expect(_service.reviewedIndices(reviewed), {0});
    expect(_decisions(reviewed)['a']['reviewedAt'], now.toIso8601String());
  });

  test('drops decisions for lines that no longer exist', () {
    final document = _service.setReviewed(
      _document([_line('gone', '删掉的行'), _line('a', '留下的行', start: 3)]),
      0,
      reviewed: true,
      reviewedAt: earlier,
    );
    final trimmed = document.copyWith(lines: [document.lines[1]]);

    final reviewed = _service.setAllReviewed(trimmed, reviewedAt: now);

    expect(_decisions(reviewed).keys, ['a']);
  });

  test('skips lines without an ID', () {
    final document = _document([_line(null, '旧数据'), _line('b', '第二行')]);

    final reviewed = _service.setAllReviewed(document, reviewedAt: now);

    expect(_service.reviewedIndices(reviewed), {1});
  });

  test('returns the same document when nothing changes', () {
    final once = _service.setAllReviewed(
      _document([_line('a', '第一行'), _line('b', '第二行', start: 3)]),
      reviewedAt: earlier,
    );

    final twice = _service.setAllReviewed(once, reviewedAt: now);
    expect(identical(twice, once), isTrue);

    final noIds = _document([_line(null, '旧数据')]);
    expect(identical(_service.setAllReviewed(noIds), noIds), isTrue);
  });

  test('keeps other metadata', () {
    final document = _document([
      _line('a', '第一行'),
    ]).copyWith(metadata: {'source': 'qwen'});

    final reviewed = _service.setAllReviewed(document, reviewedAt: now);

    expect(reviewed.metadata['source'], 'qwen');
    expect(reviewed.metadata.containsKey(_key), isTrue);
  });
}
