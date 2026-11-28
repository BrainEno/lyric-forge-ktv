import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
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

  test('formats structured smart proofreading summary data', () {
    const summary = LyricProofreadReviewSummary(
      effectiveStrategy: LyricSourceStrategy.referenceFirst,
      greenCount: 2,
      amberCount: 1,
      lockedCount: 1,
      droppedCount: 1,
      referenceCoverage: 0.875,
    );

    expect(
      LyricReviewStrings.proofreadSummary(summary),
      '策略：参考歌词优先 · 参考覆盖率 88% · 绿色 2 · 琥珀色 1 · 受保护 1 · 灰色 1',
    );
  });

  test('formats every strategy label and omits absent reference coverage', () {
    const labels = <LyricSourceStrategy, String>{
      LyricSourceStrategy.referenceFirst: '参考歌词优先',
      LyricSourceStrategy.asrFirst: '识别结果优先',
      LyricSourceStrategy.auto: '自动选择',
    };
    expect(labels.keys.toSet(), LyricSourceStrategy.values.toSet());

    for (final entry in labels.entries) {
      final summary = LyricProofreadReviewSummary(
        effectiveStrategy: entry.key,
        greenCount: 0,
        amberCount: 1,
        lockedCount: 0,
        droppedCount: 0,
        referenceCoverage: null,
      );
      expect(
        LyricReviewStrings.proofreadSummary(summary),
        '策略：${entry.value} · 绿色 0 · 琥珀色 1 · 受保护 0 · 灰色 0',
      );
    }
  });

  test('maps every reference-first reason to its existing Chinese label', () {
    const labels = <LyricProofreadReferenceReason, String>{
      LyricProofreadReferenceReason.lowConfidenceAlignment: '对齐置信度低',
      LyricProofreadReferenceReason.ambiguousAlignment: '对齐存在歧义',
      LyricProofreadReferenceReason.structuralMismatch: '行结构不匹配',
      LyricProofreadReferenceReason.referenceTimestamp: '参考时间戳',
      LyricProofreadReferenceReason.mappedAsrTiming: '沿用 ASR 时间',
      LyricProofreadReferenceReason.interpolatedTiming: '插值时间需复核',
      LyricProofreadReferenceReason.estimatedTailTiming: '尾部估算时间需复核',
      LyricProofreadReferenceReason.timelineAdjusted: '时间轴已调整，需复核',
      LyricProofreadReferenceReason.protectedLine: '手动编辑保护',
      LyricProofreadReferenceReason.referenceImportWarning: '参考输入含警告',
    };

    expect(labels.keys.toSet(), LyricProofreadReferenceReason.values.toSet());
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
    const labels = <LyricProofreadAlignmentHint, String>{
      LyricProofreadAlignmentHint.wordTimingAvailable: '词级对齐 2 词',
      LyricProofreadAlignmentHint.wordTimingMissing: '缺少词级对齐证据',
    };

    expect(labels.keys.toSet(), LyricProofreadAlignmentHint.values.toSet());
    for (final entry in labels.entries) {
      expect(
        LyricReviewStrings.alignmentHint(entry.key, wordCount: 2),
        entry.value,
      );
    }
  });

  test('maps every explanation code to the existing wording', () {
    const explanations =
        <LyricProofreadExplanationCode, LyricProofreadExplanation>{
          LyricProofreadExplanationCode.automaticReferenceCoverage:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.automaticReferenceCoverage,
                referenceCoveragePercent: 73,
              ),
          LyricProofreadExplanationCode.referenceFirstGuidance:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.referenceFirstGuidance,
              ),
          LyricProofreadExplanationCode.referenceAlignmentBudgetExceeded:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.referenceAlignmentBudgetExceeded,
              ),
          LyricProofreadExplanationCode.referenceInputWarnings:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.referenceInputWarnings,
                referenceWarningCount: 2,
              ),
          LyricProofreadExplanationCode.forcedAlignmentIgnoredByReference:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.forcedAlignmentIgnoredByReference,
              ),
          LyricProofreadExplanationCode
              .secondaryTranscriptIgnoredByReference: LyricProofreadExplanation(
            LyricProofreadExplanationCode.secondaryTranscriptIgnoredByReference,
          ),
          LyricProofreadExplanationCode.referenceIgnoredByAsr:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.referenceIgnoredByAsr,
              ),
          LyricProofreadExplanationCode.automaticFallbackToAsr:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.automaticFallbackToAsr,
              ),
          LyricProofreadExplanationCode.missingSecondaryTranscript:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.missingSecondaryTranscript,
              ),
          LyricProofreadExplanationCode.secondaryTranscriptEvidence:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.secondaryTranscriptEvidence,
              ),
          LyricProofreadExplanationCode.asrFirstConservativeTiming:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.asrFirstConservativeTiming,
              ),
          LyricProofreadExplanationCode.forcedAlignmentEvidenceAvailable:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.forcedAlignmentEvidenceAvailable,
              ),
          LyricProofreadExplanationCode.forcedAlignmentUnavailable:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.forcedAlignmentUnavailable,
              ),
          LyricProofreadExplanationCode.forcedAlignmentDiagnosticsMissing:
              LyricProofreadExplanation(
                LyricProofreadExplanationCode.forcedAlignmentDiagnosticsMissing,
              ),
        };
    const labels = <LyricProofreadExplanationCode, String>{
      LyricProofreadExplanationCode.forcedAlignmentIgnoredByReference:
          '本次选择了参考歌词优先，ForcedAligner 未运行；参考优先暂不支持强制对齐。',
      LyricProofreadExplanationCode.secondaryTranscriptIgnoredByReference:
          '本次选择了参考歌词优先，第二份 ASR 转写稿未参与本次复核。',
      LyricProofreadExplanationCode.referenceIgnoredByAsr:
          '本次 ASR 优先未用参考歌词替换草稿文字或时间；在自动策略中仅用于覆盖率判断。',
      LyricProofreadExplanationCode.automaticReferenceCoverage:
          '自动策略计算参考文本覆盖率 73%。',
      LyricProofreadExplanationCode.referenceFirstGuidance:
          '参考优先会以参考行组织提案；低置信、歧义、插值时间和结构差异保持琥珀色。',
      LyricProofreadExplanationCode.referenceAlignmentBudgetExceeded:
          '词级对齐达到计算预算上限，覆盖率不能作为完整证据。',
      LyricProofreadExplanationCode.referenceInputWarnings:
          '参考输入包含 2 条冲突或警告，相关行会要求复核。',
      LyricProofreadExplanationCode.automaticFallbackToAsr:
          '自动策略因参考文本覆盖率低于 25% 而退回 ASR 优先。',
      LyricProofreadExplanationCode.missingSecondaryTranscript:
          '未提供第二份 ASR 转写稿，因此只标记当前草稿风险。',
      LyricProofreadExplanationCode.secondaryTranscriptEvidence:
          '已将第二份带时间戳的转写稿作为独立证据；文本分歧仍需逐行复核。',
      LyricProofreadExplanationCode.asrFirstConservativeTiming:
          'ASR 优先阶段不会猜测新时间或改写现有歌词；没有可证明的变更时，应用按钮会保持禁用。',
      LyricProofreadExplanationCode.forcedAlignmentEvidenceAvailable:
          'ForcedAligner 已提供词级时间证据；这些证据仅供复核，不会直接写入歌词时间戳。',
      LyricProofreadExplanationCode.forcedAlignmentUnavailable:
          'ForcedAligner 强制对齐不可用；已保留现有歌词文字和时间戳，请手动复核时间。',
      LyricProofreadExplanationCode.forcedAlignmentDiagnosticsMissing:
          'ForcedAligner 强制对齐已完成，但未返回逐行诊断；请手动复核时间。',
    };

    expect(
      explanations.keys.toSet(),
      LyricProofreadExplanationCode.values.toSet(),
    );
    expect(labels.keys.toSet(), LyricProofreadExplanationCode.values.toSet());
    for (final entry in explanations.entries) {
      expect(
        LyricReviewStrings.proofreadExplanation(entry.value),
        labels[entry.key],
      );
    }
  });

  test('joins smart proofreading explanations in the provided order', () {
    const explanations = [
      LyricProofreadExplanation(
        LyricProofreadExplanationCode.referenceFirstGuidance,
      ),
      LyricProofreadExplanation(
        LyricProofreadExplanationCode.forcedAlignmentDiagnosticsMissing,
      ),
      LyricProofreadExplanation(
        LyricProofreadExplanationCode.forcedAlignmentEvidenceAvailable,
      ),
    ];

    expect(
      LyricReviewStrings.proofreadExplanations(explanations),
      '参考优先会以参考行组织提案；低置信、歧义、插值时间和结构差异保持琥珀色。 '
      'ForcedAligner 强制对齐已完成，但未返回逐行诊断；请手动复核时间。 '
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
      LyricReviewPriorityReasonCode.secondaryOnlySuggestion:
          '仅备用引擎识别到这一行，建议试听后决定是否补入',
      LyricReviewPriorityReasonCode.vocalGapFillInserted:
          '识别时按人声自动补上的漏句，建议试听确认',
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

  group('LyricSuggestedReviewStrings', () {
    LyricReviewQueue queueOf(List<LyricReviewPriority> items) =>
        LyricReviewQueue(
          items: items,
          lowConfidenceIndices: const <int>{},
          totalLines: 20,
          scoredLines: 20,
          reviewedLines: 0,
          confidenceThreshold: 70,
        );
    LyricReviewPriority row(int score, LyricReviewPriorityReasonCode code) =>
        LyricReviewPriority(
          lineIndex: 0,
          score: score,
          reasons: [LyricReviewPriorityReason(code)],
        );

    test('a count names its 必看 rows only when there are some (D-069)', () {
      expect(LyricSuggestedReviewStrings.countWithMustCheck(12, 5), '12（必看 5）');
      expect(LyricSuggestedReviewStrings.countWithMustCheck(3, 0), '3');
      expect(LyricSuggestedReviewStrings.mustCheckLabel(2), '必看 2');
    });

    test('tiers leave out an empty tier', () {
      final onlyWorth = queueOf([
        row(20, LyricReviewPriorityReasonCode.repeatedWords),
      ]);
      expect(LyricSuggestedReviewStrings.tiers(onlyWorth), '留意 1');
    });

    test('the summary names at most three kinds', () {
      final queue = queueOf([
        row(60, LyricReviewPriorityReasonCode.emptyLyrics),
        row(50, LyricReviewPriorityReasonCode.duplicateStart),
        row(40, LyricReviewPriorityReasonCode.enginesDifferClearly),
        row(30, LyricReviewPriorityReasonCode.secondaryOnlySuggestion),
      ]);
      expect(
        LyricSuggestedReviewStrings.mainReasons(queue),
        '主要原因：空歌词 1、时间轴异常 1、双引擎分歧 1',
      );
      expect(LyricSuggestedReviewStrings.mainReasons(queueOf([])), isNull);
    });

    test('a badge reads its tier; the tooltip keeps score and reasons', () {
      final priority = row(52, LyricReviewPriorityReasonCode.overlapsNext);
      expect(LyricSuggestedReviewStrings.rowSemantics(priority), '建议复核，必看');
      expect(
        LyricSuggestedReviewStrings.badgeTooltip(priority),
        '必看 · 优先级 52\n与下一行时间重叠',
      );
    });
  });
}
