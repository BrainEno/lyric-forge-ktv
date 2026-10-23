import 'package:flutter_test/flutter_test.dart';
import 'helpers/proofread_pipeline_invariants.dart' as invariants;
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_first_pipeline.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_result.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const pipeline = AsrFirstPipeline();

  LyricLine row(
    String text,
    int start,
    int end, {
    String? id,
    int confidence = 90,
  }) =>
      LyricLine(
        text: text,
        startTime: Duration(milliseconds: start),
        endTime: Duration(milliseconds: end),
        id: id,
        confidence: confidence,
      );

  LyricDocument doc(List<LyricLine> lines) =>
      LyricDocument(language: 'en', lines: lines);

  void expectSharedInvariants({
    required LyricDocument source,
    required String sourceSnapshot,
    required ProofreadResult result,
    Set<int> protectedSourceIndices = const {},
    Duration? audioDuration,
  }) {
    invariants.expectInvariants(
      source: source,
      sourceSnapshot: sourceSnapshot,
      proposedDocument: result.proposedDocument,
      rows: [
        for (var index = 0; index < result.lines.length; index++)
          invariants.ProofreadInvariantRow(
            line: result.lines[index].line,
            lineId: result.lines[index].lineId,
            isLocked: result.lines[index].verdict == ProofreadVerdict.locked,
            sourceIndex: index,
            timingConflict: result.lines[index].reasons.contains(
              ProofreadReason.timingConflict,
            ),
          ),
      ],
      protectedSourceIndices: protectedSourceIndices,
      audioDuration: audioDuration,
    );
  }

  test('without secondary ASR, preserves draft and marks rows for review', () {
    final original = doc([row('first lyric', 0, 1000, id: 'one')]);
    final originalSnapshot = invariants.snapshotDocument(original);
    final result = pipeline.build(draft: original);
    expectSharedInvariants(
      source: original,
      sourceSnapshot: originalSnapshot,
      result: result,
    );

    expect(result.proposedDocument.lines.single.text, 'first lyric');
    expect(
      result.proposedDocument.lines.single.startTime,
      const Duration(seconds: 0),
    );
    expect(result.lines.single.verdict, ProofreadVerdict.amber);
    expect(result.notes, contains('secondaryAsrUnavailable'));
    expect(original.lines.single.text, 'first lyric');
  });

  test('agreement can be green while protected rows remain locked', () {
    // Keep segments outside the analyzer's overlap padding so each line has
    // unambiguous one-to-one secondary evidence.
    final primary = doc([
      row('first lyric', 0, 800, id: 'one'),
      row('second lyric', 2000, 2800, id: 'two'),
    ]);
    final secondary = doc([
      row('first lyric', 0, 800),
      row('second lyric', 2000, 2800),
    ]);

    final primarySnapshot = invariants.snapshotDocument(primary);
    final result = pipeline.build(
      draft: primary,
      secondary: secondary,
      protectedDraftIndices: const {0},
      audioDuration: const Duration(seconds: 4),
    );
    expectSharedInvariants(
      source: primary,
      sourceSnapshot: primarySnapshot,
      result: result,
      protectedSourceIndices: const {0},
      audioDuration: const Duration(seconds: 4),
    );

    expect(result.lines[0].verdict, ProofreadVerdict.locked);
    expect(result.lines[0].reasons, contains(ProofreadReason.protectedLine));
    expect(result.lines[1].verdict, ProofreadVerdict.green);
    expect(result.lines[1].reasons, contains(ProofreadReason.asrAgreement));
    expect(result.proposedDocument.lines, primary.lines);
  });

  test('disagreement is amber and does not auto-replace primary text', () {
    final primary = doc([row('open the door', 0, 1500, id: 'one')]);
    final secondary = doc([row('close the door', 0, 1500)]);
    final primarySnapshot = invariants.snapshotDocument(primary);

    final result = pipeline.build(draft: primary, secondary: secondary);
    expectSharedInvariants(
      source: primary,
      sourceSnapshot: primarySnapshot,
      result: result,
    );

    expect(result.lines.single.verdict, ProofreadVerdict.amber);
    expect(
      result.lines.single.reasons,
      contains(ProofreadReason.asrDisagreement),
    );
    expect(result.proposedDocument.lines.single.text, 'open the door');
  });

  test('flags out-of-audio timestamps instead of silently rewriting them', () {
    final source = doc([row('late ending', 3000, 5000, id: 'late')]);
    final sourceSnapshot = invariants.snapshotDocument(source);

    final result = pipeline.build(
      draft: source,
      audioDuration: const Duration(seconds: 4),
    );

    expectSharedInvariants(
      source: source,
      sourceSnapshot: sourceSnapshot,
      result: result,
      audioDuration: const Duration(seconds: 4),
    );
    expect(result.lines.single.verdict, ProofreadVerdict.amber);
    expect(result.lines.single.reasons, contains(ProofreadReason.timingConflict));
    expect(result.proposedDocument.lines.single.endTime, const Duration(seconds: 5));
  });

  test('repeated chorus lines are allowed when their intervals do not overlap', () {
    final source = doc([
      row('repeat this chorus', 0, 1000, id: 'repeat-a'),
      row('repeat this chorus', 2000, 3000, id: 'repeat-b'),
    ]);
    final sourceSnapshot = invariants.snapshotDocument(source);
    final result = pipeline.build(
      draft: source,
      secondary: doc([
        row('repeat this chorus', 0, 1000),
        row('repeat this chorus', 2000, 3000),
      ]),
      audioDuration: const Duration(seconds: 4),
    );

    expectSharedInvariants(
      source: source,
      sourceSnapshot: sourceSnapshot,
      result: result,
      audioDuration: const Duration(seconds: 4),
    );
    expect(result.proposedDocument.lines, source.lines);
  });

  test('rejects invalid protected indices and audio duration', () {
    final draft = doc([row('lyric', 0, 1000)]);
    expect(
      () => pipeline.build(draft: draft, protectedDraftIndices: const {1}),
      throwsArgumentError,
    );
    expect(
      () => pipeline.build(draft: draft, audioDuration: Duration.zero),
      throwsArgumentError,
    );
  });
}
