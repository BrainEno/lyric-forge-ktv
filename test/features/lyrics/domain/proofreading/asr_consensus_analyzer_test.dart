import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_consensus_analyzer.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const analyzer = AsrConsensusAnalyzer();

  LyricLine line(
    String text,
    int start,
    int end, {
    int confidence = 90,
    LyricConfidenceSource confidenceSource = LyricConfidenceSource.model,
  }) => LyricLine(
    text: text, startTime: Duration(milliseconds: start),
    endTime: Duration(milliseconds: end),
    confidence: confidence,
    confidenceSource: confidenceSource,
  );
  LyricDocument doc(List<LyricLine> lines) => LyricDocument(language: 'en', lines: lines);

  test('classifies equivalent text as agreement without editing either input', () {
    final source = line('Ashin lady', 1000, 3000);
    final primary = doc([source]);
    final result = analyzer.analyze(
      primary: primary, secondary: doc([line('ashin lady', 1100, 3100)]),
    );
    expect(result.rows.single.status, AsrConsensusStatus.agreement);
    expect(result.rows.single.textSimilarity, 1);
    expect(result.rows.single.secondaryLineIndices, [0]);
    expect(result.rows.single.secondaryText, 'ashin lady');
    expect(identical(primary.lines.single, source), isTrue);
    expect(source.startTime, const Duration(seconds: 1));
    expect(() => result.rows.add(result.rows.single), throwsUnsupportedError);
    expect(() => result.rows.single.secondaryLineIndices.add(1), throwsUnsupportedError);
  });

  test('surfaces borderline disagreements instead of applying alternative text', () {
    final result = analyzer.analyze(
      primary: doc([line('Ashin lady', 1000, 3000)]),
      secondary: doc([line('passion lady', 1000, 3000)]),
    );
    expect(result.rows.single.status, AsrConsensusStatus.disagreement);
    expect(result.rows.single.textSimilarity, closeTo(0.727, 0.002));
    expect(result.rows.single.secondaryText, 'passion lady');
    expect(result.rows.single.reasons, contains(AsrConsensusReason.textMismatch));
    expect(result.rows.single.primaryLine.text, 'Ashin lady');
  });

  test('joins secondary segments that overlap one primary phrase', () {
    final result = analyzer.analyze(
      primary: doc([line('we are on the road tonight', 0, 4000)]),
      secondary: doc([
        line('we are on the', 0, 1800),
        line('road tonight', 1700, 3900),
      ]),
    );
    expect(result.rows.single.secondaryLineIndices, [0, 1]);
    expect(result.rows.single.secondaryText, 'we are on the road tonight');
    expect(result.rows.single.status, AsrConsensusStatus.agreement);
  });

  test('reports primary-only and recoverable secondary-only lines', () {
    final result = analyzer.analyze(
      primary: doc([line('first lyric', 0, 2000)]),
      secondary: doc([line('later lyric', 8000, 10000)]),
    );
    expect(result.rows.single.status, AsrConsensusStatus.primaryOnly);
    expect(result.rows.single.reasons, contains(AsrConsensusReason.noSecondaryOverlap));
    expect(result.secondaryOnlyLines, hasLength(1));
    expect(result.secondaryOnlyLines.single.lineIndex, 0);
    expect(result.secondaryOnlyLines.single.line.text, 'later lyric');
  });

  test('low confidence on either engine keeps matching text in review', () {
    final result = analyzer.analyze(
      primary: doc([line('hello world', 0, 2000, confidence: 40)]),
      secondary: doc([line('hello world', 0, 2000, confidence: 50)]),
    );
    expect(result.rows.single.status, AsrConsensusStatus.disagreement);
    expect(result.rows.single.reasons, contains(AsrConsensusReason.lowPrimaryConfidence));
    expect(result.rows.single.reasons, contains(AsrConsensusReason.lowSecondaryConfidence));
    expect(result.rows.single.textSimilarity, 1);
  });

  test('bounds expensive text comparisons and marks the evidence for review', () {
    const bounded = AsrConsensusAnalyzer(maxComparedRunes: 8);
    final result = bounded.analyze(
      primary: doc([line('this is a very long primary lyric', 0, 4000)]),
      secondary: doc([line('this is a very long alternate lyric', 0, 4000)]),
    );
    expect(result.rows.single.status, AsrConsensusStatus.disagreement);
    expect(result.rows.single.textSimilarity, isNull);
    expect(result.rows.single.reasons, contains(AsrConsensusReason.comparisonLimitExceeded));
  });

  test('empty transcripts produce empty evidence', () {
    final result = analyzer.analyze(primary: doc(const []), secondary: doc(const []));
    expect(result.rows, isEmpty);
    expect(result.secondaryOnlyLines, isEmpty);
    expect(result.hasDisagreements, isFalse);
  });
  test('unscored engines are not reported as low confidence', () {
    final result = analyzer.analyze(
      primary: doc([
        line(
          'hello world',
          0,
          2000,
          confidence: 50,
          confidenceSource: LyricConfidenceSource.unscored,
        ),
      ]),
      secondary: doc([
        line(
          'hello world',
          0,
          2000,
          confidence: 50,
          confidenceSource: LyricConfidenceSource.unscored,
        ),
      ]),
    );

    expect(result.rows.single.status, AsrConsensusStatus.agreement);
    expect(result.rows.single.reasons, isEmpty);
    expect(
      result.rows.single.secondaryConfidence,
      isNull,
      reason: '没有分数就不要算出一个平均分',
    );
  });

}
