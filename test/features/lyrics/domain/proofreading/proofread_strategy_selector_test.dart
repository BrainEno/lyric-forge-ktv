import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';

void main() {
  const selector = ProofreadStrategySelector();

  test('auto selects ASR first when there is no reference', () {
    final decision = selector.select(
      requestedStrategy: LyricSourceStrategy.auto,
      hasReference: false,
    );

    expect(decision.effectiveStrategy, LyricSourceStrategy.asrFirst);
    expect(decision.reason, ProofreadStrategyReason.autoWithoutReference);
    expect(decision.autoFellBackToAsr, isFalse);
    expect(decision.referenceCoverage, isNull);
    expect(decision.notes, {'autoFellBackToAsr': false});
  });

  test('auto falls back to ASR below the configured coverage threshold', () {
    final decision = selector.select(
      requestedStrategy: LyricSourceStrategy.auto,
      hasReference: true,
      referenceCoverage: 0.2499,
    );

    expect(decision.effectiveStrategy, LyricSourceStrategy.asrFirst);
    expect(decision.reason, ProofreadStrategyReason.autoCoverageInsufficient);
    expect(decision.autoFellBackToAsr, isTrue);
    expect(decision.notes, {
      'autoFellBackToAsr': true,
      'referenceCoverage': 0.2499,
    });
  });

  test('coverage equal to the threshold selects reference first', () {
    final decision = selector.select(
      requestedStrategy: LyricSourceStrategy.auto,
      hasReference: true,
      referenceCoverage: 0.25,
    );

    expect(decision.effectiveStrategy, LyricSourceStrategy.referenceFirst);
    expect(decision.reason, ProofreadStrategyReason.autoCoverageSufficient);
    expect(decision.autoFellBackToAsr, isFalse);
    expect(decision.notes, {
      'autoFellBackToAsr': false,
      'referenceCoverage': 0.25,
    });
  });

  test('auto selects reference first above the threshold', () {
    final decision = selector.select(
      requestedStrategy: LyricSourceStrategy.auto,
      hasReference: true,
      referenceCoverage: 0.8,
    );

    expect(decision.effectiveStrategy, LyricSourceStrategy.referenceFirst);
    expect(decision.autoFellBackToAsr, isFalse);
  });

  test('explicit strategy wins over automatic coverage selection', () {
    final referenceFirst = selector.select(
      requestedStrategy: LyricSourceStrategy.referenceFirst,
      hasReference: true,
      referenceCoverage: 0.1,
    );
    final asrFirst = selector.select(
      requestedStrategy: LyricSourceStrategy.asrFirst,
      hasReference: true,
      referenceCoverage: 0.9,
    );

    expect(referenceFirst.effectiveStrategy, LyricSourceStrategy.referenceFirst);
    expect(referenceFirst.autoFellBackToAsr, isFalse);
    expect(asrFirst.effectiveStrategy, LyricSourceStrategy.asrFirst);
    expect(asrFirst.autoFellBackToAsr, isFalse);
    expect(referenceFirst.notes, isEmpty);
    expect(asrFirst.notes, isEmpty);
  });

  test('auto requires coverage when a reference is present', () {
    expect(
      () => selector.select(
        requestedStrategy: LyricSourceStrategy.auto,
        hasReference: true,
      ),
      throwsArgumentError,
    );
  });

  test('reference-first requires reference lyrics', () {
    expect(
      () => selector.select(
        requestedStrategy: LyricSourceStrategy.referenceFirst,
        hasReference: false,
      ),
      throwsArgumentError,
    );
  });

  test('rejects invalid coverage values', () {
    for (final coverage in [-0.01, 1.01, double.nan, double.infinity]) {
      expect(
        () => selector.select(
          requestedStrategy: LyricSourceStrategy.auto,
          hasReference: true,
          referenceCoverage: coverage,
        ),
        throwsArgumentError,
      );
    }
  });
}
