/// Shared parameters currently consumed by the proofreading pipelines.
/// Similarity and coverage are ratios in [0, 1], not confidence percentages.
class ProofreadConstants {
  const ProofreadConstants._();

  // Anchor lengths and limits are counts, not time or confidence values.
  static const anchorKLatin = 3;
  static const anchorKCjk = 4;
  static const maxOccurrencesPerKey = 12;
  static const maxChainCandidates = 4000;
  static const maxNwCells = 4000000;

  /// Minimum token similarity ratio in [0, 1] for a soft alignment match.
  static const softMatchMinSimilarityRatio = 0.67;

  /// Minimum reference coverage ratio in [0, 1] for automatic reference-first.
  static const autoReferenceCoverageMinRatio = 0.25;
}
