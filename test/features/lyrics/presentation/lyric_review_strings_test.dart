import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_language.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_result.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_review_strings.dart';

void main() {
  test('maps unsupported ForcedAligner language to its existing guidance', () {
    expect(
      LyricReviewStrings.forcedAlignmentLanguageError(
        const ForcedAlignmentLanguageResolutionException('klingon'),
      ),
      '无法从工程语言“klingon”确定 ForcedAligner 语言；请将工程语言设为中文、英文或日文。',
    );
  });

  test('formats structured Proofread V2 summary data with existing copy', () {
    const summary = LyricProofreadV2ReviewSummary(
      effectiveStrategy: LyricSourceStrategy.referenceFirst,
      greenCount: 2,
      amberCount: 1,
      lockedCount: 1,
      droppedCount: 1,
      referenceCoverage: 0.875,
    );

    expect(
      LyricReviewStrings.proofreadV2Summary(summary),
      '策略：参考歌词优先 · 参考覆盖率 88% · 绿色 2 · 琥珀色 1 · 受保护 1 · 灰色 1',
    );
  });

  test('formats every strategy label and omits absent reference coverage', () {
    const labels = <LyricSourceStrategy, String>{
      LyricSourceStrategy.referenceFirst: '参考歌词优先',
      LyricSourceStrategy.asrFirst: 'ASR 优先',
      LyricSourceStrategy.auto: '自动选择',
    };
    expect(labels.keys.toSet(), LyricSourceStrategy.values.toSet());

    for (final entry in labels.entries) {
      final summary = LyricProofreadV2ReviewSummary(
        effectiveStrategy: entry.key,
        greenCount: 0,
        amberCount: 1,
        lockedCount: 0,
        droppedCount: 0,
        referenceCoverage: null,
      );
      expect(
        LyricReviewStrings.proofreadV2Summary(summary),
        '策略：${entry.value} · 绿色 0 · 琥珀色 1 · 受保护 0 · 灰色 0',
      );
    }
  });

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

  test('maps every proofread reason to its existing Chinese label', () {
    const labels = <ProofreadReason, String>{
      ProofreadReason.asrAgreement: 'ASR 一致',
      ProofreadReason.asrDisagreement: 'ASR 不一致',
      ProofreadReason.asrComparisonUnavailable: '缺少可比较的歌词文本',
      ProofreadReason.lowConfidence: '置信度低',
      ProofreadReason.referenceCorrection: '参考文本纠正',
      ProofreadReason.ambiguousAlignment: '对齐存在歧义',
      ProofreadReason.structuralMismatch: '行结构不匹配',
      ProofreadReason.repeatedSegment: '疑似重复片段',
      ProofreadReason.suspectedHallucination: '疑似未演唱内容',
      ProofreadReason.missingReferenceLine: '参考歌词缺行',
      ProofreadReason.interpolatedTiming: '插值时间需复核',
      ProofreadReason.estimatedTiming: '估算时间需复核',
      ProofreadReason.timingAdjusted: '时间轴已调整',
      ProofreadReason.timingConflict: '时间轴冲突',
      ProofreadReason.protectedLine: '手动编辑保护',
      ProofreadReason.importWarning: '导入含警告',
      ProofreadReason.noTimingEvidence: '缺乏时间证据',
    };

    expect(labels.keys.toSet(), ProofreadReason.values.toSet());
    for (final entry in labels.entries) {
      expect(LyricReviewStrings.proofreadReason(entry.key), entry.value);
    }
  });

  test('maps ForcedAligner supplemental hints to their existing labels', () {
    const labels = <LyricProofreadV2AlignmentHint, String>{
      LyricProofreadV2AlignmentHint.wordTimingAvailable: '词级对齐 2 词',
      LyricProofreadV2AlignmentHint.wordTimingMissing: '缺少词级对齐证据',
    };

    expect(labels.keys.toSet(), LyricProofreadV2AlignmentHint.values.toSet());
    for (final entry in labels.entries) {
      expect(
        LyricReviewStrings.alignmentHint(entry.key, wordCount: 2),
        entry.value,
      );
    }
  });

  test('maps every Proofread V2 explanation code to the existing wording', () {
    const explanations =
        <LyricProofreadV2ExplanationCode, LyricProofreadV2Explanation>{
          LyricProofreadV2ExplanationCode.automaticReferenceCoverage:
              LyricProofreadV2Explanation(
                LyricProofreadV2ExplanationCode.automaticReferenceCoverage,
                referenceCoveragePercent: 73,
              ),
          LyricProofreadV2ExplanationCode.referenceFirstGuidance:
              LyricProofreadV2Explanation(
                LyricProofreadV2ExplanationCode.referenceFirstGuidance,
              ),
          LyricProofreadV2ExplanationCode
              .referenceAlignmentBudgetExceeded: LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode.referenceAlignmentBudgetExceeded,
          ),
          LyricProofreadV2ExplanationCode.referenceInputWarnings:
              LyricProofreadV2Explanation(
                LyricProofreadV2ExplanationCode.referenceInputWarnings,
                referenceWarningCount: 2,
              ),
          LyricProofreadV2ExplanationCode.forcedAlignmentIgnoredByReference:
              LyricProofreadV2Explanation(LyricProofreadV2ExplanationCode.forcedAlignmentIgnoredByReference),
          LyricProofreadV2ExplanationCode.secondaryTranscriptIgnoredByReference:
              LyricProofreadV2Explanation(LyricProofreadV2ExplanationCode.secondaryTranscriptIgnoredByReference),
          LyricProofreadV2ExplanationCode.forcedAlignmentIgnoredByReference:
          '本次选择了参考歌词优先，ForcedAligner 未运行；参考优先暂不支持强制对齐。',
      LyricProofreadV2ExplanationCode.secondaryTranscriptIgnoredByReference:
          '本次选择了参考歌词优先，第二份 ASR 转写稿未参与本次复核。',
      LyricProofreadV2ExplanationCode.referenceIgnoredByAsr:
          '本次 ASR 优先未用参考歌词替换草稿文字或时间；在自动策略中仅用于覆盖率判断。',
      LyricProofreadV2ExplanationCode.automaticFallbackToAsr:
              LyricProofreadV2Explanation(
                LyricProofreadV2ExplanationCode.automaticFallbackToAsr,
              ),
          LyricProofreadV2ExplanationCode.missingSecondaryTranscript:
              LyricProofreadV2Explanation(
                LyricProofreadV2ExplanationCode.missingSecondaryTranscript,
              ),
          LyricProofreadV2ExplanationCode.secondaryTranscriptEvidence:
              LyricProofreadV2Explanation(
                LyricProofreadV2ExplanationCode.secondaryTranscriptEvidence,
              ),
          LyricProofreadV2ExplanationCode.asrFirstConservativeTiming:
              LyricProofreadV2Explanation(
                LyricProofreadV2ExplanationCode.asrFirstConservativeTiming,
              ),
          LyricProofreadV2ExplanationCode
              .forcedAlignmentEvidenceAvailable: LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode.forcedAlignmentEvidenceAvailable,
          ),
          LyricProofreadV2ExplanationCode.forcedAlignmentUnavailable:
              LyricProofreadV2Explanation(
                LyricProofreadV2ExplanationCode.forcedAlignmentUnavailable,
              ),
          LyricProofreadV2ExplanationCode
              .forcedAlignmentDiagnosticsMissing: LyricProofreadV2Explanation(
            LyricProofreadV2ExplanationCode.forcedAlignmentDiagnosticsMissing,
          ),
        };
    const labels = <LyricProofreadV2ExplanationCode, String>{
      LyricProofreadV2ExplanationCode.automaticReferenceCoverage:
          '自动策略计算参考文本覆盖率 73%。',
      LyricProofreadV2ExplanationCode.referenceFirstGuidance:
          '参考优先会以参考行组织提案；低置信、歧义、插值时间和结构差异保持琥珀色。',
      LyricProofreadV2ExplanationCode.referenceAlignmentBudgetExceeded:
          '词级对齐达到计算预算上限，覆盖率不能作为完整证据。',
      LyricProofreadV2ExplanationCode.referenceInputWarnings:
          '参考输入包含 2 条冲突或警告，相关行会要求复核。',
      LyricProofreadV2ExplanationCode.automaticFallbackToAsr:
          '自动策略因参考文本覆盖率低于 25% 而退回 ASR 优先。',
      LyricProofreadV2ExplanationCode.missingSecondaryTranscript:
          '未提供第二份 ASR 转写稿，因此只标记当前草稿风险。',
      LyricProofreadV2ExplanationCode.secondaryTranscriptEvidence:
          '已将第二份带时间戳的转写稿作为独立证据；文本分歧仍需逐行复核。',
      LyricProofreadV2ExplanationCode.asrFirstConservativeTiming:
          'ASR 优先阶段不会猜测新时间或改写现有歌词；没有可证明的变更时，应用按钮会保持禁用。',
      LyricProofreadV2ExplanationCode.forcedAlignmentEvidenceAvailable:
          'ForcedAligner 已提供词级时间证据；这些证据仅供复核，不会直接写入歌词时间戳。',
      LyricProofreadV2ExplanationCode.forcedAlignmentUnavailable:
          'Forced alignment is unavailable. Existing lyric text and timestamps were preserved; review timing manually.',
      LyricProofreadV2ExplanationCode.forcedAlignmentDiagnosticsMissing:
          'Forced alignment completed without line diagnostics; review timing manually.',
    };

    expect(
      explanations.keys.toSet(),
      LyricProofreadV2ExplanationCode.values.toSet(),
    );
    expect(labels.keys.toSet(), LyricProofreadV2ExplanationCode.values.toSet());
    for (final entry in explanations.entries) {
      expect(
        LyricReviewStrings.proofreadV2Explanation(entry.value),
        labels[entry.key],
      );
    }
  });

  test('joins Proofread V2 explanations in the provided order', () {
    const explanations = [
      LyricProofreadV2Explanation(
        LyricProofreadV2ExplanationCode.referenceFirstGuidance,
      ),
      LyricProofreadV2Explanation(
        LyricProofreadV2ExplanationCode.forcedAlignmentDiagnosticsMissing,
      ),
      LyricProofreadV2Explanation(
        LyricProofreadV2ExplanationCode.forcedAlignmentEvidenceAvailable,
      ),
    ];

    expect(
      LyricReviewStrings.proofreadV2Explanations(explanations),
      '参考优先会以参考行组织提案；低置信、歧义、插值时间和结构差异保持琥珀色。 '
      'Forced alignment completed without line diagnostics; review timing manually. '
      'ForcedAligner 已提供词级时间证据；这些证据仅供复核，不会直接写入歌词时间戳。',
    );
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
