import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_language.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_result.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/run_proofread_v2_use_case.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricDocument draft({String language = 'en'}) => LyricDocument(
  language: language,
  globalOffset: const Duration(milliseconds: 100),
  lines: const [
    LyricLine(
      id: 'a',
      text: 'hello world',
      startTime: Duration.zero,
      endTime: Duration(seconds: 2),
      confidence: 90,
    ),
    LyricLine(
      id: 'b',
      text: 'sing tonight',
      startTime: Duration(seconds: 2),
      endTime: Duration(seconds: 4),
      confidence: 40,
    ),
  ],
);

ReferenceLyricInput reference(
  List<String> texts, {
  List<String> warnings = const [],
}) => ReferenceLyricInput(
  lines: [for (final text in texts) ReferenceLyricLine(text: text)],
  timed: false,
  format: 'txt',
  warnings: warnings,
);

const audio = AudioAsset(
  originalPath: '/song.wav',
  vocalPath: '/vocals.wav',
  format: 'wav',
  duration: Duration(seconds: 6),
);

class SpyRunner {
  int calls = 0;
  String? path;
  String? text;
  String? language;
  Duration? duration;
  Object? error;
  Future<List<ForcedAlignedSpan>>? pending;
  List<ForcedAlignedSpan> spans = [];

  Future<List<ForcedAlignedSpan>> run({
    required String audioPath,
    required String text,
    required String language,
    required Duration audioDuration,
  }) async {
    calls++;
    path = audioPath;
    this.text = text;
    this.language = language;
    duration = audioDuration;
    if (error != null) throw error!;
    return pending == null ? spans : await pending!;
  }
}

Set<LyricProofreadV2ExplanationCode> codes(ProofreadV2RunResult result) =>
    result.assembly.explanations.map((entry) => entry.code).toSet();

