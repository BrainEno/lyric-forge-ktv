import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/independent_snapshot_comparison.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricLine line(String text, int start, int end) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: start),
  endTime: Duration(milliseconds: end),
);

LyricDocument doc(List<LyricLine> lines, {Duration? offset}) => LyricDocument(
  language: 'en',
  lines: lines,
  globalOffset: offset,
);

void main() {
  const service = IndependentSnapshotComparison();

  test('exact text is compared between distinct raw segments only', () {
    final primary = doc([line('Same lyric', 100, 1000)]);
    final secondary = doc([line('Same lyric', 200, 900)]);
    final result = service.compare(primary: primary, secondary: secondary);
    expect(result.limitExceeded, isFalse);
    expect(result.rows, hasLength(1));
    final row = result.rows.single;
    expect(row.kind, SnapshotComparisonKind.exactText);
    expect(row.primaryIndex, 0);
    expect(row.secondaryIndex, 0);
    expect(row.primary, same(primary.lines.single));
    expect(row.secondary, same(secondary.lines.single));
  });

  test('whitespace, punctuation, case and Unicode differences are not normalized', () {
    for (final pair in [
      ['hello', 'Hello'],
      ['hello', 'hello '],
      ['hello!', 'hello'],
      ['é', 'e\u0301'],
      ['今夜', '今晚'],
      ['A 🎵', 'A 🎶'],
    ]) {
      final result = service.compare(
        primary: doc([line(pair.first, 0, 100)]),
        secondary: doc([line(pair.last, 0, 100)]),
      );
      expect(result.rows.single.kind, SnapshotComparisonKind.differentText,
          reason: '$pair must remain distinct');
    }
  });

  test('half-open intervals touching at endpoints do not overlap', () {
    final result = service.compare(
      primary: doc([line('a', 0, 100)]),
      secondary: doc([line('a', 100, 200)]),
    );
    expect(result.rows.map((r) => r.kind), [
      SnapshotComparisonKind.primaryOnly,
      SnapshotComparisonKind.secondaryOnly,
    ]);
    expect(result.rows.first.primaryIndex, 0);
    expect(result.rows.first.secondary, isNull);
    expect(result.rows.last.secondaryIndex, 0);
    expect(result.rows.last.primary, isNull);
  });

  test('one millisecond of overlap is a match, without padding', () {
    final result = service.compare(
      primary: doc([line('a', 0, 101)]),
      secondary: doc([line('a', 100, 200)]),
    );
    expect(result.rows.single.kind, SnapshotComparisonKind.exactText);
  });

  test('one primary to many secondary segments is ambiguous on both sides', () {
    final result = service.compare(
      primary: doc([line('hello world', 0, 2000)]),
      secondary: doc([line('hello', 0, 1000), line('world', 1000, 2000)]),
    );
    expect(result.rows, hasLength(3));
    expect(result.rows.every((r) => r.kind == SnapshotComparisonKind.ambiguousOverlap), isTrue);
    expect(result.rows.map((r) => r.primaryIndex), [0, null, null]);
    expect(result.rows.map((r) => r.secondaryIndex), [null, 0, 1]);
  });

  test('one secondary spanning multiple primary segments is ambiguous', () {
    final result = service.compare(
      primary: doc([line('a', 0, 1000), line('b', 1000, 2000)]),
      secondary: doc([line('a', 0, 2000)]),
    );
    expect(result.rows, hasLength(3));
    expect(result.rows.every((r) => r.kind == SnapshotComparisonKind.ambiguousOverlap), isTrue);
    expect(result.rows.last.secondaryIndex, 0);
    expect(result.rows.last.primary, isNull);
  });

  test('many-to-many overlapping raw segments never produce exact matches', () {
    final result = service.compare(
      primary: doc([line('same', 0, 1000), line('same', 500, 1500)]),
      secondary: doc([line('same', 0, 1000), line('same', 500, 1500)]),
    );
    expect(result.rows, hasLength(4));
    expect(result.rows.every((r) => r.kind == SnapshotComparisonKind.ambiguousOverlap), isTrue);
  });

  test('mixed relationships preserve both original index spaces', () {
    final result = service.compare(
      primary: doc([
        line('equal', 0, 100),
        line('old', 200, 300),
        line('alone', 400, 500),
        line('split', 600, 800),
      ]),
      secondary: doc([
        line('equal', 0, 100),
        line('new', 200, 300),
        line('extra', 500, 600),
        line('spl', 600, 700),
        line('it', 700, 800),
      ]),
    );
    expect(result.rows.map((r) => r.kind), [
      SnapshotComparisonKind.exactText,
      SnapshotComparisonKind.differentText,
      SnapshotComparisonKind.primaryOnly,
      SnapshotComparisonKind.ambiguousOverlap,
      SnapshotComparisonKind.secondaryOnly,
      SnapshotComparisonKind.ambiguousOverlap,
      SnapshotComparisonKind.ambiguousOverlap,
    ]);
    expect(result.rows.map((r) => r.primaryIndex), [0, 1, 2, 3, null, null, null]);
    expect(result.rows.map((r) => r.secondaryIndex), [0, 1, null, null, 2, 3, 4]);
  });

  test('empty transcripts yield only the other side or no rows', () {
    expect(service.compare(primary: doc([]), secondary: doc([])).rows, isEmpty);
    expect(
      service.compare(primary: doc([]), secondary: doc([line('b', 0, 1)])).rows.single.kind,
      SnapshotComparisonKind.secondaryOnly,
    );
    expect(
      service.compare(primary: doc([line('a', 0, 1)]), secondary: doc([])).rows.single.kind,
      SnapshotComparisonKind.primaryOnly,
    );
  });

  test('duplicate segments stay ambiguous even when text is identical', () {
    final result = service.compare(
      primary: doc([line('repeat', 0, 10)]),
      secondary: doc([line('repeat', 0, 10), line('repeat', 0, 10)]),
    );
    expect(result.rows, hasLength(3));
    expect(result.rows.every((r) => r.kind == SnapshotComparisonKind.ambiguousOverlap), isTrue);
  });

  test('nonzero offset on either side is not silently ignored', () {
    final original = doc([line('a', 0, 10)]);
    final shifted = doc([line('a', 0, 10)], offset: const Duration(milliseconds: -1));
    for (final pair in [(original, shifted), (shifted, original)]) {
      final result = service.compare(primary: pair.$1, secondary: pair.$2);
      expect(result.limitExceeded, isTrue);
      expect(result.rows, isEmpty);
    }
  });

  test('invalid timestamps and blank text fail closed', () {
    final valid = doc([line('a', 0, 10)]);
    for (final bad in [
      line('a', -1, 10),
      line('a', 10, 10),
      line('a', 11, 10),
      line('  ', 0, 10),
    ]) {
      for (final pair in [(valid, doc([bad])), (doc([bad]), valid)]) {
        final result = service.compare(primary: pair.$1, secondary: pair.$2);
        expect(result.limitExceeded, isTrue);
        expect(result.rows, isEmpty);
      }
    }
  });

  test('limits bound both transcript dimensions', () {
    final many = List.generate(
      IndependentSnapshotComparison.maxLinesPerTranscript + 1,
      (i) => line('line $i', i * 2, i * 2 + 1),
    );
    final valid = doc([line('x', 0, 1)]);
    for (final pair in [(valid, doc(many)), (doc(many), valid)]) {
      final result = service.compare(primary: pair.$1, secondary: pair.$2);
      expect(result.limitExceeded, isTrue);
      expect(result.rows, isEmpty);
    }
    final atLimit = doc(many.take(IndependentSnapshotComparison.maxLinesPerTranscript).toList());
    expect(service.compare(primary: atLimit, secondary: valid).limitExceeded, isFalse);
  });

  test('text budget counts Unicode runes rather than UTF-16 units', () {
    final limit = IndependentSnapshotComparison.maxTextRunesPerLine;
    final within = doc([line('🎵' * limit, 0, 1)]);
    final over = doc([line('🎵' * (limit + 1), 0, 1)]);
    final valid = doc([line('x', 0, 1)]);
    expect(service.compare(primary: within, secondary: valid).limitExceeded, isFalse);
    expect(service.compare(primary: over, secondary: valid).limitExceeded, isTrue);
    expect(service.compare(primary: valid, secondary: over).limitExceeded, isTrue);
  });

  test('the result rows are immutable and input documents are not changed', () {
    final primary = doc([line('old', 0, 100)]);
    final secondary = doc([line('new', 0, 100)]);
    final beforePrimary = primary.toJson();
    final beforeSecondary = secondary.toJson();
    final result = service.compare(primary: primary, secondary: secondary);
    expect(() => result.rows.clear(), throwsUnsupportedError);
    expect(primary.toJson(), beforePrimary);
    expect(secondary.toJson(), beforeSecondary);
  });
}
