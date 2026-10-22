import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_retiming_planner.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const planner = AsrRetimingPlanner();
  LyricLine line(String text, int start, int end, {int confidence = 90}) =>
      LyricLine(text: text, startTime: Duration(milliseconds: start),
        endTime: Duration(milliseconds: end), confidence: confidence);
  LyricDocument doc(List<LyricLine> lines) => LyricDocument(language: 'en', lines: lines);

  test('plans an exact nearby timed match without mutating the draft', () {
    final source = line('hello word', 1000, 2500);
    final draft = doc([line('first', 0, 900), source, line('last', 4000, 5000)]);
    final result = planner.plan(draft: draft, draftIndex: 1, proposedText: 'Hello, world!',
      timingEvidence: doc([line('hello world', 1500, 3100)]));

    expect(result.status, AsrRetimingStatus.readyForReview);
    expect(result.options.single.startTime, const Duration(milliseconds: 1500));
    expect(result.options.single.endTime, const Duration(milliseconds: 3100));
    expect(result.canOfferForReview, isTrue);
    expect(source.text, 'hello word');
    expect(source.startTime, const Duration(milliseconds: 1000));
  });

  test('joins split secondary lines only for an exact normalized match', () {
    final result = planner.plan(draft: doc([line('hello word', 1000, 3000)]),
      draftIndex: 0, proposedText: 'hello world',
      timingEvidence: doc([line('hello', 1100, 1800), line('world', 1800, 2700)]));

    expect(result.status, AsrRetimingStatus.readyForReview);
    expect(result.options.single.startTime, const Duration(milliseconds: 1100));
    expect(result.options.single.endTime, const Duration(milliseconds: 2700));
    expect(result.options.single.evidenceLineIndices, [0, 1]);
  });

  test('refuses missing and ambiguous timing evidence', () {
    final draft = doc([line('old text', 1000, 4000)]);
    final missing = planner.plan(draft: draft, draftIndex: 0, proposedText: 'new words',
      timingEvidence: doc([line('different words', 1000, 2500)]));
    final ambiguous = planner.plan(draft: draft, draftIndex: 0, proposedText: 'hello world',
      timingEvidence: doc([line('hello world', 1100, 1800), line('hello world', 2500, 3300)]));

    expect(missing.status, AsrRetimingStatus.noMatchingEvidence);
    expect(ambiguous.status, AsrRetimingStatus.ambiguousEvidence);
    expect(ambiguous.options, hasLength(2));
    expect(ambiguous.canOfferForReview, isFalse);
  });

  test('low confidence timing is not marked ready', () {
    final result = planner.plan(draft: doc([line('old text', 1000, 2500)]),
      draftIndex: 0, proposedText: 'hello world',
      timingEvidence: doc([line('hello world', 1200, 2400, confidence: 35)]));

    expect(result.status, AsrRetimingStatus.lowConfidenceEvidence);
    expect(result.options, hasLength(1));
    expect(result.canOfferForReview, isFalse);
  });

  test('rejects timing that overlaps neighbors or exceeds audio duration', () {
    final overlap = planner.plan(
      draft: doc([line('previous', 0, 2000), line('old text', 2000, 3500), line('next', 3600, 5000)]),
      draftIndex: 1, proposedText: 'hello world',
      timingEvidence: doc([line('hello world', 1800, 3700)]));
    final audio = planner.plan(draft: doc([line('old text', 7000, 8500)]),
      draftIndex: 0, proposedText: 'hello world',
      timingEvidence: doc([line('hello world', 8000, 9500)]),
      audioDuration: const Duration(seconds: 9));

    expect(overlap.status, AsrRetimingStatus.boundaryConflict);
    expect(audio.status, AsrRetimingStatus.invalidTimingEvidence);
  });

  test('does not plan unchanged, empty, or protected text changes', () {
    final draft = doc([line('hello world', 1000, 2500)]);
    AsrRetimingPlan run(String text, {Set<int> protected = const {}}) => planner.plan(
      draft: draft, draftIndex: 0, proposedText: text,
      timingEvidence: doc([line('hello world', 1000, 2500)]),
      protectedDraftIndices: protected);

    expect(run('Hello, world!').status, AsrRetimingStatus.noTextChange);
    expect(run(' ').status, AsrRetimingStatus.invalidProposedText);
    expect(run('new text', protected: const {0}).status, AsrRetimingStatus.protectedLine);
    expect(() => run('new', protected: const {1}), throwsArgumentError);
    expect(() => planner.plan(draft: draft, draftIndex: 2, proposedText: 'new',
      timingEvidence: doc([])), throwsArgumentError);
  });
}
