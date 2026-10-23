import 'package:flutter_test/flutter_test.dart';
import 'shared_proofread_pipeline_invariants.dart';
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

  LyricDocument doc(List<LyricLine> lines, {Map<String, dynamic> metadata = const {}}) =>
      LyricDocument(language: 'en', lines: lines, metadata: metadata);

  void expectInvariants(
    ProofreadResult result, {
    required LyricDocument input,
    required String inputSnapshot,
    Set<int> protectedSourceIndices = const {},
    Duration? audioDuration,
  }) {
    expectProofreadPipelineInvariants(
      input: input,
      inputSnapshot: inputSnapshot,
      proposedDocument: result.proposedDocument,
      verdictLines: result.lines.map((line) => line.line).toList(),
      lineIds: result.lines.map((line) => line.lineId).toList(),
      lockedVerdicts: result.lines.map((line) => line.verdict == ProofreadVerdict.locked).toList(),
      sourceIndices: List<int>.generate(result.proposedDocument.lines.length, (index) => index),
      protectedSourceIndices: protectedSourceIndices,
      audioDuration: audioDuration,
    );
  }

  test('without secondary ASR, preserves draft and marks rows for review', () {
    final original = doc([row('first lyric', 0, 1000, id: 'one')], metadata: {'nested': {'items': ['original', 'metadata']}});
    final originalSnapshot = snapshotLyricDocument(original);
    final result = pipeline.build(draft: original, audioDuration: const Duration(seconds: 2));

    expectInvariants(result, input: original, inputSnapshot: originalSnapshot, audioDuration: const Duration(seconds: 2));
    expect(result.proposedDocument.lines.single.text, 'first lyric');
    expect(
      result.proposedDocument.lines.single.startTime,
      const Duration(seconds: 0),
    );
    expectInvariants(result, input: primary, inputSnapshot: primarySnapshot, audioDuration: const Duration(seconds: 2));
    expect(snapshotLyricDocument(secondary), secondarySnapshot);
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

    final primarySnapshot = snapshotLyricDocument(primary);
    final secondarySnapshot = snapshotLyricDocument(secondary);
    final result = pipeline.build(
      draft: primary,
      secondary: secondary,
      protectedDraftIndices: const {0},
      audioDuration: const Duration(seconds: 3),
    );

    expectInvariants(result, input: primary, inputSnapshot: primarySnapshot, protectedSourceIndices: const {0}, audioDuration: const Duration(seconds: 3));
    expect(snapshotLyricDocument(secondary), secondarySnapshot);
    expect(result.lines[0].verdict, ProofreadVerdict.locked);
    expect(result.lines[0].reasons, contains(ProofreadReason.protectedLine));
    expect(result.lines[1].verdict, ProofreadVerdict.green);
    expect(result.lines[1].reasons, contains(ProofreadReason.asrAgreement));
    expect(result.proposedDocument.lines, primary.lines);
  });

  test('disagreement is amber and does not auto-replace primary text', () {
    final primary = doc([row('open the door', 0, 1500, id: 'one')]);
    final secondary = doc([row('close the door', 0, 1500)]);
    final primarySnapshot = snapshotLyricDocument(primary);
    final secondarySnapshot = snapshotLyricDocument(secondary);

    final result = pipeline.build(draft: primary, secondary: secondary, audioDuration: const Duration(seconds: 2));

    expect(result.lines.single.verdict, ProofreadVerdict.amber);
    expect(
      result.lines.single.reasons,
      contains(ProofreadReason.asrDisagreement),
    );
    expect(result.proposedDocument.lines.single.text, 'open the door');
  });

  test('permits a line to end exactly at the known audio boundary', () {
    final draft = doc([
      row('short line', 0, 300, id: 'short'),
      row('final line', 1000, 2000, id: 'final'),
    ]);
    final before = snapshotLyricDocument(draft);
    final duration = const Duration(seconds: 2);
    final result = pipeline.build(draft: draft, audioDuration: duration);
    expectInvariants(result, input: draft, inputSnapshot: before, audioDuration: duration);
    expect(result.proposedDocument.lines.last.endTime, duration);
  });

  test('marks out-of-audio timing as a conflict without mutating the draft', () {
    final draft = doc([row('too long', 3000, 5000, id: 'too-long')]);
    final before = snapshotLyricDocument(draft);
    final result = pipeline.build(draft: draft, audioDuration: const Duration(seconds: 4));
    // ASR-first is diagnostic-only: preserve the source interval and flag it.
    expectInvariants(result, input: draft, inputSnapshot: before);
    expect(result.lines.single.verdict, ProofreadVerdict.amber);
    expect(result.lines.single.reasons, contains(ProofreadReason.timingConflict));
    expect(result.proposedDocument.lines.single.endTime, const Duration(seconds: 5));
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
