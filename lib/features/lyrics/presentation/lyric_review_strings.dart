import '../domain/proofreading/forced_alignment_language.dart';
import '../domain/proofreading/proofread_result.dart';
import '../domain/proofreading/proofread_review_proposal.dart';
import '../domain/proofreading/project_proofread_evidence.dart';
import '../domain/proofreading/proofread_strategy_selector.dart';
import '../domain/services/lyric_review_priority_service.dart';

/// Centralised user-visible strings for lyric review and line audition.
abstract final class LyricReviewStrings {
  static const String auditionPlayTooltip = '播放/继续本行试听';
  static const String auditionPauseTooltip = '暂停本行试听';
  static const String auditionInvalidStart = '这一行的有效开始时间或结束时间无效，无法试听。';
  static const String auditionErrorPrefix = '无法试听当前歌词行：';
  static const String loopCurrentLineLabel = '循环本行';
  static const String loopCurrentLineHelp =
      '打开后，本行播放到结束时间会回到试听起点；没有有效结束时间的行无法自动循环。';
  static const String loopCurrentLineEnabled = '已开启循环本行';
  static const String loopCurrentLineDisabled = '已关闭循环本行';
  static const String droppedReferenceItemReason = '未找到可靠参考匹配；默认排除，可勾选恢复';

  static String referenceReason(LyricProofreadV2ReferenceReason reason) {
    return switch (reason) {
      LyricProofreadV2ReferenceReason.lowConfidenceAlignment => '对齐置信度低',
      LyricProofreadV2ReferenceReason.ambiguousAlignment => '对齐存在歧义',
      LyricProofreadV2ReferenceReason.structuralMismatch => '行结构不匹配',
      LyricProofreadV2ReferenceReason.referenceTimestamp => '参考时间戳',
      LyricProofreadV2ReferenceReason.mappedAsrTiming => '沿用 ASR 时间',
      LyricProofreadV2ReferenceReason.interpolatedTiming => '插值时间需复核',
      LyricProofreadV2ReferenceReason.estimatedTailTiming => '尾部估算时间需复核',
      LyricProofreadV2ReferenceReason.timelineAdjusted => '时间轴已调整，需复核',
      LyricProofreadV2ReferenceReason.protectedLine => '手动编辑保护',
      LyricProofreadV2ReferenceReason.referenceImportWarning => '参考输入含警告',
    };
  }

  static String proofreadReason(ProofreadReason reason) {
    return switch (reason) {
      ProofreadReason.asrAgreement => 'ASR 一致',
      ProofreadReason.asrDisagreement => 'ASR 不一致',
      ProofreadReason.asrComparisonUnavailable => '缺少可比较的歌词文本',
      ProofreadReason.lowConfidence => '置信度低',
      ProofreadReason.referenceCorrection => '参考文本纠正',
      ProofreadReason.ambiguousAlignment => '对齐存在歧义',
      ProofreadReason.structuralMismatch => '行结构不匹配',
      ProofreadReason.repeatedSegment => '疑似重复片段',
      ProofreadReason.suspectedHallucination => '疑似未演唱内容',
      ProofreadReason.missingReferenceLine => '参考歌词缺行',
      ProofreadReason.interpolatedTiming => '插值时间需复核',
      ProofreadReason.estimatedTiming => '估算时间需复核',
      ProofreadReason.timingAdjusted => '时间轴已调整',
      ProofreadReason.timingConflict => '时间轴冲突',
      ProofreadReason.protectedLine => '手动编辑保护',
      ProofreadReason.importWarning => '导入含警告',
      ProofreadReason.noTimingEvidence => '缺乏时间证据',
    };
  }

  static String alignmentHint(
    LyricProofreadV2AlignmentHint hint, {
    required int wordCount,
  }) {
    return switch (hint) {
      LyricProofreadV2AlignmentHint.wordTimingAvailable => '词级对齐 $wordCount 词',
      LyricProofreadV2AlignmentHint.wordTimingMissing => '缺少词级对齐证据',
    };
  }

