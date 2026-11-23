import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_indexed_review_metadata.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_line_batch_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricDocument _document(int count, {Map<String, dynamic> metadata = const {}}) {
  return LyricDocument(
    language: 'zh',
    metadata: metadata,
    lines: [
      for (var index = 0; index < count; index++)
        LyricLine(
          id: 'l$index',
          text: '第$index句',
          startTime: Duration(seconds: index * 4 + 1),
          endTime: Duration(seconds: index * 4 + 3),
        ),
    ],
  );
}

List<String> _texts(LyricDocument document) => [
  for (final line in document.lines) line.text,
];

void main() {
  const service = LyricLineBatchService();

  group('row helpers', () {
    test('normalize sorts, drops repeats and rows outside the song', () {
      expect(LyricLineBatchService.normalize(_document(4), [3, 1, 3, -1, 9]), [
        1,
        3,
      ]);
    });

    test('contiguous rows and runs', () {
      expect(LyricLineBatchService.isContiguous([2, 3, 4]), isTrue);
      expect(LyricLineBatchService.isContiguous([2, 4]), isFalse);
      expect(LyricLineBatchService.runs([0, 1, 3, 5, 6]), [
        [0, 1],
        [3],
        [5, 6],
      ]);
    });
  });

  group('delete', () {
    test('removes rows that are not next to each other', () {
      final result = service.delete(_document(5), [3, 1]);
      expect(_texts(result), ['第0句', '第2句', '第4句']);
    });

    test('keeps engine candidates on the rows that remain', () {
      final document = _document(
        5,
        metadata: {
          LyricIndexedReviewMetadata.candidatesKey: [
            {'lineIndex': 1, 'text': 'gone'},
            {'lineIndex': 4, 'text': 'kept'},
          ],
        },
      );
      final result = service.delete(document, [0, 1]);
      final candidates =
          result.metadata[LyricIndexedReviewMetadata.candidatesKey] as List;
      expect(candidates, hasLength(1));
      expect((candidates.single as Map)['lineIndex'], 2);
      expect((candidates.single as Map)['text'], 'kept');
    });
  });

  group('merge', () {
    test('joins neighbours into the first row, keeping its id', () {
      final result = service.merge(_document(5), [1, 2, 3])!;
      expect(_texts(result), ['第0句', '第1句第2句第3句', '第4句']);
      expect(result.lines[1].id, 'l1');
      expect(result.lines[1].startTime, const Duration(seconds: 5));
      expect(result.lines[1].endTime, const Duration(seconds: 15));
    });

    test('refuses rows with a gap, or a single row', () {
      expect(service.merge(_document(5), [1, 3]), isNull);
      expect(service.merge(_document(5), [2]), isNull);
    });
  });

  group('shift', () {
    test('moves only the chosen rows, also across a gap', () {
      final result = service.shift(_document(4), [
        0,
        2,
      ], const Duration(milliseconds: 500));
      final lines = result.document!.lines;
      expect(result.changedCount, 2);
      expect(lines[0].startTime, const Duration(milliseconds: 1500));
      expect(lines[1].startTime, const Duration(seconds: 5));
      expect(lines[2].startTime, const Duration(milliseconds: 9500));
      expect(lines[2].endTime, const Duration(milliseconds: 11500));
    });

    test('holds a row at 0:00 and counts it', () {
      final result = service.shift(_document(2), [
        0,
      ], const Duration(seconds: -3));
      expect(result.document!.lines.first.startTime, Duration.zero);
      expect(result.clampedCount, 1);
    });

    test('reports an overlap it creates', () {
      // Row 0 ends at 3 s and row 1 starts at 5 s: 2.5 s later they overlap.
      final result = service.shift(_document(2), [
        0,
      ], const Duration(milliseconds: 2500));
      expect(result.introducedIssues, isNotEmpty);
    });

    test('changes nothing for a zero offset or no rows', () {
      expect(service.shift(_document(2), [0], Duration.zero).isSuccess, false);
      expect(
        service.shift(_document(2), [], const Duration(seconds: 1)).isSuccess,
        isFalse,
      );
    });
  });
}
