import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_consensus_analyzer.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_repetition_analyzer.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const analyzer = AsrRepetitionAnalyzer();

  LyricLine line(String text, {int confidence = 95}) => LyricLine(
    text: text,
    startTime: const Duration(seconds: 1),
    endTime: const Duration(seconds: 4),
    confidence: confidence,
  );

  AsrConsensusResult evidence({
    required String primary,
    required String secondary,
    int primaryConfidence = 95,
    int secondaryConfidence = 95,
  }) => AsrConsensusResult(
    rows: [
      AsrConsensusRow(
        primaryIndex: 0,
        primaryLine: line(primary, confidence: primaryConfidence),
        secondaryLineIndices: const [0],
        secondaryText: secondary,
        secondaryConfidence: secondaryConfidence,
        textSimilarity: 0.6,
        status: AsrConsensusStatus.disagreement,
        reasons: const {AsrConsensusReason.textMismatch},
      ),
    ],
    secondaryOnlyLines: const [],
  );

  test('suggests the non-repeated alternative when primary duplicates a phrase', () {
    final result = analyzer.analyze(
      evidence(
        primary: 'we are on the road we are on the road tonight',
        secondary: 'we are on the road tonight',
      ),
    );

    expect(result.suggestions, hasLength(1));
    final suggestion = result.suggestions.single;
    expect(suggestion.primaryIndex, 0);
    expect(suggestion.suspectSide, AsrRepetitionSide.primary);
    expect(() => result.suggestions.add(suggestion), throwsUnsupportedError);
    expect(suggestion.originalText, 'we are on the road we are on the road tonight');
    expect(suggestion.suggestedText, 'we are on the road tonight');
    expect(suggestion.repeatedUnitNormalized, 'weareontheroad');
  });

  test('detects repeated CJK text after punctuation and spacing normalization', () {
    final result = analyzer.analyze(
      evidence(primary: '我想回家，我想回家了', secondary: '我想回家了'),
    );

    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.single.suspectSide, AsrRepetitionSide.primary);
    expect(result.suggestions.single.suggestedText, '我想回家了');
  });

  test('also surfaces a repeated secondary transcript without auto-applying primary text', () {
    final result = analyzer.analyze(
      evidence(primary: 'we are home', secondary: 'we are home, we are home'),
    );

    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.single.suspectSide, AsrRepetitionSide.secondary);
    expect(result.suggestions.single.originalText, 'we are home, we are home');
    expect(result.suggestions.single.suggestedText, 'we are home');
  });

  test('does not suggest cleanup when either engine has low confidence', () {
    final cases = [
      evidence(
        primary: 'we are home we are home',
        secondary: 'we are home',
        primaryConfidence: 50,
      ),
      evidence(
        primary: 'we are home we are home',
        secondary: 'we are home',
        secondaryConfidence: 50,
      ),
    ];
    expect(
      cases.every((item) => analyzer.analyze(item).suggestions.isEmpty),
      isTrue,
    );
  });

  test('does not infer repetition from shared repeats, unrelated text, or oversized input', () {
    final sharedRepeat = analyzer.analyze(
      evidence(
        primary: 'we are home we are home',
        secondary: 'we are home we are home',
      ),
    );
    final unrelated = analyzer.analyze(
      evidence(primary: 'meet me in the morning', secondary: 'see you tonight'),
    );
    const bounded = AsrRepetitionAnalyzer(maxComparedRunes: 12);
    final oversized = bounded.analyze(
      evidence(
        primary: 'we are home we are home and then some',
        secondary: 'we are home and then some',
      ),
    );

    expect(
      [sharedRepeat, unrelated, oversized].every((item) => item.suggestions.isEmpty),
      isTrue,
    );
  });
}