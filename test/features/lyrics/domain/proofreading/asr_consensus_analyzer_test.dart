import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_consensus_analyzer.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const analyzer = AsrConsensusAnalyzer();

  LyricLine line(String text, int startMs, int endMs, {int confidence = 90}) =>
      LyricLine(
        text: text,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs),
        confidence: confidence,
      );

  LyricDocument document(List<LyricLine> lines) =>
      LyricDocument(language: 'en', lines: lines);

  test('classifies aligned equivalent text as agreement without editing either input', () {
    final primaryLine = line('Ashin lady', 1000, 3000);
    final primary = document([primaryLine]);
    final secondary = document([line('ashin lady', 1100, 3100)]);

    final result = analyzer.analyze(primary: primary, secondary: secondary);

    expect(result.rows, hasLength(1));
    expect(result.rows.single.status, AsrConsensusStatus.agreement);
    expect(result.rows.single.textSimilarity, 1);
    expect(result.rows.single.secondaryLineIndices, [0]);
    expect(result.rows.single.secondaryText, 'ashin lady');
    expect(identical(primary.lines.single, primaryLine), isTrue);
    expect(primary.lines.single.startTime, const Duration(seconds: 1));
  });

  test('surfaces borderline lyric disagreements instead of auto-applying the alternative', () {
    final result = analyzer.analyze(
      primary: document([line('Ashin lady', 1000, 3000)]),
      secondary: document([line('passion lady', 1000, 3000)]),
    );

    expect(result.rows.single.status, AsrConsensusStatus.disagreement);
    expect(result.rows.single.textSimilarity, closeTo(0.727, 0.002));
    expect(result.rows.single.secondaryText, 'passion lady');
    expect(result.rows.single.reasons, contains(AsrConsensusReason.textMismatch));
    expect(result.rows.single.primaryLine.text, 'Ashin lady');
  });

  test('joins multiple secondary segments that overlap one primary line', () {
    final result = analyzer.analyze(
      primary: document([line('we are on the road tonight', 0, 4000)]),
      secondary: document([
        line('we are on the', 0, 1800),
        line('road tonight', 1700, 3900),
      ]),
    );

    expect(result.rows.single.secondaryLineIndices, [0, 1]);
    expect(result.rows.single.secondaryText, 'we are on the road tonight');
    expect(result.rows.single.status, AsrConsensusStatus.agreement);
  });

  test('reports a primary-only line and recoverable secondary-only lines', () {
    final result = analyzer.analyze(
      primary: document([line('first lyric', 0, 2000)]),
      secondary: document([line('later lyric', 8000, 10000)]),
    );

    expect(result.rows.single.status, AsrConsensusStatus.primaryOnly);
    expect(result.rows.single.reasons, contains(AsrConsensusReason.noSecondaryOverlap));
    expect(result.secondaryOnlyLines, hasLength(1));
    expect(result.secondaryOnlyLines.single.lineIndex, 0);
    expect(result.secondaryOnlyLines.single.line.text, 'later lyric');
  });

  test('low-confidence primary text remains reviewable even when engines agree', () {
    final result = analyzer.analyze(
      primary: document([line('hello world', 0, 2000, confidence: 40)]),
      secondary: document([line('hello world', 0, 2000, confidence: 95)]),
    );

    expect(result.rows.single.status, AsrConsensusStatus.disagreement);
    expect(result.rows.single.reasons, contains(AsrConsensusReason.lowPrimaryConfidence));
    expect(result.rows.single.textSimilarity, 1);
  });

  test('bounds expensive text comparisons and marks truncated evidence as review', () {
    const bounded = AsrConsensusAnalyzer(maxComparedRunes: 8);
    final result = bounded.analyze(
      primary: document([line('this is a very long primary lyric', 0, 4000)]),
      secondary: document([line('this is a very long alternate lyric', 0, 4000)]),
    );

    expect(result.rows.single.status, AsrConsensusStatus.disagreement);
    expect(result.rows.single.textSimilarity, isNull);
    expect(
      result.rows.single.reasons,
      contains(AsrConsensusReason.comparisonLimitExceeded),
    );
  });

  test('empty inputs produce immutable empty evidence', () {
    final result = analyzer.analyze(
      primary: document(const []),
      secondary: document(const []),
    );

    expect(result.rows, isEmpty);
    expect(result.secondaryOnlyLines, isEmpty);
    expect(() => result.rows.add(throw StateError('not reached')), throwsUnsupportedError);
  });
}
