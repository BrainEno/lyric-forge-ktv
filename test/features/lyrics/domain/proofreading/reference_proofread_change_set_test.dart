import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_reference_correction_suggester.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_retiming_planner.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_proofread_change_set.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_proofread_review_builder.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_alignment_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const changeSet = ReferenceProofreadChangeSet();

  LyricLine line(String text, int start, int end) => LyricLine(
        text: text,
        startTime: Duration(milliseconds: start),
        endTime: Duration(milliseconds: end),
      );

  LyricDocument document(List<LyricLine> lines) =>
      LyricDocument(language: 'en', lines: lines, globalOffset: const Duration(milliseconds: 25),
          metadata: const {'source': 'test'});

  ReferenceProofreadReviewItem proposal({
    required int index,
    required String before,
    required String after,
    required int start,
    required int end,
    bool ready = true,
  }) {
    final correction = AsrReferenceCorrectionSuggestion(
      draftIndex: index,
      referenceIndex: index,
      currentText: before,
      suggestedText: after,
      similarity: 0.9,
      alignmentStatus: AsrLineAlignmentStatus.toBeCorrected,
      reasons: const {AsrReferenceCorrectionReason.textMismatch},
    );
    final timing = AsrRetimingPlan(
      draftIndex: index,
      proposedText: after,
      status: ready ? AsrRetimingStatus.readyForReview : AsrRetimingStatus.ambiguousEvidence,
      options: [
        AsrRetimingOption(
          startTime: Duration(milliseconds: start),
          endTime: Duration(milliseconds: end),
          evidenceLineIndices: const [0],
          meanConfidence: 95,
        ),
      ],
      reasons: const {AsrRetimingReason.exactTimedTextMatch},
    );
    return ReferenceProofreadReviewItem(correction: correction, retiming: timing);
  }

  test('diff exposes before and after text and timing without mutation', () {
    final draft = document([line('Hello word', 1000, 2000)]);
    final item = proposal(index: 0, before: 'Hello word', after: 'Hello world',
        start: 1100, end: 2100);

    final rows = changeSet.diff(draft, [item]);

    expect(rows, hasLength(1));
    expect(rows.single.beforeText, 'Hello word');
    expect(rows.single.afterText, 'Hello world');
    expect(rows.single.beforeStart, const Duration(milliseconds: 1000));
    expect(rows.single.afterStart, const Duration(milliseconds: 1100));
    expect(rows.single.canApply, isTrue);
    expect(draft.lines.single.text, 'Hello word');
  });

  test('batch apply is atomic and undo restores the original document', () {
    final draft = document([
      line('Hello word', 1000, 2000),
      line('Next line', 3000, 4000),
    ]);
    final first = proposal(index: 0, before: 'Hello word', after: 'Hello world',
        start: 1100, end: 2100);
    final second = proposal(index: 1, before: 'Next line', after: 'Next verse',
        start: 3100, end: 4100);

    final applied = changeSet.apply(
      draft: draft,
      proposals: [first, second],
      selectedDraftIndices: const {0, 1},
    );

    expect(applied.after.lines[0].text, 'Hello world');
    expect(applied.after.lines[0].startTime, const Duration(milliseconds: 1100));
    expect(applied.after.lines[1].text, 'Next verse');
    expect(applied.changedDraftIndices, [0, 1]);
    expect(applied.undo(), same(draft));
    expect(applied.redo(), same(applied.after));
    expect(draft.lines[0].text, 'Hello word');
    expect(applied.after.globalOffset, draft.globalOffset);
    expect(applied.after.metadata, same(draft.metadata));
  });

  test('rejects the whole batch when any selected proposal is stale', () {
    final draft = document([
      line('Hello newer', 1000, 2000),
      line('Next line', 3000, 4000),
    ]);
    final first = proposal(index: 0, before: 'Hello word', after: 'Hello world',
        start: 1100, end: 2100);
    final second = proposal(index: 1, before: 'Next line', after: 'Next verse',
        start: 3100, end: 4100);

    expect(
      () => changeSet.apply(
        draft: draft,
        proposals: [first, second],
        selectedDraftIndices: const {0, 1},
      ),
      throwsStateError,
    );
    expect(draft.lines[1].text, 'Next line');
  });

  test('rejects protected or manually reviewed proposals', () {
    final draft = document([line('Hello word', 1000, 2000)]);
    final item = proposal(index: 0, before: 'Hello word', after: 'Hello world',
        start: 1100, end: 2100);

    expect(
      () => changeSet.apply(
        draft: draft,
        proposals: [item],
        selectedDraftIndices: const {0},
        protectedDraftIndices: const {0},
      ),
      throwsStateError,
    );
    expect(
      () => changeSet.apply(
        draft: draft,
        proposals: [proposal(index: 0, before: 'Hello word', after: 'Hello world',
            start: 1100, end: 2100, ready: false)],
        selectedDraftIndices: const {0},
      ),
      throwsStateError,
    );
  });

  test('rejects a batch whose combined timing overlaps', () {
    final draft = document([
      line('First word', 1000, 2000),
      line('Second word', 3000, 4000),
    ]);
    final first = proposal(index: 0, before: 'First word', after: 'First verse',
        start: 2500, end: 3300);
    final second = proposal(index: 1, before: 'Second word', after: 'Second verse',
        start: 3100, end: 3800);

    expect(
      () => changeSet.apply(
        draft: draft,
        proposals: [first, second],
        selectedDraftIndices: const {0, 1},
      ),
      throwsStateError,
    );
    expect(draft.lines[0].text, 'First word');
    expect(draft.lines[1].text, 'Second word');
  });
}