void main() {
  late SpyRunner spy;
  late RunProofreadV2UseCase useCase;

  setUp(() {
    spy = SpyRunner();
    useCase = RunProofreadV2UseCase(runner: spy.run);
  });

  group('strategy and evidence orchestration', () {
    test(
      'explicit ASR mode keeps draft and explains missing second transcript',
      () async {
        final input = draft();
        final snapshot = jsonEncode(input.toJson());
        final run = await useCase.build(
          draft: input,
          strategy: LyricSourceStrategy.asrFirst,
          audioAsset: audio,
        );
        expect(run.decision.effectiveStrategy, LyricSourceStrategy.asrFirst);
        expect(run.summary.effectiveStrategy, LyricSourceStrategy.asrFirst);
        expect(run.assembly.items, hasLength(2));
        expect(run.assembly.proposalDocument.lines.map((line) => line.text), [
          'hello world',
          'sing tonight',
        ]);
        expect(
          codes(run),
          contains(LyricProofreadV2ExplanationCode.missingSecondaryTranscript),
        );
        expect(spy.calls, 0);
        expect(jsonEncode(input.toJson()), snapshot);
      },
    );

    test('secondary evidence is reflected in assembled explanation', () async {
      final input = draft();
      final run = await useCase.build(
        draft: input,
        secondary: draft(),
        strategy: LyricSourceStrategy.asrFirst,
      );
      expect(
        codes(run),
        contains(LyricProofreadV2ExplanationCode.secondaryTranscriptEvidence),
      );
      expect(
        codes(run),
        isNot(
          contains(LyricProofreadV2ExplanationCode.missingSecondaryTranscript),
        ),
      );
      expect(run.assembly.items, hasLength(2));
      expect(spy.calls, 0);
    });

    test('matching secondary transcript yields V2 consensus rows', () async {
      final primary = LyricDocument(
        language: 'en',
        lines: const [
          LyricLine(
            id: 'primary',
            text: 'hello world',
            startTime: Duration.zero,
            endTime: Duration(seconds: 2),
            confidence: 90,
          ),
        ],
      );
      final secondary = LyricDocument(
        language: 'en',
        lines: const [
          LyricLine(
            id: 'secondary',
            text: 'hello world',
            startTime: Duration.zero,
            endTime: Duration(seconds: 2),
            confidence: 90,
          ),
        ],
      );

      final run = await useCase.build(
        draft: primary,
        secondary: secondary,
        strategy: LyricSourceStrategy.auto,
      );

      expect(run.decision.effectiveStrategy, LyricSourceStrategy.asrFirst);
      expect(run.assembly.items, hasLength(1));
      expect(
        run.assembly.items.single.proofreadReasons,
        contains(ProofreadReason.asrAgreement),
      );
      expect(
        run.assembly.items.single.verdict,
        LyricProofreadReviewVerdict.green,
      );
      expect(
        codes(run),
        contains(LyricProofreadV2ExplanationCode.secondaryTranscriptEvidence),
      );
      expect(
        codes(run),
        isNot(
          contains(LyricProofreadV2ExplanationCode.missingSecondaryTranscript),
        ),
      );
    });

    test(
      'auto without reference selects ASR without labeling it a coverage fallback',
      () async {
        final run = await useCase.build(
          draft: draft(),
          strategy: LyricSourceStrategy.auto,
        );
        expect(
          run.decision.reason,
          ProofreadStrategyReason.autoWithoutReference,
        );
        expect(run.decision.effectiveStrategy, LyricSourceStrategy.asrFirst);
        expect(run.decision.autoFellBackToAsr, isFalse);
        expect(run.summary.referenceCoverage, isNull);
      },
    );

    test('auto with matching reference selects reference pipeline', () async {
      final run = await useCase.build(
        draft: draft(),
        strategy: LyricSourceStrategy.auto,
        reference: reference(['hello world', 'sing tonight']),
        audioAsset: audio,
      );
      expect(
        run.decision.effectiveStrategy,
        LyricSourceStrategy.referenceFirst,
      );
      expect(
        run.decision.reason,
        ProofreadStrategyReason.autoCoverageSufficient,
      );
      expect(run.summary.referenceCoverage, closeTo(1, 0.001));
      expect(
        codes(run),
        contains(LyricProofreadV2ExplanationCode.automaticReferenceCoverage),
      );
      expect(spy.calls, 0);
    });

    test('auto with unrelated reference falls back to ASR', () async {
      final run = await useCase.build(
        draft: draft(),
        strategy: LyricSourceStrategy.auto,
        reference: reference(['completely different unrelated words']),
        audioAsset: audio,
      );
      expect(run.decision.effectiveStrategy, LyricSourceStrategy.asrFirst);
      expect(run.decision.autoFellBackToAsr, isTrue);
      expect(
        codes(run),
        contains(LyricProofreadV2ExplanationCode.automaticFallbackToAsr),
      );
      expect(run.assembly.proposalDocument.lines.map((line) => line.text), [
        'hello world',
        'sing tonight',
      ]);
    });

    test(
      'reference strategy without reference fails before runner invocation',
      () async {
        await expectLater(
          useCase.build(
            draft: draft(),
            strategy: LyricSourceStrategy.referenceFirst,
            useForcedAlignment: true,
            audioAsset: audio,
          ),
          throwsArgumentError,
        );
        expect(spy.calls, 0);
      },
    );

    test(
      'explicit reference exposes import warnings and ordered proposal',
      () async {
        final input = draft();
        final snapshot = jsonEncode(input.toJson());
        final run = await useCase.build(
          draft: input,
          strategy: LyricSourceStrategy.referenceFirst,
          reference: reference(
            ['hello world', 'sing tonight'],
            warnings: ['conflict'],
          ),
          audioAsset: audio,
        );
        expect(run.assembly.items.map((row) => row.proposedLine.text), [
          'hello world',
          'sing tonight',
        ]);
        expect(
          codes(run),
          contains(LyricProofreadV2ExplanationCode.referenceInputWarnings),
        );
        expect(
          run.assembly.explanations
              .singleWhere(
                (entry) =>
                    entry.code ==
                    LyricProofreadV2ExplanationCode.referenceInputWarnings,
              )
              .referenceWarningCount,
          1,
        );
        expect(run.assembly.proposalDocument.globalOffset, Duration.zero);
        expect(jsonEncode(input.toJson()), snapshot);
      },
    );

    test(
      'manual and explicitly reviewed rows are protected together',
      () async {
        final input = const LyricReviewDecisionService().setReviewed(
          draft(),
          1,
          reviewed: true,
          reviewedAt: DateTime.utc(2026),
        );
        final run = await useCase.build(
          draft: input,
          strategy: LyricSourceStrategy.referenceFirst,
          reference: reference(['hello world', 'sing tonight']),
          manuallyEditedIndices: {0},
          audioAsset: audio,
        );
        expect(run.assembly.items.map((row) => row.verdict), [
          LyricProofreadReviewVerdict.locked,
          LyricProofreadReviewVerdict.locked,
        ]);
        expect(run.summary.lockedCount, 2);
        expect(
          run.assembly.items.every(
            (row) => row.referenceReasons.contains(
              LyricProofreadV2ReferenceReason.protectedLine,
            ),
          ),
          isTrue,
        );
      },
    );

    test('invalid manual index is rejected by the pipeline', () async {
      await expectLater(
        useCase.build(
          draft: draft(),
          strategy: LyricSourceStrategy.asrFirst,
          manuallyEditedIndices: {5},
        ),
        throwsArgumentError,
      );
    });
  });

  group('forced alignment boundary', () {
    test(
      'passes vocal path, draft text, resolved language and duration',
      () async {
        spy.spans = const [
          ForcedAlignedSpan(
            text: 'hello',
            start: Duration(milliseconds: 100),
            end: Duration(milliseconds: 500),
          ),
          ForcedAlignedSpan(
            text: 'world',
            start: Duration(milliseconds: 600),
            end: Duration(milliseconds: 900),
          ),
        ];
        final input = draft(language: 'en-US');
        final before = jsonEncode(input.toJson());
        final run = await useCase.build(
          draft: input,
          strategy: LyricSourceStrategy.asrFirst,
          audioAsset: audio,
          useForcedAlignment: true,
        );
        expect(spy.calls, 1);
        expect(spy.path, '/vocals.wav');
        expect(spy.text, 'hello world\nsing tonight');
        expect(spy.language, 'English');
        expect(spy.duration, const Duration(seconds: 6));
        expect(run.assembly.alignmentDiagnostics, isNotNull);
        expect(run.assembly.items.first.alignmentTokens, isNotEmpty);
        expect(
          codes(run),
          contains(
            LyricProofreadV2ExplanationCode.forcedAlignmentEvidenceAvailable,
          ),
        );
        expect(jsonEncode(input.toJson()), before);
      },
    );

    test('uses original audio when vocal path is absent', () async {
      await useCase.build(
        draft: draft(),
        strategy: LyricSourceStrategy.asrFirst,
        audioAsset: const AudioAsset(
          originalPath: '/original.wav',
          format: 'wav',
          duration: Duration(seconds: 5),
        ),
        useForcedAlignment: true,
      );
      expect(spy.path, '/original.wav');
    });

    test('empty alignment is an available result with diagnostics', () async {
      final run = await useCase.build(
        draft: draft(),
        strategy: LyricSourceStrategy.asrFirst,
        audioAsset: audio,
        useForcedAlignment: true,
      );
      expect(spy.calls, 1);
      expect(run.assembly.alignmentDiagnostics, isNotNull);
      expect(
        codes(run),
        isNot(
          contains(
            LyricProofreadV2ExplanationCode.forcedAlignmentEvidenceAvailable,
          ),
        ),
      );
      expect(
        codes(run),
        isNot(
          contains(LyricProofreadV2ExplanationCode.forcedAlignmentUnavailable),
        ),
      );
    });

    test(
      'ordinary aligner failure produces conservative review and warning',
      () async {
        spy.error = Exception('unavailable');
        final run = await useCase.build(
          draft: draft(),
          strategy: LyricSourceStrategy.asrFirst,
          audioAsset: audio,
          useForcedAlignment: true,
        );
        expect(
          codes(run),
          contains(LyricProofreadV2ExplanationCode.forcedAlignmentUnavailable),
        );
        expect(run.assembly.proposalDocument.lines.map((line) => line.text), [
          'hello world',
          'sing tonight',
        ]);
      },
    );

    test(
      'busy alignment remains retryable and is not treated as unavailable',
      () async {
        spy.error = const ForcedAlignmentResourceBusyException();
        await expectLater(
          useCase.build(
            draft: draft(),
            strategy: LyricSourceStrategy.asrFirst,
            audioAsset: audio,
            useForcedAlignment: true,
          ),
          throwsA(isA<ForcedAlignmentResourceBusyException>()),
        );
        expect(spy.calls, 1);
      },
    );

    for (final asset in <AudioAsset?>[
      null,
      const AudioAsset(originalPath: '/a', format: 'wav'),
      const AudioAsset(
        originalPath: '/a',
        format: 'wav',
        duration: Duration.zero,
      ),
      const AudioAsset(
        originalPath: '/a',
        format: 'wav',
        duration: Duration(seconds: -1),
      ),
    ]) {
      test(
        'missing or invalid duration rejects alignment: ${asset?.duration}',
        () async {
          await expectLater(
            useCase.build(
              draft: draft(),
              strategy: LyricSourceStrategy.asrFirst,
              audioAsset: asset,
              useForcedAlignment: true,
            ),
            throwsA(isA<ProofreadV2MissingAudioException>()),
          );
          expect(spy.calls, 0);
        },
      );
    }

    test('unsupported language rejects alignment before runner', () async {
      await expectLater(
        useCase.build(
          draft: draft(language: 'unknown'),
          strategy: LyricSourceStrategy.asrFirst,
          audioAsset: audio,
          useForcedAlignment: true,
        ),
        throwsA(isA<ForcedAlignmentLanguageResolutionException>()),
      );
      expect(spy.calls, 0);
    });

    test('reference strategy sends reference text to the aligner', () async {
      final run = await useCase.build(
        draft: draft(),
        strategy: LyricSourceStrategy.referenceFirst,
        reference: reference(['hello world', 'sing tonight']),
        audioAsset: audio,
        useForcedAlignment: true,
      );
      expect(
        run.decision.effectiveStrategy,
        LyricSourceStrategy.referenceFirst,
      );
      expect(spy.calls, 1);
      expect(spy.text, 'hello world\nsing tonight');
      expect(run.assembly.referenceAlignmentPlan, isNotNull);
    });

    test(
      'runner may finish later without modifying the original draft',
      () async {
        final completion = Completer<List<ForcedAlignedSpan>>();
        spy.pending = completion.future;
        final input = draft();
        final snapshot = jsonEncode(input.toJson());
        final pending = useCase.build(
          draft: input,
          strategy: LyricSourceStrategy.asrFirst,
          audioAsset: audio,
          useForcedAlignment: true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(spy.calls, 1);
        completion.complete([]);
        final run = await pending;
        expect(run.assembly.items, hasLength(2));
        expect(jsonEncode(input.toJson()), snapshot);
      },
    );
  });
}
