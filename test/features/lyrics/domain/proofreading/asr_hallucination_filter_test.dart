import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_consensus_analyzer.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_hallucination_filter.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const filter = AsrHallucinationCandidateFilter();

  LyricLine line(String text, int start, int end, {int confidence = 90}) => LyricLine(
    text: text,
    startTime: Duration(milliseconds: start),
    endTime: Duration(milliseconds: end),
    confidence: confidence,
  );

  AsrConsensusRow primaryOnly(LyricLine source, int index) => AsrConsensusRow(
    primaryIndex: index,
    primaryLine: source,
    secondaryLineIndices: const [],
    secondaryText: null,
    secondaryConfidence: null,
    textSimilarity: null,
    status: AsrConsensusStatus.primaryOnly,
    reasons: const {AsrConsensusReason.noSecondaryOverlap},
  );

  AsrConsensusResult evidence({
    required List<AsrConsensusRow> rows,
    List<AsrConsensusSecondaryOnlyLine> secondaryOnly = const [],
  }) => AsrConsensusResult(rows: rows, secondaryOnlyLines: secondaryOnly);

  test('returns a low-confidence primary-only line as a review candidate', () {
    final source = line('strange words in the silence', 1000, 2600, confidence: 35);
    final result = filter.analyze(evidence(rows: [primaryOnly(source, 2)]));

    expect(result.candidates, hasLength(1));
    final candidate = result.candidates.single;
    expect(candidate.primaryIndex, 2);
    expect(candidate.line, same(source));
    expect(candidate.reasons, contains(AsrHallucinationReason.lowConfidence));
    expect(candidate.reasons, contains(AsrHallucinationReason.noSecondaryOverlap));
    expect(source.text, 'strange words in the silence');
    expect(source.startTime, const Duration(milliseconds: 1000));
    expect(source.endTime, const Duration(milliseconds: 2600));
  });

  test('does not flag a high-confidence line that lacks secondary overlap', () {
    final result = filter.analyze(
      evidence(rows: [primaryOnly(line('unusual line', 1000, 2500), 0)]),
    );

    expect(result.candidates, isEmpty);
  });

  test('does not classify text disagreement with overlapping support as hallucination', () {
    final source = line('I see the morning', 1000, 3000, confidence: 25);
    final row = AsrConsensusRow(
      primaryIndex: 0,
      primaryLine: source,
      secondaryLineIndices: const [0],
      secondaryText: 'I see the evening',
      secondaryConfidence: 95,
      textSimilarity: 0.7,
      status: AsrConsensusStatus.disagreement,
      reasons: const {AsrConsensusReason.textMismatch, AsrConsensusReason.lowPrimaryConfidence},
    );

    expect(filter.analyze(evidence(rows: [row])).candidates, isEmpty);
  });

  test('holds a candidate when a secondary-only line is temporally nearby', () {
    final source = line('unconfirmed phrase', 1000, 2000, confidence: 25);
    final nearby = line('maybe this phrase', 2600, 3800);
    final result = filter.analyze(
      evidence(
        rows: [primaryOnly(source, 0)],
        secondaryOnly: [AsrConsensusSecondaryOnlyLine(lineIndex: 1, line: nearby)],
      ),
    );

    expect(result.candidates, isEmpty);
  });

  test('keeps a candidate when secondary-only evidence is temporally distant', () {
    final source = line('unconfirmed phrase', 1000, 2000, confidence: 25);
    final distant = line('later verse', 8000, 9500);
    final result = filter.analyze(
      evidence(
        rows: [primaryOnly(source, 0)],
        secondaryOnly: [AsrConsensusSecondaryOnlyLine(lineIndex: 1, line: distant)],
      ),
    );

    expect(result.candidates, hasLength(1));
  });

  test('uses configurable confidence and nearby-time thresholds', () {
    const strict = AsrHallucinationCandidateFilter(
      lowConfidenceThreshold: 40,
      nearbySecondaryTolerance: Duration(milliseconds: 250),
    );
    final source = line('unconfirmed phrase', 1000, 2000, confidence: 35);
    final nearby = line('different phrase', 2350, 3500);
    final result = strict.analyze(
      evidence(
        rows: [primaryOnly(source, 0)],
        secondaryOnly: [AsrConsensusSecondaryOnlyLine(lineIndex: 1, line: nearby)],
      ),
    );

    expect(result.candidates, hasLength(1));
  });

  test('skips empty normalized text and exposes immutable candidates', () {
    final blank = primaryOnly(line('…', 1000, 2000, confidence: 10), 0);
    final candidateRow = primaryOnly(
      line('unconfirmed phrase', 5000, 6500, confidence: 20),
      1,
    );
    final result = filter.analyze(evidence(rows: [blank, candidateRow]));

    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.primaryIndex, 1);
    expect(() => result.candidates.add(result.candidates.single), throwsUnsupportedError);
    expect(
      () => result.candidates.single.reasons.add(AsrHallucinationReason.lowConfidence),
      throwsUnsupportedError,
    );
  });
}
