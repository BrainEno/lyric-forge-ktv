import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/run_proofread_v2_use_case.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricDocument transcript(String text) => LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: text,
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
      confidence: 90,
    ),
  ],
);
ReferenceLyricInput reference(String text) => ReferenceLyricInput(
  lines: [ReferenceLyricLine(text: text)],
  timed: false,
  format: 'plain',
);
const audio = AudioAsset(
  originalPath: '/song.wav',
  vocalPath: '/voice.wav',
  format: 'wav',
  duration: Duration(seconds: 4),
);

Set<LyricProofreadV2ExplanationCode> codes(ProofreadV2RunResult result) =>
    result.assembly.explanations.map((e) => e.code).toSet();

void main() {
  late int calls;
  late String? alignedText;
  late String? alignedPath;
  late RunProofreadV2UseCase useCase;
  setUp(() {
    calls = 0;
    alignedText = null;
    alignedPath = null;
    useCase = RunProofreadV2UseCase(
      runner:
          ({
            required audioPath,
            required text,
            required language,
            required audioDuration,
          }) async {
            calls++;
            alignedText = text;
            alignedPath = audioPath;
            return const [];
          },
    );
  });

  group('automatic strategy evidence routing', () {
    for (final hasSecondary in [false, true]) {
      for (final alignment in [false, true]) {
        test(
          'no reference uses ASR: second=$hasSecondary alignment=$alignment',
          () async {
            final draft = transcript('hello world');
            final before = jsonEncode(draft.toJson());
            final run = await useCase.build(
              draft: draft,
              strategy: LyricSourceStrategy.auto,
              secondary: hasSecondary ? transcript('hello world') : null,
              useForcedAlignment: alignment,
              audioAsset: audio,
            );
            expect(
              run.decision.effectiveStrategy,
              LyricSourceStrategy.asrFirst,
            );
            expect(
              run.decision.reason,
              ProofreadStrategyReason.autoWithoutReference,
            );
            expect(calls, alignment ? 1 : 0);
            expect(
              codes(run),
              contains(
                hasSecondary
                    ? LyricProofreadV2ExplanationCode
                          .secondaryTranscriptEvidence
                    : LyricProofreadV2ExplanationCode
                          .missingSecondaryTranscript,
              ),
            );
            expect(
              codes(run),
              isNot(
                contains(
                  LyricProofreadV2ExplanationCode.automaticFallbackToAsr,
                ),
              ),
            );
            expect(
              codes(run),
              isNot(
                contains(
                  LyricProofreadV2ExplanationCode
                      .forcedAlignmentIgnoredByReference,
                ),
              ),
            );
            expect(
              codes(run),
              isNot(
                contains(
                  LyricProofreadV2ExplanationCode
                      .secondaryTranscriptIgnoredByReference,
                ),
              ),
            );
            if (alignment) {
              expect(alignedText, 'hello world');
              expect(alignedPath, '/voice.wav');
            }
            expect(jsonEncode(draft.toJson()), before);
          },
        );

        test(
          'matching reference routes alignment and ignores secondary: second=$hasSecondary alignment=$alignment',
          () async {
            final draft = transcript('hello world');
            final secondary = hasSecondary ? transcript('hello world') : null;
            final run = await useCase.build(
              draft: draft,
              strategy: LyricSourceStrategy.auto,
              reference: reference('hello world'),
              secondary: secondary,
              useForcedAlignment: alignment,
              audioAsset: audio,
            );
            expect(
              run.decision.effectiveStrategy,
              LyricSourceStrategy.referenceFirst,
            );
            expect(calls, alignment ? 1 : 0);
            expect(run.assembly.referenceAlignmentPlan != null, alignment);
            expect(
              codes(run).contains(
                LyricProofreadV2ExplanationCode
                    .forcedAlignmentIgnoredByReference,
              ),
              isFalse,
            );
            if (alignment) {
              expect(alignedText, 'hello world');
              expect(alignedPath, '/voice.wav');
            }
            expect(
              codes(run).contains(
                LyricProofreadV2ExplanationCode
                    .secondaryTranscriptIgnoredByReference,
              ),
              hasSecondary,
            );
            expect(
              codes(run),
              contains(
                LyricProofreadV2ExplanationCode.automaticReferenceCoverage,
              ),
            );
            expect(
              codes(run),
              isNot(
                contains(
                  LyricProofreadV2ExplanationCode.secondaryTranscriptEvidence,
                ),
              ),
            );
            expect(
              codes(run),
              isNot(
                contains(LyricProofreadV2ExplanationCode.referenceIgnoredByAsr),
              ),
            );
            expect(draft.lines.single.text, 'hello world');
          },
        );

        test(
          'unrelated reference falls back and reports actual evidence: second=$hasSecondary alignment=$alignment',
          () async {
            final run = await useCase.build(
              draft: transcript('hello world'),
              strategy: LyricSourceStrategy.auto,
              reference: reference('unrelated unknown words'),
              secondary: hasSecondary ? transcript('hello world') : null,
              useForcedAlignment: alignment,
              audioAsset: audio,
            );
            expect(
              run.decision.effectiveStrategy,
              LyricSourceStrategy.asrFirst,
            );
            expect(
              codes(run),
              contains(LyricProofreadV2ExplanationCode.automaticFallbackToAsr),
            );
            expect(
              codes(run),
              contains(LyricProofreadV2ExplanationCode.referenceIgnoredByAsr),
            );
            expect(
              codes(run),
              contains(
                hasSecondary
                    ? LyricProofreadV2ExplanationCode
                          .secondaryTranscriptEvidence
                    : LyricProofreadV2ExplanationCode
                          .missingSecondaryTranscript,
              ),
            );
            expect(
              codes(run),
              isNot(
                contains(
                  hasSecondary
                      ? LyricProofreadV2ExplanationCode
                            .missingSecondaryTranscript
                      : LyricProofreadV2ExplanationCode
                            .secondaryTranscriptEvidence,
                ),
              ),
            );
            expect(calls, alignment ? 1 : 0);
            expect(
              codes(run),
              isNot(
                contains(
                  LyricProofreadV2ExplanationCode
                      .forcedAlignmentIgnoredByReference,
                ),
              ),
            );
            expect(
              codes(run),
              isNot(
                contains(
                  LyricProofreadV2ExplanationCode
                      .secondaryTranscriptIgnoredByReference,
                ),
              ),
            );
          },
        );
      }
    }

    test(
      'reference-first requires audio when alignment is requested',
      () async {
        await expectLater(
          useCase.build(
            draft: transcript('hello world'),
            strategy: LyricSourceStrategy.referenceFirst,
            reference: reference('hello world'),
            useForcedAlignment: true,
          ),
          throwsA(isA<ProofreadV2MissingAudioException>()),
        );
        expect(calls, 0);
      },
    );

    test(
      'explicit ASR with a supplied reference states it is not applied',
      () async {
        final run = await useCase.build(
          draft: transcript('hello world'),
          strategy: LyricSourceStrategy.asrFirst,
          reference: reference('other words'),
        );
        expect(
          codes(run),
          contains(LyricProofreadV2ExplanationCode.referenceIgnoredByAsr),
        );
        expect(
          codes(run),
          isNot(
            contains(LyricProofreadV2ExplanationCode.automaticFallbackToAsr),
          ),
        );
      },
    );

    test(
      'ASR alignment without duration still reports a typed error',
      () async {
        await expectLater(
          useCase.build(
            draft: transcript('hello world'),
            strategy: LyricSourceStrategy.auto,
            useForcedAlignment: true,
          ),
          throwsA(isA<ProofreadV2MissingAudioException>()),
        );
        expect(calls, 0);
      },
    );

    test('busy forced aligner remains a retryable failure', () async {
      final busy = RunProofreadV2UseCase(
        runner:
            ({
              required audioPath,
              required text,
              required language,
              required audioDuration,
            }) async => throw const ForcedAlignmentResourceBusyException(),
      );
      await expectLater(
        busy.build(
          draft: transcript('hello world'),
          strategy: LyricSourceStrategy.auto,
          useForcedAlignment: true,
          audioAsset: audio,
        ),
        throwsA(isA<ForcedAlignmentResourceBusyException>()),
      );
    });
  });
}
