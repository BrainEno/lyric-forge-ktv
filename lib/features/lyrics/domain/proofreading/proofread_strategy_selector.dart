import 'proofread_constants.dart';

enum LyricSourceStrategy { referenceFirst, asrFirst, auto }

enum ProofreadStrategyReason {
  explicitReferenceFirst,
  explicitAsrFirst,
  autoWithoutReference,
  autoCoverageSufficient,
  autoCoverageInsufficient,
}

class ProofreadStrategyDecision {
  final LyricSourceStrategy requestedStrategy;
  final LyricSourceStrategy effectiveStrategy;
  final ProofreadStrategyReason reason;
  final double? referenceCoverage;
  final bool autoFellBackToAsr;
  final Map<String, Object> notes;

  ProofreadStrategyDecision({
    required this.requestedStrategy,
    required this.effectiveStrategy,
    required this.reason,
    required this.referenceCoverage,
    required this.autoFellBackToAsr,
    required Map<String, Object> notes,
  }) : notes = Map.unmodifiable(notes);
}

/// Selects a proofreading pipeline without running or mutating either pipeline.
class ProofreadStrategySelector {
  const ProofreadStrategySelector();

  ProofreadStrategyDecision select({
    required LyricSourceStrategy requestedStrategy,
    required bool hasReference,
    double? referenceCoverage,
  }) {
    _validateCoverage(referenceCoverage);

    switch (requestedStrategy) {
      case LyricSourceStrategy.referenceFirst:
        if (!hasReference) {
          throw ArgumentError.value(
            hasReference,
            'hasReference',
            'referenceFirst requires reference lyrics',
          );
        }
        return ProofreadStrategyDecision(
          requestedStrategy: requestedStrategy,
          effectiveStrategy: LyricSourceStrategy.referenceFirst,
          reason: ProofreadStrategyReason.explicitReferenceFirst,
          referenceCoverage: referenceCoverage,
          autoFellBackToAsr: false,
          notes: const {},
        );
      case LyricSourceStrategy.asrFirst:
        return ProofreadStrategyDecision(
          requestedStrategy: requestedStrategy,
          effectiveStrategy: LyricSourceStrategy.asrFirst,
          reason: ProofreadStrategyReason.explicitAsrFirst,
          referenceCoverage: referenceCoverage,
          autoFellBackToAsr: false,
          notes: const {},
        );
      case LyricSourceStrategy.auto:
        if (!hasReference) {
          return ProofreadStrategyDecision(
            requestedStrategy: requestedStrategy,
            effectiveStrategy: LyricSourceStrategy.asrFirst,
            reason: ProofreadStrategyReason.autoWithoutReference,
            referenceCoverage: null,
            autoFellBackToAsr: false,
            notes: const {'autoFellBackToAsr': false},
          );
        }
        if (referenceCoverage == null) {
          throw ArgumentError(
            'referenceCoverage is required when auto has reference lyrics',
          );
        }
        final fellBack =
            referenceCoverage < ProofreadConstants.autoRefCoverageMin;
        return ProofreadStrategyDecision(
          requestedStrategy: requestedStrategy,
          effectiveStrategy: fellBack
              ? LyricSourceStrategy.asrFirst
              : LyricSourceStrategy.referenceFirst,
          reason: fellBack
              ? ProofreadStrategyReason.autoCoverageInsufficient
              : ProofreadStrategyReason.autoCoverageSufficient,
          referenceCoverage: referenceCoverage,
          autoFellBackToAsr: fellBack,
          notes: {
            'autoFellBackToAsr': fellBack,
            'referenceCoverage': referenceCoverage,
          },
        );
    }
  }

  void _validateCoverage(double? referenceCoverage) {
    if (referenceCoverage == null) return;
    if (!referenceCoverage.isFinite ||
        referenceCoverage < 0 ||
        referenceCoverage > 1) {
      throw ArgumentError.value(
        referenceCoverage,
        'referenceCoverage',
        'must be finite and between 0 and 1',
      );
    }
  }
}
