import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_first_pipeline.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_result.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_first_pipeline.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const assembler = ProofreadV2ReviewAssembler();

  LyricLine row(
    String text,
    int start,
    int end, {
    String? id,
    int confidence = 100,
  }) => LyricLine(
    text: text,
    startTime: Duration(milliseconds: start),
    endTime: Duration(milliseconds: end),
    confidence: confidence,
    id: id,
  );

  LyricDocument doc(List<LyricLine> lines, {Duration? offset}) =>
      LyricDocument(language: 'en', lines: lines, globalOffset: offset);

  ReferenceLyricLine ref(String text, {int? start, int? end}) =>
      ReferenceLyricLine(
        text: text,
        startTime: start == null ? null : Duration(milliseconds: start),
        endTime: end == null ? null : Duration(milliseconds: end),
      );

  ReferenceLyricInput reference(
    List<ReferenceLyricLine> lines, {
    List<String> warnings = const [],
  }) => ReferenceLyricInput(
    lines: lines,
    timed: lines.any((line) => line.hasTimestamp),
    format: 'plain',
    warnings: warnings,
  );

  group('reference-first assembly', () {
    // This draft/reference pair is the one the pipeline test uses to force an
    // interpolated reference line (no draft source) and one unmatched draft
    // row, so the review rows have to describe both cases.
    late LyricDocument draft;

    setUp(() {
      draft = doc([
        row('第一句歌词', 0, 2000, id: 'a'),
        row('unrelated recognition noise', 2000, 2500, id: 'b'),
        row('第三句歌词', 4000, 6000, id: 'c'),
      ], offset: const Duration(milliseconds: 250));
    });

    ProofreadV2ReviewAssembly assemble({
      LyricSourceStrategy strategy = LyricSourceStrategy.referenceFirst,
      Set<int> protected = const {},
      List<String> warnings = const [],
    }) {
      final result = const ReferenceFirstPipeline().build(
        draft: draft,
        reference: reference([
          ref('第一句歌词'),
          ref('第二句歌词'),
          ref('第三句歌词'),
        ], warnings: warnings),
        protectedDraftIndices: protected,
        audioDuration: const Duration(seconds: 8),
      );
      return assembler.referenceFirst(
        draft: draft,
        result: result,
        requestedStrategy: strategy,
      );
    }

    test('rows follow the reference order, not the draft order', () {
      final assembly = assemble();

      expect(assembly.items, hasLength(3));
      expect(assembly.proposalDocument.lines.map((line) => line.text), [
        '第一句歌词',
        '第二句歌词',
        '第三句歌词',
      ]);
      expect(assembly.items.map((item) => item.proposalIndex), [0, 1, 2]);
      expect(assembly.items.map((item) => item.sourceIndex).whereType<int>(), [
        0,
        2,
      ]);
      expect(assembly.items.first.originalLine?.id, 'a');
    });

    test(
      'an interpolated reference line has no draft source and stays amber',
      () {
        final interpolated = assemble().items.singleWhere(
          (item) => item.sourceIndex == null,
        );

        expect(interpolated.originalLine, isNull);
        expect(interpolated.verdict, LyricProofreadReviewVerdict.amber);
        expect(
          interpolated.referenceReasons,
          contains(LyricProofreadV2ReferenceReason.interpolatedTiming),
        );
      },
    );

    test('a protected draft line arrives as a locked row', () {
      final assembly = assemble(protected: {2});
      final locked = assembly.items.firstWhere((item) => item.sourceIndex == 2);

      expect(locked.verdict, LyricProofreadReviewVerdict.locked);
      expect(
        locked.referenceReasons,
        contains(LyricProofreadV2ReferenceReason.protectedLine),
      );
    });

    test('the proposal document drops the global offset', () {
      expect(assemble().proposalDocument.globalOffset, Duration.zero);
    });

    test('an unmatched draft row stays visible for explicit restore', () {
      final assembly = assemble();

      final dropped = assembly.droppedItems.single;
      expect(dropped.sourceIndex, 1);
      expect(dropped.line.text, 'unrelated recognition noise');
      expect(
        assembly.items.map((item) => item.sourceIndex),
        isNot(contains(dropped.sourceIndex)),
      );
    });

    test('coverage is explained only when the strategy was automatic', () {
      expect(
        assemble(
          strategy: LyricSourceStrategy.auto,
        ).explanations.map((explanation) => explanation.code),
        contains(LyricProofreadV2ExplanationCode.automaticReferenceCoverage),
      );
      expect(
        assemble(
          strategy: LyricSourceStrategy.referenceFirst,
        ).explanations.map((explanation) => explanation.code),
        isNot(
          contains(LyricProofreadV2ExplanationCode.automaticReferenceCoverage),
        ),
      );
      expect(
        assemble().explanations.map((explanation) => explanation.code),
        contains(LyricProofreadV2ExplanationCode.referenceFirstGuidance),
      );
    });

    test('reference warnings are surfaced with their count', () {
      final withWarning = assemble(warnings: ['ignored header']);
      final warningExplanation = withWarning.explanations.singleWhere(
        (explanation) =>
            explanation.code ==
            LyricProofreadV2ExplanationCode.referenceInputWarnings,
      );
      expect(warningExplanation.referenceWarningCount, 1);
      expect(
        assemble().explanations.map((explanation) => explanation.code),
        isNot(contains(LyricProofreadV2ExplanationCode.referenceInputWarnings)),
      );
    });
  });

  group('ASR-first assembly', () {
    late LyricDocument draft;

    setUp(() {
      draft = doc([
        row('first line', 0, 1000, id: 'a'),
        row('second line', 1000, 2000, id: 'b', confidence: 55),
      ]);
    });

    ProofreadV2ReviewAssembly assemble({
      Set<int> protected = const {},
      bool forcedAlignment = false,
      bool hasSecondary = false,
      bool fellBack = false,
      List<TimedLyricToken> firstLineTokens = const [],
      ForcedAlignmentProofreadOutcome? outcome,
    }) {
      final pipelineResult = const AsrFirstPipeline().build(
        draft: draft,
        protectedDraftIndices: protected,
      );
      final result = firstLineTokens.isEmpty
          ? pipelineResult
          : ProofreadResult(
              proposedDocument: pipelineResult.proposedDocument,
              lines: [
                for (final entry in pipelineResult.lines.asMap().entries)
                  ProofreadLineResult(
                    lineId: entry.value.lineId,
                    line: entry.value.line,
                    verdict: entry.value.verdict,
                    reasons: entry.value.reasons,
                    risk: entry.value.risk,
                    tokens: entry.key == 0
                        ? firstLineTokens
                        : entry.value.tokens,
                  ),
              ],
              droppedLines: pipelineResult.droppedLines,
              adlibs: pipelineResult.adlibs,
              notes: pipelineResult.notes,
              referenceCoverage: pipelineResult.referenceCoverage,
              autoFellBackToAsr: pipelineResult.autoFellBackToAsr,
              alignmentDiagnostics: pipelineResult.alignmentDiagnostics,
            );
      return assembler.asrFirst(
        draft: draft,
        result: result,
        usedForcedAlignment: forcedAlignment,
        hasSecondaryTranscript: hasSecondary,
        autoFellBackToAsr: fellBack,
        alignmentOutcome: outcome,
      );
    }

    test('rows stay one-to-one with the draft', () {
      final assembly = assemble();

      expect(assembly.items, hasLength(2));
      expect(assembly.items.map((item) => item.sourceIndex), [0, 1]);
      expect(assembly.items.map((item) => item.proposalIndex), [0, 1]);
      expect(assembly.items[1].originalLine?.id, 'b');
      expect(assembly.proposalDocument.lines, hasLength(2));
    });

    test('a scored low-confidence line is amber with its reason', () {
      final assembly = assemble();

      expect(assembly.items[1].verdict, LyricProofreadReviewVerdict.amber);
      expect(
        assembly.items[1].proofreadReasons,
        contains(ProofreadReason.lowConfidence),
      );
      expect(assembly.items.first.verdict, LyricProofreadReviewVerdict.amber);
    });

    test('a protected line is locked', () {
      expect(
        assemble(protected: {0}).items.first.verdict,
        LyricProofreadReviewVerdict.locked,
      );
    });

    test('forced alignment emits typed hints based on word evidence', () {
      final withoutTokens = assemble(forcedAlignment: true);
      expect(withoutTokens.items.first.alignmentHints, {
        LyricProofreadV2AlignmentHint.wordTimingMissing,
      });

      final wordToken = TimedLyricToken(
        text: 'first',
        interval: ProofreadTimeInterval(
          start: Duration.zero,
          end: const Duration(milliseconds: 500),
        ),
        confidence: null,
        source: ProofreadTimeSource.forcedAligner,
      );
      final withTokens = assemble(
        forcedAlignment: true,
        firstLineTokens: [wordToken],
        outcome: ForcedAlignmentProofreadOutcome(
          result: const AsrFirstPipeline().build(draft: draft),
          alignmentAvailable: true,
        ),
      );
      expect(withTokens.items.first.alignmentHints, {
        LyricProofreadV2AlignmentHint.wordTimingAvailable,
      });
      expect(
        withTokens.explanations.map((explanation) => explanation.code),
        contains(
          LyricProofreadV2ExplanationCode.forcedAlignmentEvidenceAvailable,
        ),
      );

      final withoutForcedAlignment = assemble(firstLineTokens: [wordToken]);
      expect(withoutForcedAlignment.items.first.alignmentHints, isEmpty);
    });

    test('explanation codes identify the active ASR evidence path', () {
      expect(
        assemble().explanations.map((explanation) => explanation.code),
        contains(LyricProofreadV2ExplanationCode.missingSecondaryTranscript),
      );
      expect(
        assemble(
          hasSecondary: true,
        ).explanations.map((explanation) => explanation.code),
        contains(LyricProofreadV2ExplanationCode.secondaryTranscriptEvidence),
      );
      expect(
        assemble(
          fellBack: true,
        ).explanations.map((explanation) => explanation.code),
        contains(LyricProofreadV2ExplanationCode.automaticFallbackToAsr),
      );
      expect(
        assemble().explanations.map((explanation) => explanation.code),
        contains(LyricProofreadV2ExplanationCode.asrFirstConservativeTiming),
      );
    });

    test('alignment availability selects a typed fallback explanation', () {
      final result = const AsrFirstPipeline().build(draft: draft);
      final unavailable = assemble(
        forcedAlignment: true,
        outcome: ForcedAlignmentProofreadOutcome(
          result: result,
          alignmentAvailable: false,
        ),
      );
      expect(
        unavailable.explanations.map((explanation) => explanation.code),
        contains(LyricProofreadV2ExplanationCode.forcedAlignmentUnavailable),
      );

      final diagnosticsMissing = assemble(
        forcedAlignment: true,
        outcome: ForcedAlignmentProofreadOutcome(
          result: result,
          alignmentAvailable: true,
        ),
      );
      expect(
        diagnosticsMissing.explanations.map((explanation) => explanation.code),
        contains(
          LyricProofreadV2ExplanationCode.forcedAlignmentDiagnosticsMissing,
        ),
      );
      expect(diagnosticsMissing.alignmentDiagnostics, isNull);
    });
  });

  group('summary', () {
    LyricProofreadV2ReviewItem item(
      LyricProofreadReviewVerdict verdict,
      int index,
    ) => LyricProofreadV2ReviewItem(
      proposalIndex: index,
      sourceIndex: index,
      proposedLine: const LyricLine(
        text: 'x',
        startTime: Duration.zero,
        endTime: Duration(seconds: 1),
      ),
      originalLine: null,
      verdict: verdict,
    );

    test('counts every group and includes coverage when provided', () {
      final text = assembler.summary(
        effectiveStrategy: LyricSourceStrategy.referenceFirst,
        items: [
          item(LyricProofreadReviewVerdict.green, 0),
          item(LyricProofreadReviewVerdict.green, 1),
          item(LyricProofreadReviewVerdict.amber, 2),
          item(LyricProofreadReviewVerdict.locked, 3),
        ],
        droppedItems: [
          const LyricProofreadV2DroppedItem(
            sourceIndex: 9,
            line: LyricLine(
              text: 'dropped',
              startTime: Duration.zero,
              endTime: Duration(seconds: 1),
            ),
          ),
        ],
        referenceCoverage: 0.875,
      );

      expect(text, '策略：参考歌词优先 · 参考覆盖率 88% · 绿色 2 · 琥珀色 1 · 受保护 1 · 灰色 1');
    });

    test('omits coverage when the run had no reference', () {
      final text = assembler.summary(
        effectiveStrategy: LyricSourceStrategy.asrFirst,
        items: [item(LyricProofreadReviewVerdict.amber, 0)],
        droppedItems: const [],
      );

      expect(text, '策略：ASR 优先 · 绿色 0 · 琥珀色 1 · 受保护 0 · 灰色 0');
    });
  });

  test('reference reason codes preserve every pipeline reason', () {
    for (final reason in ReferenceFirstReason.values) {
      expect(
        ProofreadV2ReviewAssembler.referenceReasonCode(reason).name,
        reason.name,
      );
    }
  });

  test('strategy labels cover every strategy value', () {
    for (final strategy in LyricSourceStrategy.values) {
      expect(ProofreadV2ReviewAssembler.strategyLabel(strategy), isNotEmpty);
    }
  });
}
