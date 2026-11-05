import '../domain/proofreading/proofread_result.dart';
import '../domain/proofreading/proofread_review_proposal.dart';
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
