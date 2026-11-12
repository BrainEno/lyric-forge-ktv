import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/timing_provenance.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_v2_document_composer.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_alignment_timing_applier.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_forced_alignment_planner.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricLine line(String text, int start, int end, {String? id}) => LyricLine(text: text, startTime: Duration(milliseconds: start), endTime: Duration(milliseconds: end), id: id);
ReferenceForcedTimingProposal evidence(String text, int start, int end) {
  final planner = const ReferenceForcedAlignmentPlanner();
  final prepared = planner.prepare(ReferenceLyricInput(lines: [ReferenceLyricLine(text: text)], timed: false, format: 'txt')).prepared!;
  return planner.plan(reference: prepared, spans: [ForcedAlignedSpan(text: text, start: Duration(milliseconds: start), end: Duration(milliseconds: end))], audioDuration: const Duration(seconds: 60)).proposals.single;
}
LyricProofreadV2ReviewItem row({required int index, required LyricLine proposed, LyricLine? original, int? source, LyricProofreadReviewVerdict verdict = LyricProofreadReviewVerdict.amber, ReferenceForcedTimingProposal? timing}) => LyricProofreadV2ReviewItem(proposalIndex: index, sourceIndex: source, originalLine: original, proposedLine: proposed, verdict: verdict, referenceTimingEvidence: timing);
LyricProofreadV2Selection choice({Set<int> accept = const {}, Set<int> timings = const {}, Set<int> restore = const {}}) => LyricProofreadV2Selection(acceptedProposalIndices: accept, restoredDraftIndices: restore, acceptedReferenceTimingIndices: timings);

