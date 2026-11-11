import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_retiming_planner.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/run_reference_proofread_use_case.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricLine line(String text, int start, int end, {int confidence = 90}) =>
    LyricLine(
      text: text,
      startTime: Duration(milliseconds: start),
      endTime: Duration(milliseconds: end),
      confidence: confidence,
    );

LyricDocument document(List<LyricLine> lines) => LyricDocument(
  language: 'en',
  lines: lines,
  globalOffset: const Duration(milliseconds: 25),
  metadata: const {'origin': 'test'},
);

ReferenceLyricInput reference(
  String text, {
  List<String> warnings = const [],
}) => ReferenceLyricInput(
  lines: [ReferenceLyricLine(text: text)],
  timed: false,
  format: 'plain',
  warnings: warnings,
);

void main() {
  const useCase = RunReferenceProofreadUseCase();
  late LyricDocument draft;
  late LyricDocument evidence;

  setUp(() {
    draft = document([line('Hello word', 2100, 4600)]);
    evidence = document([line('Hello world', 2200, 4500)]);
  });

  group('text-only preparation and application', () {
    test(
      'exposes correction without timing and preserves original snapshot',
      () {
        final plan = useCase.build(
          draft: draft,
          reference: reference('Hello world'),
        );
        expect(plan.hasTimingEvidence, isFalse);
        expect(plan.isEmpty, isFalse);
        expect(plan.timedItems, isEmpty);
        expect(plan.suggestions.single.currentText, 'Hello word');
        expect(plan.suggestions.single.suggestedText, 'Hello world');
        expect(draft.lines.single.text, 'Hello word');
      },
    );

    test(
      'explicit selection applies text but preserves timing and metadata',
      () {
        final plan = useCase.build(
          draft: draft,
          reference: reference('Hello world'),
        );
        final result = plan.apply({0});
        expect(result.after.lines.single.text, 'Hello world');
        expect(
          result.after.lines.single.startTime,
          draft.lines.single.startTime,
        );
        expect(result.after.lines.single.endTime, draft.lines.single.endTime);
        expect(result.after.globalOffset, draft.globalOffset);
        expect(result.after.metadata, draft.metadata);
        expect(result.changedDraftIndices, [0]);
        expect(result.undo(), same(draft));
        expect(result.redo(), same(result.after));
      },
    );

    test('matching text produces an empty plan', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello word'),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.suggestions, isEmpty);
    });

    test('protected line is excluded from suggestions', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world'),
        protectedDraftIndices: {0},
      );
      expect(plan.isEmpty, isTrue);
      expect(() => plan.apply({0}), throwsStateError);
    });

    test('reference warnings keep a candidate in manual review', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world', warnings: ['input warning']),
      );
      expect(plan.suggestions.single.requiresManualReview, isTrue);
      expect(() => plan.apply({0}), throwsStateError);
      expect(draft.lines.single.text, 'Hello word');
    });

    test('empty selection cannot apply', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world'),
      );
      expect(() => plan.apply({}), throwsArgumentError);
    });

    test('selection outside snapshot fails atomically', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world'),
      );
      expect(() => plan.apply({0, 8}), throwsRangeError);
      expect(draft.lines.single.text, 'Hello word');
    });

    test('plan collections are unmodifiable', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world'),
      );
      expect(() => plan.suggestions.clear(), throwsUnsupportedError);
      expect(() => plan.timedItems.clear(), throwsUnsupportedError);
      expect(() => plan.protectedDraftIndices.add(0), throwsUnsupportedError);
    });

    test('caller cannot mutate captured protection after preparing', () {
      final protected = <int>{};
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world'),
        protectedDraftIndices: protected,
      );
      protected.add(0);
      expect(plan.protectedDraftIndices, isEmpty);
      expect(plan.apply({0}).after.lines.single.text, 'Hello world');
    });
  });

  group('independent timing evidence', () {
    test(
      'exact nearby evidence creates complete review and selected timing',
      () {
        final plan = useCase.build(
          draft: draft,
          reference: reference('Hello world'),
          timingEvidence: evidence,
          audioDuration: const Duration(seconds: 10),
        );
        expect(plan.hasTimingEvidence, isTrue);
        expect(plan.suggestions, isEmpty);
        expect(plan.isEmpty, isFalse);
        expect(
          plan.timedItems.single.retiming.status,
          AsrRetimingStatus.readyForReview,
        );
        final result = plan.apply({0});
        expect(result.after.lines.single.text, 'Hello world');
        expect(
          result.after.lines.single.startTime,
          const Duration(milliseconds: 2200),
        );
        expect(
          result.after.lines.single.endTime,
          const Duration(milliseconds: 4500),
        );
        expect(result.undo(), same(draft));
        expect(
          draft.lines.single.startTime,
          const Duration(milliseconds: 2100),
        );
        expect(evidence.lines.single.text, 'Hello world');
      },
    );

    test('unmatched evidence remains review-only', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world'),
        timingEvidence: document([line('Other words', 2200, 4500)]),
      );
      expect(
        plan.timedItems.single.retiming.status,
        AsrRetimingStatus.noMatchingEvidence,
      );
      expect(plan.timedItems.single.canOfferCompleteProposal, isFalse);
      expect(() => plan.apply({0}), throwsStateError);
    });

    test(
      'reference warning blocks complete application even with evidence',
      () {
        final plan = useCase.build(
          draft: draft,
          reference: reference('Hello world', warnings: ['warning']),
          timingEvidence: evidence,
        );
        expect(plan.timedItems.single.requiresManualReview, isTrue);
        expect(() => plan.apply({0}), throwsStateError);
      },
    );

    test('protected row does not produce a timed suggestion', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world'),
        timingEvidence: evidence,
        protectedDraftIndices: {0},
      );
      expect(plan.isEmpty, isTrue);
      expect(() => plan.apply({0}), throwsStateError);
    });

    test('audio duration constrains the timing proposal', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world'),
        timingEvidence: evidence,
        audioDuration: const Duration(seconds: 3),
      );
      expect(plan.timedItems.single.canOfferCompleteProposal, isFalse);
      expect(() => plan.apply({0}), throwsStateError);
    });

    test('an empty selection does not apply evidence', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world'),
        timingEvidence: evidence,
      );
      expect(() => plan.apply({}), throwsArgumentError);
      expect(draft.lines.single.text, 'Hello word');
    });

    test('timed items cannot be added or removed after review preparation', () {
      final plan = useCase.build(
        draft: draft,
        reference: reference('Hello world'),
        timingEvidence: evidence,
      );
      expect(() => plan.timedItems.clear(), throwsUnsupportedError);
    });
  });
}
