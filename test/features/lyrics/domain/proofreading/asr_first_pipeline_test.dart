import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_first_pipeline.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_result.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const pipeline = AsrFirstPipeline();

  LyricLine row(String text, int start, int end, {String? id, int confidence = 90}) =>
      LyricLine(
        text: text,
        startTime: Duration(milliseconds: start),
        endTime: Duration(milliseconds: end),
        id: id,
        confidence: confidence,
      );

  LyricDocument doc(List<LyricLine> lines) =>
      LyricDocument(language: 'en', lines: lines);

  test('without secondary ASR, preserves draft and marks rows for review', () {
    final original = doc([row('first lyric', 0, 1000, id: 'one')]);
    final result = pipeline.build(draft: original);

    expect(result.proposedDocument.lines.single.text, 'first lyric');
    expect(result.proposedDocument.lines.single.startTime, const Duration(seconds: 0));
    expect(result.lines.single.verdict, ProofreadVerdict.amber);
    expect(result.notes, contains('secondaryAsrUnavailable'));
    expect(original.lines.single.text, 'first lyric');
  });

  test('agreement can be green while protected rows remain locked', () {
    final primary = doc([
      row('first lyric', 0, 1000, id: 'one'),
      row('second lyric', 1000, 2000, id: 'two'),
    ]);
    final secondary = doc([
      row('first lyric', 0, 1000),
      row('second lyric', 1000, 2000),
    ]);

    final result = pipeline.build(
      draft: primary,
      secondary: secondary,
      protectedDraftIndices: const {0},
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

    final result = pipeline.build(draft: primary, secondary: secondary);

    expect(result.lines.single.verdict, ProofreadVerdict.amber);
    expect(result.lines.single.reasons, contains(ProofreadReason.asrDisagreement));
    expect(result.proposedDocument.lines.single.text, 'open the door');
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
