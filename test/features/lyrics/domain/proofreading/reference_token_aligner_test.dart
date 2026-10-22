import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_token_aligner.dart';

void main() {
  const aligner = ReferenceTokenAligner();

  test('aligns tokens in order across a draft-only insertion', () {
    final result = aligner.align(
      referenceText: 'we are on the road tonight',
      draftText: 'we are driving on the road tonight',
    );

    expect(result.referenceTokenCount, 6);
    expect(result.referenceCoverage, 1);
    expect(result.anchorCount, greaterThan(0));
    expect(result.candidateLimitReached, isFalse);
    expect(
      result.matches.map((match) => '${match.referenceIndex}:${match.draftIndex}'),
      ['0:0', '1:1', '2:3', '3:4', '4:5', '5:6'],
    );
  });

  test('soft token matches above the configured floor contribute to coverage', () {
    final result = aligner.align(
      referenceText: 'hello world',
      draftText: 'hallo world',
    );

    expect(result.referenceCoverage, 1);
    expect(result.anchorCount, 0);
    expect(result.matches.first.similarity, greaterThan(0.67));
  });

  test('repeated chorus text remains in a monotonic alignment', () {
    final result = aligner.align(
      referenceText: 'oh oh oh oh',
      draftText: 'oh oh oh oh',
    );

    expect(result.referenceCoverage, 1);
    expect(result.anchorCount, 0);
    expect(result.matches.map((match) => match.draftIndex), [0, 1, 2, 3]);
  });

  test('CJK reference text can form a unique four-token anchor', () {
    final result = aligner.align(
      referenceText: '我在这里等你',
      draftText: '我在这里等你',
    );

    expect(result.anchorCount, greaterThan(0));
    expect(result.referenceCoverage, 1);
    expect(
      result.matches.where((match) => match.isAnchor).length,
      greaterThanOrEqualTo(4),
    );
  });

  test('no matches and an empty reference both have zero coverage', () {
    final unmatched = aligner.align(
      referenceText: 'one two three four',
      draftText: 'completely different',
    );
    final empty = aligner.align(
      referenceText: '',
      draftText: 'hello world',
    );

    expect(unmatched.referenceCoverage, 0);
    expect(empty.referenceTokenCount, 0);
    expect(empty.referenceCoverage, 0);
    expect(empty.matches, isEmpty);
  });

  test('oversized DP input is bounded and reports degraded coverage', () {
    final repeatedText = List<String>.filled(2000, 'oh').join(' ');
    final result = aligner.align(
      referenceText: repeatedText,
      draftText: repeatedText,
    );

    expect(result.dpBudgetExceeded, isTrue);
    expect(result.anchorCount, 0);
    expect(result.referenceCoverage, 0);
  });
}