  static String projectEvidenceUnavailable(
    ProjectProofreadEvidenceStatus status,
  ) => switch (status) {
    ProjectProofreadEvidenceStatus.available => '工程证据可用。',
    ProjectProofreadEvidenceStatus.projectChanged => '工程已在其他位置更新，请刷新后重试。',
    ProjectProofreadEvidenceStatus.missingEvidence =>
      '工程没有完整的独立双引擎快照；可改为粘贴第二份转写稿。',
    ProjectProofreadEvidenceStatus.invalidEvidence =>
      '工程中的独立转写快照无效或不支持；可改为粘贴第二份转写稿。',
    ProjectProofreadEvidenceStatus.unverifiedAudio =>
      '快照缺少音频校验信息，不能自动复用；可改为粘贴第二份转写稿。',
    ProjectProofreadEvidenceStatus.audioUnavailable => '识别音频不可读取，无法验证工程快照。',
    ProjectProofreadEvidenceStatus.audioChanged => '识别音频与快照不一致，不能复用工程证据。',
    ProjectProofreadEvidenceStatus.audioSelectionChanged =>
      '校验期间工程识别音源发生变化，请重试。',
    ProjectProofreadEvidenceStatus.draftChanged =>
      '当前歌词与独立主引擎原稿不完全一致，不能把第二稿作为独立共识；可改用手动复核。',
    ProjectProofreadEvidenceStatus.unsupportedOffsets =>
      '歌词或转写快照带有偏移，暂不能安全比较工程证据。',
  };

  static const forcedAlignmentBusy = '识别资源正忙，请等待其他任务结束后重试。';

  static String forcedAlignmentLanguageError(
    ForcedAlignmentLanguageResolutionException error,
  ) => '无法从工程语言“${error.language}”确定 ForcedAligner 语言；请将工程语言设为中文、英文或日文。';

  static String proofreadV2Explanation(
    LyricProofreadV2Explanation explanation,
  ) {
    return switch (explanation.code) {
      LyricProofreadV2ExplanationCode.automaticReferenceCoverage =>
        '自动策略计算参考文本覆盖率 '
            '${explanation.referenceCoveragePercent!}%。',
      LyricProofreadV2ExplanationCode.referenceFirstGuidance =>
        '参考优先会以参考行组织提案；低置信、歧义、插值时间和结构差异保持琥珀色。',
      LyricProofreadV2ExplanationCode.referenceAlignmentBudgetExceeded =>
        '词级对齐达到计算预算上限，覆盖率不能作为完整证据。',
      LyricProofreadV2ExplanationCode.referenceInputWarnings =>
        '参考输入包含 ${explanation.referenceWarningCount!} 条冲突或警告，相关行会要求复核。',
      LyricProofreadV2ExplanationCode.forcedAlignmentIgnoredByReference =>
        '本次选择了参考歌词优先，ForcedAligner 未运行；参考优先暂不支持强制对齐。',
      LyricProofreadV2ExplanationCode.secondaryTranscriptIgnoredByReference =>
        '本次选择了参考歌词优先，第二份 ASR 转写稿未参与本次复核。',
      LyricProofreadV2ExplanationCode.referenceIgnoredByAsr =>
        '本次 ASR 优先未用参考歌词替换草稿文字或时间；在自动策略中仅用于覆盖率判断。',
      LyricProofreadV2ExplanationCode.automaticFallbackToAsr =>
        '自动策略因参考文本覆盖率低于 25% 而退回 ASR 优先。',
      LyricProofreadV2ExplanationCode.missingSecondaryTranscript =>
        '未提供第二份 ASR 转写稿，因此只标记当前草稿风险。',
      LyricProofreadV2ExplanationCode.secondaryTranscriptEvidence =>
        '已将第二份带时间戳的转写稿作为独立证据；文本分歧仍需逐行复核。',
      LyricProofreadV2ExplanationCode.asrFirstConservativeTiming =>
        'ASR 优先阶段不会猜测新时间或改写现有歌词；没有可证明的变更时，应用按钮会保持禁用。',
      LyricProofreadV2ExplanationCode.forcedAlignmentEvidenceAvailable =>
        'ForcedAligner 已提供词级时间证据；这些证据仅供复核，不会直接写入歌词时间戳。',
      LyricProofreadV2ExplanationCode.forcedAlignmentUnavailable =>
        'Forced alignment is unavailable. Existing lyric text and timestamps were preserved; review timing manually.',
      LyricProofreadV2ExplanationCode.forcedAlignmentDiagnosticsMissing =>
        'Forced alignment completed without line diagnostics; review timing manually.',
    };
  }

