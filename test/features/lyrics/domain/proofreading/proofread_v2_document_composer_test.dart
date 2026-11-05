import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_v2_document_composer.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const composer = ProofreadV2DocumentComposer();

  LyricLine line(
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

  LyricProofreadV2ReviewItem item({
    required int proposalIndex,
    required int? sourceIndex,
    required LyricLine proposed,
    required LyricLine? original,
    required LyricProofreadReviewVerdict verdict,
  }) => LyricProofreadV2ReviewItem(
    proposalIndex: proposalIndex,
    sourceIndex: sourceIndex,
    proposedLine: proposed,
    originalLine: original,
    verdict: verdict,
  );

  LyricProofreadV2Selection selection({
    Set<int> accepted = const {},
    Set<int> restored = const {},
  }) => LyricProofreadV2Selection(
    acceptedProposalIndices: accepted,
    restoredDraftIndices: restored,
  );

  group('compose', () {
    test('accepting a proposal replaces the draft line in place', () {
      final before = LyricDocument(
        language: 'en',
        lines: [
          line('first', 0, 1000, id: 'a'),
          line('typo line', 1000, 2000, id: 'b'),
          line('third', 2000, 3000, id: 'c'),
        ],
      );
      final proposal = before.copyWith(
        lines: [
          line('first', 0, 1000, id: 'a'),
          line('fixed line', 1000, 2000, id: 'b'),
          line('third', 2000, 3000, id: 'c'),
        ],
      );

      final after = composer.compose(
        before: before,
        proposalDocument: proposal,
        items: [
          item(
            proposalIndex: 0,
            sourceIndex: 0,
            proposed: proposal.lines[0],
            original: before.lines[0],
            verdict: LyricProofreadReviewVerdict.green,
          ),
          item(
            proposalIndex: 1,
            sourceIndex: 1,
            proposed: proposal.lines[1],
            original: before.lines[1],
            verdict: LyricProofreadReviewVerdict.green,
          ),
          item(
            proposalIndex: 2,
            sourceIndex: 2,
            proposed: proposal.lines[2],
            original: before.lines[2],
            verdict: LyricProofreadReviewVerdict.green,
          ),
        ],
        droppedItems: const [],
        selection: selection(accepted: {1}),
        effectiveStrategy: LyricSourceStrategy.asrFirst,
      );

      expect(after.lines.map((line) => line.text), [
        'first',
        'fixed line',
        'third',
      ]);
      expect(after.lines.map((line) => line.id), ['a', 'b', 'c']);
    });

    test('an unaccepted proposal keeps the draft text and timing', () {
      final before = LyricDocument(
        language: 'en',
        lines: [line('draft text', 1000, 2000, id: 'a')],
      );
      final proposal = before.copyWith(
        lines: [line('proposed text', 0, 500, id: 'a')],
      );

      final after = composer.compose(
        before: before,
        proposalDocument: proposal,
        items: [
          item(
            proposalIndex: 0,
            sourceIndex: 0,
            proposed: proposal.lines[0],
            original: before.lines[0],
            verdict: LyricProofreadReviewVerdict.green,
          ),
        ],
        droppedItems: const [],
        selection: selection(),
        effectiveStrategy: LyricSourceStrategy.asrFirst,
      );

      expect(after.lines.single.text, 'draft text');
      expect(after.lines.single.startTime, before.lines.single.startTime);
    });

    test('a locked row applies without being accepted', () {
      final before = LyricDocument(
        language: 'en',
        lines: [line('locked original', 0, 1000, id: 'a')],
      );
      final proposal = before.copyWith(
        lines: [line('locked proposal', 0, 1000, id: 'a')],
      );

      final after = composer.compose(
        before: before,
        proposalDocument: proposal,
        items: [
          item(
            proposalIndex: 0,
            sourceIndex: 0,
            proposed: proposal.lines[0],
            original: before.lines[0],
            verdict: LyricProofreadReviewVerdict.locked,
          ),
        ],
        droppedItems: const [],
        selection: selection(),
        effectiveStrategy: LyricSourceStrategy.asrFirst,
      );

      expect(after.lines.single.text, 'locked proposal');
    });

    test(
      'a new proposal without a draft source is appended in review order',
      () {
        final before = LyricDocument(
          language: 'en',
          lines: [
            line('first', 0, 1000, id: 'a'),
            line('third', 2000, 3000, id: 'c'),
          ],
        );
        final proposal = before.copyWith(
          lines: [
            line('first', 0, 1000, id: 'a'),
            line('second', 1000, 2000, id: 'b'),
            line('third', 2000, 3000, id: 'c'),
          ],
        );

        final after = composer.compose(
          before: before,
          proposalDocument: proposal,
          items: [
            item(
              proposalIndex: 0,
              sourceIndex: 0,
              proposed: proposal.lines[0],
              original: before.lines[0],
              verdict: LyricProofreadReviewVerdict.green,
            ),
            item(
              proposalIndex: 1,
              sourceIndex: null,
              proposed: proposal.lines[1],
              original: null,
              verdict: LyricProofreadReviewVerdict.amber,
            ),
            item(
              proposalIndex: 2,
              sourceIndex: 1,
              proposed: proposal.lines[2],
              original: before.lines[1],
              verdict: LyricProofreadReviewVerdict.green,
            ),
          ],
          droppedItems: const [],
          selection: selection(accepted: {1}),
          effectiveStrategy: LyricSourceStrategy.referenceFirst,
        );

        expect(after.lines.map((line) => line.text), [
          'first',
          'second',
          'third',
        ]);
      },
    );

    test('a dropped draft line is removed unless the user restored it', () {
      final before = LyricDocument(
        language: 'en',
        lines: [
          line('keep one', 0, 1000, id: 'a'),
          line('noise', 1000, 2000, id: 'b'),
          line('keep two', 2000, 3000, id: 'c'),
        ],
      );
      final proposal = before.copyWith(
        lines: [
          line('keep one', 0, 1000, id: 'a'),
          line('keep two', 2000, 3000, id: 'c'),
        ],
      );
      final items = [
        item(
          proposalIndex: 0,
          sourceIndex: 0,
          proposed: proposal.lines[0],
          original: before.lines[0],
          verdict: LyricProofreadReviewVerdict.green,
        ),
        item(
          proposalIndex: 1,
          sourceIndex: 2,
          proposed: proposal.lines[1],
          original: before.lines[2],
          verdict: LyricProofreadReviewVerdict.green,
        ),
      ];
      final dropped = [
        LyricProofreadV2DroppedItem(sourceIndex: 1, line: before.lines[1]),
      ];

      final withoutRestore = composer.compose(
        before: before,
        proposalDocument: proposal,
        items: items,
        droppedItems: dropped,
        selection: selection(),
        effectiveStrategy: LyricSourceStrategy.referenceFirst,
      );
      expect(withoutRestore.lines.map((line) => line.text), [
        'keep one',
        'keep two',
      ]);

      final restored = composer.compose(
        before: before,
        proposalDocument: proposal,
        items: items,
        droppedItems: dropped,
        selection: selection(restored: {1}),
        effectiveStrategy: LyricSourceStrategy.referenceFirst,
      );
      expect(restored.lines.map((line) => line.text), [
        'keep one',
        'noise',
        'keep two',
      ]);
      expect(restored.lines.map((line) => line.id), ['a', 'b', 'c']);
    });

    test(
      'a restored line is re-inserted by timestamp, not by review order',
      () {
        final before = LyricDocument(
          language: 'en',
          lines: [
            line('late proposal', 5000, 6000, id: 'a'),
            line('early restored', 1000, 2000, id: 'b'),
          ],
        );
        final proposal = before.copyWith(lines: [before.lines[0]]);

        final after = composer.compose(
          before: before,
          proposalDocument: proposal,
          items: [
            item(
              proposalIndex: 0,
              sourceIndex: 0,
              proposed: proposal.lines[0],
              original: before.lines[0],
              verdict: LyricProofreadReviewVerdict.green,
            ),
          ],
          droppedItems: [
            LyricProofreadV2DroppedItem(sourceIndex: 1, line: before.lines[1]),
          ],
          selection: selection(restored: {1}),
          effectiveStrategy: LyricSourceStrategy.referenceFirst,
        );

        expect(after.lines.map((line) => line.text), [
          'early restored',
          'late proposal',
        ]);
      },
    );

    test('reference-first timing changes reset the global offset', () {
      final before = LyricDocument(
        language: 'en',
        lines: [line('text', 5000, 6000, id: 'a')],
        globalOffset: const Duration(milliseconds: 400),
      );
      final proposal = before.copyWith(
        lines: [line('text', 1000, 2000, id: 'a')],
      );

      final after = composer.compose(
        before: before,
        proposalDocument: proposal,
        items: [
          item(
            proposalIndex: 0,
            sourceIndex: 0,
            proposed: proposal.lines[0],
            original: before.lines[0],
            verdict: LyricProofreadReviewVerdict.green,
          ),
        ],
        droppedItems: const [],
        selection: selection(accepted: {0}),
        effectiveStrategy: LyricSourceStrategy.referenceFirst,
      );

      expect(after.globalOffset, Duration.zero);
    });

    test('a text-only reference change keeps the global offset', () {
      final before = LyricDocument(
        language: 'en',
        lines: [line('text', 1000, 2000, id: 'a')],
        globalOffset: const Duration(milliseconds: 400),
      );
      final proposal = before.copyWith(
        lines: [line('fixed text', 1000, 2000, id: 'a')],
      );

      final after = composer.compose(
        before: before,
        proposalDocument: proposal,
        items: [
          item(
            proposalIndex: 0,
            sourceIndex: 0,
            proposed: proposal.lines[0],
            original: before.lines[0],
            verdict: LyricProofreadReviewVerdict.green,
          ),
        ],
        droppedItems: const [],
        selection: selection(accepted: {0}),
        effectiveStrategy: LyricSourceStrategy.referenceFirst,
      );

      expect(after.globalOffset, before.globalOffset);
    });

    test('an ASR-first timing change never touches the global offset', () {
      final before = LyricDocument(
        language: 'en',
        lines: [line('text', 5000, 6000, id: 'a')],
        globalOffset: const Duration(milliseconds: 400),
      );
      final proposal = before.copyWith(
        lines: [line('text', 1000, 2000, id: 'a')],
      );

      final after = composer.compose(
        before: before,
        proposalDocument: proposal,
        items: [
          item(
            proposalIndex: 0,
            sourceIndex: 0,
            proposed: proposal.lines[0],
            original: before.lines[0],
            verdict: LyricProofreadReviewVerdict.green,
          ),
        ],
        droppedItems: const [],
        selection: selection(accepted: {0}),
        effectiveStrategy: LyricSourceStrategy.asrFirst,
      );

      expect(after.globalOffset, before.globalOffset);
    });

    test('timing provenance follows only the ids that survive the edit', () {
      final before = LyricDocument(
        language: 'en',
        lines: [
          line('kept', 0, 1000, id: 'keep'),
          line('changed', 1000, 2000, id: 'change'),
          line('removed', 2000, 3000, id: 'gone'),
        ],
        metadata: {
          'timingProvenance': {
            'keep': 'reference',
            'change': 'reference',
            'gone': 'reference',
          },
        },
      );
      final proposal = before.copyWith(
        lines: [
          line('kept', 0, 1000, id: 'keep'),
          line('changed', 1100, 2100, id: 'change'),
          line('removed', 2000, 3000, id: 'gone'),
        ],
        metadata: {
          'timingProvenance': {'keep': 'reference', 'change': 'asrRetimed'},
        },
      );

      final after = composer.compose(
        before: before,
        proposalDocument: proposal,
        items: [
          item(
            proposalIndex: 0,
            sourceIndex: 0,
            proposed: proposal.lines[0],
            original: before.lines[0],
            verdict: LyricProofreadReviewVerdict.green,
          ),
          item(
            proposalIndex: 1,
            sourceIndex: 1,
            proposed: proposal.lines[1],
            original: before.lines[1],
            verdict: LyricProofreadReviewVerdict.green,
          ),
        ],
        droppedItems: [
          LyricProofreadV2DroppedItem(sourceIndex: 2, line: before.lines[2]),
        ],
        selection: selection(accepted: {0, 1}),
        effectiveStrategy: LyricSourceStrategy.referenceFirst,
      );

      expect(after.metadata['timingProvenance'], {
        'keep': 'reference',
        'change': 'asrRetimed',
      });
    });

    test('lines without an id get one so later edits can track them', () {
      final before = LyricDocument(
        language: 'en',
        lines: [line('text', 0, 1000)],
      );

      final after = composer.compose(
        before: before,
        proposalDocument: before,
        items: [
          item(
            proposalIndex: 0,
            sourceIndex: 0,
            proposed: before.lines[0],
            original: before.lines[0],
            verdict: LyricProofreadReviewVerdict.green,
          ),
        ],
        droppedItems: const [],
        selection: selection(),
        effectiveStrategy: LyricSourceStrategy.asrFirst,
      );

      expect(after.lines.single.id, isNotNull);
    });
  });

  group('isDifferent', () {
    final base = LyricDocument(
      language: 'en',
      lines: [line('text', 1000, 2000, id: 'a')],
    );

    test('is false for an identical document', () {
      expect(composer.isDifferent(base, base.copyWith()), isFalse);
    });

    test('detects text, timing, confidence and offset changes', () {
      expect(
        composer.isDifferent(
          base,
          base.copyWith(lines: [base.lines.single.copyWith(text: 'other')]),
        ),
        isTrue,
      );
      expect(
        composer.isDifferent(
          base,
          base.copyWith(
            lines: [
              base.lines.single.copyWith(
                endTime: const Duration(milliseconds: 2500),
              ),
            ],
          ),
        ),
        isTrue,
      );
      expect(
        composer.isDifferent(
          base,
          base.copyWith(lines: [base.lines.single.copyWith(confidence: 42)]),
        ),
        isTrue,
      );
      expect(
        composer.isDifferent(
          base,
          base.copyWith(globalOffset: const Duration(milliseconds: 100)),
        ),
        isTrue,
      );
    });

    test('detects added and removed lines', () {
      final longer = base.copyWith(
        lines: [
          ...base.lines,
          line('extra', 2000, 3000, id: 'b'),
        ],
      );

      expect(composer.isDifferent(base, longer), isTrue);
      expect(composer.isDifferent(longer, base), isTrue);
    });
  });
}
