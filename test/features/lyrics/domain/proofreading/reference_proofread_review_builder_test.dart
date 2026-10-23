import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_retiming_planner.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_proofread_review_builder.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const builder = ReferenceProofreadReviewBuilder();

  LyricLine lyric(String text, int start, int end, {int confidence = 90}) =>
      LyricLine(
        text: text,
        startTime: Duration(milliseconds: start),
        endTime: Duration(milliseconds: end),
        confidence: confidence,
      );

  ReferenceLyricInput reference(
    String text, {
    List<String> warnings = const [],
    List<String> conflicts = const [],
  }) =>
      ReferenceLyricInput(
        lines: [ReferenceLyricLine(text: text)],
        timed: false,
        format: 'plain',
        warnings: warnings,
        conflicts: conflicts,
      );

  LyricDocument document(List<LyricLine> lines) =>
      LyricDocument(language: 'en', lines: lines);

  test('pairs a reference text suggestion with exact nearby ASR timing', () {
    final source = lyric('Hello word', 2100, 4600);
    final draft = document([source]);
    final result = builder.build(
      draft: draft,
      reference: reference('Hello world'),
      timingEvidence: document([lyric('Hello world', 2200, 4500)]),
      audioDuration: const Duration(seconds: 10),
    );

    expect(result, hasLength(1));
    final item = result.single;
    expect(item.correction.currentText, 'Hello word');
    expect(item.correction.suggestedText, 'Hello world');
    expect(item.retiming.status, AsrRetimingStatus.readyForReview);
    expect(
      item.retiming.options.single.startTime,
      const Duration(milliseconds: 2200),
    );
    expect(
      item.retiming.options.single.endTime,
      const Duration(milliseconds: 4500),
    );
    expect(item.canOfferCompleteProposal, isTrue);
    expect(draft.lines.single.text, 'Hello word');
    expect(source.startTime, const Duration(milliseconds: 2100));
  });

  test(
    'keeps a text correction incomplete when exact timing evidence is absent',
    () {
      final result = builder.build(
        draft: document([lyric('Hello word', 2100, 4600)]),
        reference: reference('Hello world'),
        timingEvidence: document([lyric('Something else', 2200, 4500)]),
      );

      expect(result, hasLength(1));
      expect(
        result.single.retiming.status,
        AsrRetimingStatus.noMatchingEvidence,
      );
      expect(result.single.requiresManualReview, isTrue);
      expect(result.single.canOfferCompleteProposal, isFalse);
    },
  );

  test('protected rows never produce correction bundles', () {
    final result = builder.build(
      draft: document([lyric('Hello word', 2100, 4600)]),
      reference: reference('Hello world'),
      timingEvidence: document([lyric('Hello world', 2200, 4500)]),
      protectedDraftIndices: const {0},
    );

    expect(result, isEmpty);
  });

  test('reference import warnings prevent complete proposal eligibility', () {
    final result = builder.build(
      draft: document([lyric('Hello word', 2100, 4600)]),
      reference: reference(
        'Hello world',
        warnings: const ['Timestamp repaired'],
      ),
      timingEvidence: document([lyric('Hello world', 2200, 4500)]),
    );

    expect(result, hasLength(1));
    expect(result.single.correction.requiresManualReview, isTrue);
    expect(result.single.canOfferCompleteProposal, isFalse);
  });
}
