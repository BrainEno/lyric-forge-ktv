import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_review_strings.dart';

void main() {
  test('maps every reference-first reason to its existing Chinese label', () {
    const labels = <LyricProofreadV2ReferenceReason, String>{
      LyricProofreadV2ReferenceReason.lowConfidenceAlignment: '对齐置信度低',
      LyricProofreadV2ReferenceReason.ambiguousAlignment: '对齐存在歧义',
      LyricProofreadV2ReferenceReason.structuralMismatch: '行结构不匹配',
      LyricProofreadV2ReferenceReason.referenceTimestamp: '参考时间戳',
      LyricProofreadV2ReferenceReason.mappedAsrTiming: '沿用 ASR 时间',
      LyricProofreadV2ReferenceReason.interpolatedTiming: '插值时间需复核',
      LyricProofreadV2ReferenceReason.estimatedTailTiming: '尾部估算时间需复核',
      LyricProofreadV2ReferenceReason.timelineAdjusted: '时间轴已调整，需复核',
      LyricProofreadV2ReferenceReason.protectedLine: '手动编辑保护',
      LyricProofreadV2ReferenceReason.referenceImportWarning: '参考输入含警告',
    };

    expect(labels.keys.toSet(), LyricProofreadV2ReferenceReason.values.toSet());
    for (final entry in labels.entries) {
      expect(LyricReviewStrings.referenceReason(entry.key), entry.value);
    }
  });

  test('keeps the dropped reference guidance in presentation strings', () {
    expect(
      LyricReviewStrings.droppedReferenceItemReason,
      '未找到可靠参考匹配；默认排除，可勾选恢复',
    );
  });

  test('maps all stable priority reason codes to existing Chinese labels', () {
    const labels = <LyricReviewPriorityReasonCode, String>{
      LyricReviewPriorityReasonCode.emptyLyrics: '歌词为空',
      LyricReviewPriorityReasonCode.enginesDifferGreatly: '双引擎结果差异很大',
      LyricReviewPriorityReasonCode.enginesDifferClearly: '双引擎结果存在明显分歧',
      LyricReviewPriorityReasonCode.enginesHaveDifferentCandidates: '双引擎存在不同候选',
      LyricReviewPriorityReasonCode.repeatedWords: '出现连续重复词，建议确认是否为识别重复',
      LyricReviewPriorityReasonCode.unusuallyLongText: '单行文本异常偏长，可能包含多句歌词',
      LyricReviewPriorityReasonCode.longTextWithShortInterval: '歌词文本较长但显示区间极短',
      LyricReviewPriorityReasonCode.intervalOverTwentySeconds: '单行持续时间超过 20 秒',
      LyricReviewPriorityReasonCode.negativeStart: '开始时间为负',
      LyricReviewPriorityReasonCode.negativeEffectiveStart: '叠加全局偏移后开始时间为负',
      LyricReviewPriorityReasonCode.invalidTimeInterval: '歌词时间区间无效',
      LyricReviewPriorityReasonCode.nonMonotonicStart: '歌词顺序与时间顺序不一致',
      LyricReviewPriorityReasonCode.duplicateStart: '与上一行开始时间重复',
      LyricReviewPriorityReasonCode.overlapsPrevious: '与上一行时间重叠',
      LyricReviewPriorityReasonCode.overlapsNext: '与下一行时间重叠',
      LyricReviewPriorityReasonCode.extremelyShortGap: '与下一行之间的间隔极短',
      LyricReviewPriorityReasonCode.startBeyondAudio: '开始时间超出音频长度',
      LyricReviewPriorityReasonCode.endBeyondAudio: '结束时间超出音频长度',
    };
    const confidenceLabels = <LyricReviewPriorityReasonCode, String>{
      LyricReviewPriorityReasonCode.confidenceExtremelyLow: '识别置信度极低（42）',
      LyricReviewPriorityReasonCode.confidenceVeryLow: '识别置信度很低（42）',
      LyricReviewPriorityReasonCode.confidenceLow: '识别置信度偏低（42）',
      LyricReviewPriorityReasonCode.confidenceBelowThreshold: '识别置信度低于复核阈值（42）',
    };

    expect({
      ...labels.keys,
      ...confidenceLabels.keys,
    }, LyricReviewPriorityReasonCode.values.toSet());
    for (final entry in labels.entries) {
      expect(
        LyricReviewStrings.priorityReason(LyricReviewPriorityReason(entry.key)),
        entry.value,
      );
    }
    for (final entry in confidenceLabels.entries) {
      expect(
        LyricReviewStrings.priorityReason(
          LyricReviewPriorityReason(entry.key, confidence: 42),
        ),
        entry.value,
      );
    }
  });
}
