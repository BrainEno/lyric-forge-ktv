class ProofreadConstants {
  const ProofreadConstants._();

  // 分行
  static const gapSplitSec = 0.8;
  static const maxLineDurationSec = 8.0;
  static const maxTokensLatin = 14;
  static const maxTokensCjk = 24;
  static const minSegmentSec = 0.6;
  static const mergeGapMaxSec = 1.2;
  // 输出行
  static const minLineOutputSec = 0.30;
  static const leadSec = 0.10;
  static const maxLineSec = 12.0;
  static const maxTokensPerSecLatin = 8.0;
  static const maxTokensPerSecCjk = 10.0;
  // 对齐
  static const anchorKLatin = 3;
  static const anchorKCjk = 4;
  static const maxOccurrencesPerKey = 12;
  static const maxChainCandidates = 4000;
  static const softMatchMinSim = 0.67;
  static const maxNwCells = 4000000;
  // 策略与判定
  static const autoRefCoverageMin = 0.25;
  static const agreementGreenMin = 0.35;
  static const agreementLowMax = 0.30;
  static const asrConfGreenMin = 0.60;
  static const minVocalOverlap = 0.20;
  static const gopGreen = -1.0;
  static const gopGrey = -3.0;
  static const confidenceGreen = 85;
  static const confidenceAmber = 60;
  // 幻觉与重复
  static const loopMinRepeats = 4;
  static const loopMaxConfidence = 0.6;
  static const repetitionClusterSim = 0.6;
  static const repetitionFixMaxConf = 0.75;
  static const consensusTimeGateSec = 3.0;
  // 外部端口
  static const alignerMaxWindowSec = 290.0;
  static const trailingSecPerToken = 0.6;
}