  static String proofreadV2Explanations(
    Iterable<LyricProofreadV2Explanation> explanations,
  ) => explanations.map(proofreadV2Explanation).join(' ');

  static String proofreadV2Summary(LyricProofreadV2ReviewSummary summary) {
    final strategyLabel = switch (summary.effectiveStrategy) {
      LyricSourceStrategy.referenceFirst => '参考歌词优先',
      LyricSourceStrategy.asrFirst => 'ASR 优先',
      LyricSourceStrategy.auto => '自动选择',
    };
    return [
      '策略：$strategyLabel',
      if (summary.referenceCoverage != null)
        '参考覆盖率 ${(summary.referenceCoverage! * 100).round()}%',
      '绿色 ${summary.greenCount}',
      '琥珀色 ${summary.amberCount}',
      '受保护 ${summary.lockedCount}',
      '灰色 ${summary.droppedCount}',
    ].join(' · ');
  }

  static String priorityReason(LyricReviewPriorityReason reason) {
    return switch (reason.code) {
      LyricReviewPriorityReasonCode.emptyLyrics => '歌词为空',
      LyricReviewPriorityReasonCode.confidenceExtremelyLow =>
        '识别置信度极低（${reason.confidence!}）',
      LyricReviewPriorityReasonCode.confidenceVeryLow =>
        '识别置信度很低（${reason.confidence!}）',
      LyricReviewPriorityReasonCode.confidenceLow =>
        '识别置信度偏低（${reason.confidence!}）',
      LyricReviewPriorityReasonCode.confidenceBelowThreshold =>
        '识别置信度低于复核阈值（${reason.confidence!}）',
      LyricReviewPriorityReasonCode.enginesDifferGreatly => '双引擎结果差异很大',
      LyricReviewPriorityReasonCode.enginesDifferClearly => '双引擎结果存在明显分歧',
      LyricReviewPriorityReasonCode.enginesHaveDifferentCandidates =>
        '双引擎存在不同候选',
      LyricReviewPriorityReasonCode.repeatedWords => '出现连续重复词，建议确认是否为识别重复',
      LyricReviewPriorityReasonCode.unusuallyLongText => '单行文本异常偏长，可能包含多句歌词',
      LyricReviewPriorityReasonCode.longTextWithShortInterval =>
        '歌词文本较长但显示区间极短',
      LyricReviewPriorityReasonCode.intervalOverTwentySeconds =>
        '单行持续时间超过 20 秒',
      LyricReviewPriorityReasonCode.negativeStart => '开始时间为负',
      LyricReviewPriorityReasonCode.negativeEffectiveStart => '叠加全局偏移后开始时间为负',
      LyricReviewPriorityReasonCode.invalidTimeInterval => '歌词时间区间无效',
      LyricReviewPriorityReasonCode.nonMonotonicStart => '歌词顺序与时间顺序不一致',
      LyricReviewPriorityReasonCode.duplicateStart => '与上一行开始时间重复',
      LyricReviewPriorityReasonCode.overlapsPrevious => '与上一行时间重叠',
      LyricReviewPriorityReasonCode.overlapsNext => '与下一行时间重叠',
      LyricReviewPriorityReasonCode.extremelyShortGap => '与下一行之间的间隔极短',
      LyricReviewPriorityReasonCode.startBeyondAudio => '开始时间超出音频长度',
      LyricReviewPriorityReasonCode.endBeyondAudio => '结束时间超出音频长度',
    };
  }
}