void main() {
  const composer = ProofreadV2DocumentComposer();
  const applier = ReferenceAlignmentTimingApplier();
  LyricDocument compose({required LyricDocument before, required List<LyricProofreadV2ReviewItem> items, LyricProofreadV2Selection? selection, List<LyricProofreadV2DroppedItem> dropped = const [], LyricSourceStrategy strategy = LyricSourceStrategy.referenceFirst}) => composer.compose(
    before: before,
    proposalDocument: before.copyWith(lines: items.map((item) => item.proposedLine).toList()),
    items: items, droppedItems: dropped, selection: selection ?? choice(), effectiveStrategy: strategy,
  );

  group('explicit per-line timing selection', () {
    test('no choice keeps source timestamp and metadata unchanged', () {
      final source = LyricDocument(language: 'en', lines: [line('hello', 0, 1000, id: 'a')], metadata: const {'timingProvenance': {'a': 'manual'}});
      final snapshot = jsonEncode(source.toJson());
      final result = compose(before: source, items: [row(index: 0, source: 0, original: source.lines.first, proposed: source.lines.first, timing: evidence('hello', 2000, 3000))]);
      expect(result.toJson(), source.toJson());
      expect(jsonEncode(source.toJson()), snapshot);
    });

    test('selected alignment changes timing only, with persistent provenance', () {
      final source = LyricDocument(language: 'en', lines: [line('hello', 0, 1000, id: 'a'), line('world', 5000, 6000, id: 'b')], metadata: const {'timingProvenance': {'a': 'manual', 'b': 'mappedAsr'}, 'other': 'keep'});
      final snapshot = jsonEncode(source.toJson());
      final result = compose(before: source, items: [
        row(index: 0, source: 0, original: source.lines[0], proposed: source.lines[0], timing: evidence('hello', 2000, 3000)),
        row(index: 1, source: 1, original: source.lines[1], proposed: source.lines[1], timing: evidence('world', 7000, 8000)),
      ], selection: choice(timings: {0}));
      expect(result.lines[0].text, 'hello');
      expect(result.lines[0].startTime, const Duration(seconds: 2));
      expect(result.lines[0].endTime, const Duration(seconds: 3));
      expect(result.lines[1].toJson(), source.lines[1].toJson());
      expect(result.metadata['timingProvenance'], {'a': 'forcedAlignmentReference', 'b': 'mappedAsr'});
      expect(result.metadata['other'], 'keep');
      expect(jsonEncode(source.toJson()), snapshot);
      expect(LyricTimingProvenance.fromName('forcedAlignmentReference'), LyricTimingProvenance.forcedAlignmentReference);
      final roundtrip = LyricDocument.fromJson(jsonDecode(jsonEncode(result.toJson())) as Map<String, dynamic>);
      expect(roundtrip.metadata['timingProvenance'], result.metadata['timingProvenance']);
    });

    test('absolute evidence is represented relative to nonzero global offset', () {
      for (final offset in [500, -500]) {
        final source = LyricDocument(language: 'en', globalOffset: Duration(milliseconds: offset), lines: [line('hello', 2000, 3000, id: 'a')]);
        final result = compose(before: source, items: [row(index: 0, source: 0, original: source.lines.first, proposed: source.lines.first, timing: evidence('hello', 4000, 4500))], selection: choice(timings: {0}));
        expect(result.globalOffset, source.globalOffset);
        expect(result.lines.single.startTime + result.globalOffset!, const Duration(seconds: 4));
        expect(result.lines.single.endTime + result.globalOffset!, const Duration(milliseconds: 4500));
      }
    });

    test('multiple selections preserve order, other fields and independent provenance', () {
      final source = LyricDocument(language: 'en', lines: [line('same', 0, 500, id: 'a'), line('same', 3000, 3500, id: 'b'), line('end', 6000, 6500, id: 'c')]);
      final result = compose(before: source, items: [
        row(index: 9, source: 0, original: source.lines[0], proposed: source.lines[0], timing: evidence('same', 1000, 1500)),
        row(index: 4, source: 1, original: source.lines[1], proposed: source.lines[1], timing: evidence('same', 4000, 4500)),
        row(index: 2, source: 2, original: source.lines[2], proposed: source.lines[2]),
      ], selection: choice(timings: {9, 4}));
      expect(result.lines.map((l) => l.id), ['a', 'b', 'c']);
      expect(result.lines.map((l) => l.startTime.inMilliseconds), [1000, 4000, 6000]);
      expect(result.metadata['timingProvenance'], {'a': 'forcedAlignmentReference', 'b': 'forcedAlignmentReference'});
    });

    test('new accepted reference line gets an ID and timing provenance', () {
      final source = LyricDocument(language: 'en', lines: [line('first', 0, 500, id: 'a')]);
      final added = line('added', 1000, 2000);
      final result = compose(before: source, items: [
        row(index: 0, source: 0, original: source.lines.first, proposed: source.lines.first),
        row(index: 1, proposed: added, timing: evidence('added', 2200, 2600)),
      ], selection: choice(accept: {1}, timings: {1}));
      expect(result.lines, hasLength(2));
      expect(result.lines[1].id, isNotNull);
      expect(result.lines[1].startTime, const Duration(milliseconds: 2200));
      expect((result.metadata['timingProvenance'] as Map)[result.lines[1].id], 'forcedAlignmentReference');
    });

    test('reinserted dropped rows cannot shift the target identity', () {
      final source = LyricDocument(language: 'en', lines: [line('old', 0, 1000, id: 'a'), line('later', 4000, 5000, id: 'b')]);
      final result = compose(before: source, items: [row(index: 3, source: 1, original: source.lines[1], proposed: source.lines[1], timing: evidence('later', 6000, 7000))], dropped: [LyricProofreadV2DroppedItem(sourceIndex: 0, line: source.lines[0])], selection: choice(timings: {3}, restore: {0}));
      expect(result.lines.map((l) => l.id), ['a', 'b']);
      expect(result.lines.first.startTime, Duration.zero);
      expect(result.lines.last.startTime, const Duration(seconds: 6));
      expect(result.metadata['timingProvenance'], {'b': 'forcedAlignmentReference'});
    });

    test('if the evidence matches existing timing it does not relabel provenance', () {
      final source = LyricDocument(language: 'en', lines: [line('a', 1000, 2000, id: 'a')], metadata: const {'timingProvenance': {'a': 'manual'}});
      final result = compose(before: source, items: [row(index: 0, source: 0, original: source.lines[0], proposed: source.lines[0], timing: evidence('a', 1000, 2000))], selection: choice(timings: {0}));
      expect(result.metadata['timingProvenance'], {'a': 'manual'});
      expect(composer.isDifferent(source, result), isFalse);
    });
  });

  group('fail closed instead of guessing', () {
    late LyricDocument source;
    late LyricProofreadV2ReviewItem valid;
    setUp(() {
      source = LyricDocument(language: 'en', lines: [line('hello', 0, 1000, id: 'a')]);
      valid = row(index: 0, source: 0, original: source.lines.first, proposed: source.lines.first, timing: evidence('hello', 2000, 3000));
    });
    void fails(ReferenceTimingApplyFailure reason, void Function() action) => expect(action, throwsA(isA<ReferenceTimingApplyException>().having((e) => e.reason, 'reason', reason)));

    test('unknown choices, duplicate proposal ids and wrong strategy are rejected', () {
      fails(ReferenceTimingApplyFailure.unknownSelection, () => compose(before: source, items: [valid], selection: choice(timings: {1})));
      fails(ReferenceTimingApplyFailure.duplicateProposal, () => compose(before: source, items: [valid, valid], selection: choice(timings: {0})));
      fails(ReferenceTimingApplyFailure.wrongStrategy, () => compose(before: source, items: [valid], selection: choice(timings: {0}), strategy: LyricSourceStrategy.asrFirst));
    });

    test('locked rows and nonexistent evidence are rejected even for forged selection', () {
      fails(ReferenceTimingApplyFailure.protectedLine, () => compose(before: source, items: [row(index: 0, source: 0, original: source.lines.first, proposed: source.lines.first, verdict: LyricProofreadReviewVerdict.locked, timing: evidence('hello', 2000, 3000))], selection: choice(timings: {0})));
      fails(ReferenceTimingApplyFailure.missingEvidence, () => compose(before: source, items: [row(index: 0, source: 0, original: source.lines.first, proposed: source.lines.first)], selection: choice(timings: {0})));
    });

    test('rejected changed text cannot receive a different reference alignment', () {
      final item = row(index: 0, source: 0, original: source.lines.first, proposed: line('other', 0, 1000, id: 'a'), timing: evidence('other', 2000, 3000));
      fails(ReferenceTimingApplyFailure.textMismatch, () => compose(before: source, items: [item], selection: choice(timings: {0})));
      final accepted = compose(before: source, items: [item], selection: choice(accept: {0}, timings: {0}));
      expect(accepted.lines.first.text, 'other');
      expect(accepted.lines.first.startTime, const Duration(seconds: 2));
    });

    test('an unaccepted inserted row never materializes', () {
      final inserted = row(index: 1, proposed: line('extra', 1000, 2000), timing: evidence('extra', 2000, 3000));
      fails(ReferenceTimingApplyFailure.unacceptedInsertion, () => compose(before: source, items: [valid, inserted], selection: choice(timings: {1})));
      expect(source.lines, hasLength(1));
    });

    test('duplicate IDs, negative stored time and changed offset are rejected', () {
      final duplicate = LyricDocument(language: 'en', lines: [line('hello', 0, 1000, id: 'a'), line('other', 2000, 3000, id: 'a')]);
      fails(ReferenceTimingApplyFailure.ambiguousLineIdentity, () => compose(before: duplicate, items: [row(index: 0, source: 0, original: duplicate.lines.first, proposed: duplicate.lines.first, timing: evidence('hello', 2000, 3000)), row(index: 1, source: 1, original: duplicate.lines.last, proposed: duplicate.lines.last)], selection: choice(timings: {0})));
      final offset = source.copyWith(globalOffset: const Duration(seconds: 4));
      fails(ReferenceTimingApplyFailure.negativeStoredTime, () => compose(before: offset, items: [valid], selection: choice(timings: {0})));
      final changed = row(index: 0, source: 0, original: offset.lines.first, proposed: line('hello', 500, 1500, id: 'a'), timing: evidence('hello', 2000, 3000));
      fails(ReferenceTimingApplyFailure.offsetChanged, () => compose(before: offset, items: [changed], selection: choice(accept: {0}, timings: {0})));
    });

    test('ordinary partial reference timing cannot move unselected rows via offset reset', () {
      final before = LyricDocument(language: 'en', globalOffset: const Duration(milliseconds: 500), lines: [line('a', 1000, 2000, id: 'a'), line('b', 3000, 4000, id: 'b')]);
      final items = [row(index: 0, source: 0, original: before.lines[0], proposed: line('a', 1500, 2500, id: 'a')), row(index: 1, source: 1, original: before.lines[1], proposed: before.lines[1])];
      fails(ReferenceTimingApplyFailure.offsetChanged, () => compose(before: before, items: items, selection: choice(accept: {0})));
      fails(ReferenceTimingApplyFailure.offsetChanged, () => compose(before: before, items: items, selection: choice(accept: {0, 1})));
      expect(before.lines[1].startTime + before.globalOffset!, const Duration(milliseconds: 3500));
    });

    test('missing or duplicated composed mapping is rejected', () {
      fails(ReferenceTimingApplyFailure.ambiguousLineIdentity, () => applier.apply(before: source, composed: source, items: [valid], selection: choice(timings: {0}), effectiveStrategy: LyricSourceStrategy.referenceFirst, outputIndexByProposal: {}));
      final second = row(index: 1, source: 0, original: source.lines.first, proposed: source.lines.first, timing: evidence('hello', 4000, 5000));
      fails(ReferenceTimingApplyFailure.ambiguousLineIdentity, () => applier.apply(before: source, composed: source, items: [valid, second], selection: choice(timings: {0, 1}), effectiveStrategy: LyricSourceStrategy.referenceFirst, outputIndexByProposal: {0: 0, 1: 0}));
    });
  });
}
