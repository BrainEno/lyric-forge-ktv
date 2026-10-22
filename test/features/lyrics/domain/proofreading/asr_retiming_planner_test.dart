import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_retiming_planner.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const planner = AsrRetimingPlanner();

  LyricLine line(String text, int start, int end, {int confidence = 90}) =>
      LyricLine(
        text: text,
        startTime: Duration(milliseconds: start),
        endTime: Duration(milliseconds: end),
        confidence: confidence,
      );

  LyricDocument doc(List<LyricLine> lines) =>
      LyricDocument(language: 'en', lines: lines);

  test('uses an exact nearby secondary-ASR interval without mutating draft', () {
    final source = line('hello word', 1000, 2500);
    final draft = doc([line('first', 0, 900), source, line('last', 4000, 5000)]);
    final evidence = doc([line('hello world', 1500, 3100)]);
    final plan = planner.plan(
      draft: draft,
      draftIndex: 1,
      proposedText: 'Hello, world!',
      timingEvidence: evidence,
    );

    expect(plan.status, AsrRetimingStatus.readyForReview);
    expect(plan.options, hasLength(1));
    expect(plan.options.single.startTime, const Duration(milliseconds: 1500));
    expect(plan.options.single.endTime, const Duration(milliseconds: 3100));
    expect(plan.options.single.evidenceLineIndices, [0]);
    expect(plan.options.single.meanConfidence, 90);
    expect(plan.canOfferForReview, isTrue);
    expect(source.text, 'hello word');
    expect(source.startTime, const Duration(milliseconds: 1000));
    expect(draft.lines[1].endTime, const Duration(milliseconds: 2500));
  });

  test('joins split secondary lines only when normalized text matches exactly', () {
    final plan = planner.plan(
      draft: doc([line('hello word', 1000, 3000)]),
      draftIndex: 0,
      proposedText: 'hello world',
      timingEvidence: doc([
        line('hello', 1100, 1800),
        line('world', 1800, 2700),
      ]),
    );

    expect(plan.status, AsrRetimingStatus.readyForReview);
    expect(plan.options.single.startTime, const Duration(milliseconds: 1100));
    expect(plan.options.single.endTime, const Duration(milliseconds: 2700));
    expect(plan.options.single.evidenceLineIndices, [0, 1]);
  });

  test('does not guess times when there is no exact nearby match', () {
    final plan = planner.plan(
      draft: doc([line('old text', 1000, 2500)]),
      draftIndex: 0,
      proposedText: 'new reference words',
      timingEvidence: doc([line('different words', 1000, 2500)]),
    );

    expect(plan.status, AsrRetimingStatus.noMatchingEvidence);
    expect(plan.options, isEmpty);
    expect(plan.canOfferForReview, isFalse);
  });

  test('marks repeated nearby matches as ambiguous instead of choosing one', () {
    final plan = planner.plan(
      draft: doc([line('old text', 1000, 4000)]),
      draftIndex: 0,
      proposedText: 'hello world',
      timingEvidence: doc([
        line('hello world', 1100, 1800),
        line('hello world', 2500, 3300),
      ]),
    );

    expect(plan.status, AsrRetimingStatus.ambiguousEvidence);
    expect(plan.options, hasLength(2));
    expect(plan.canOfferForReview, isFalse);
  });

  test('keeps low-confidence timing as non-ready evidence', () {
    final plan = planner.plan(
      draft: doc([line('old text', 1000, 2500)]),
      draftIndex: 0,
      proposedText: 'hello world',
      timingEvidence: doc([line('hello world', 1200, 2400, confidence: 35)]),
    );

    expect(plan.status, AsrRetimingStatus.lowConfidenceEvidence);
    expect(plan.options, hasLength(1));
    expect(plan.canOfferForReview, isFalse);
  });

  test('rejects intervals that conflict with neighboring rows or audio bounds', () {
    final draft = doc([
      line('previous', 0, 2000),
      line('old text', 2000, 3500),
      line('next', 3600, 5000),
    ]);
    final overlapPlan = planner.plan(
      draft: draft,
      draftIndex: 1,
      proposedText: 'hello world',
      timingEvidence: doc([line('hello world', 1800, 3700)]),
    );
    final audioPlan = planner.plan(
      draft: doc([line('old text', 1000, 2500)]),
      draftIndex: 0,
      proposedText: 'hello world',
      timingEvidence: doc([line('hello world', 8000, 9500)]),
      audioDuration: const Duration(seconds: 9),
    );

    expect(overlapPlan.status, AsrRetimingStatus.boundaryConflict);
    expect(audioPlan.status, AsrRetimingStatus.invalidTimingEvidence);
  });

  test('does not plan unchanged, empty, or protected text changes', () {
    final draft = doc([line('hello world', 1000, 2500)]);
    AsrRetimingPlan run(String text, {Set<int> protected = const {}}) =>
        planner.plan(
          draft: draft,
          draftIndex: 0,
          proposedText: text,
          timingEvidence: doc([line('hello world', 1000, 2500)]),
          protectedDraftIndices: protected,
        );

    expect(run('Hello, world!').status, AsrRetimingStatus.noTextChange);
    expect(run('   ').status, AsrRetimingStatus.invalidProposedText);
    expect(run('new text', protected: const {0}).status, AsrRetimingStatus.protectedLine);
  });

  test('rejects invalid request arguments', () {
    expect(
      () => planner.plan(
        draft: doc([line('old', 0, 1000)]),
        draftIndex: 2,
        proposedText: 'new',
        timingEvidence: doc([]),
      ),
      throwsArgumentError,
    );
  });
}
