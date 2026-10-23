import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/timing_provenance.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_first_pipeline.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

import 'shared_proofread_pipeline_invariants.dart';

void main() {
  const pipeline = ReferenceFirstPipeline();

  LyricLine row(String text, int start, int end, {String? id}) => LyricLine(
    text: text,
    startTime: Duration(milliseconds: start),
    endTime: Duration(milliseconds: end),
    id: id,
  );

  ReferenceLyricLine ref(String text, {int? start, int? end}) =>
      ReferenceLyricLine(
        text: text,
        startTime: start == null ? null : Duration(milliseconds: start),
        endTime: end == null ? null : Duration(milliseconds: end),
      );

  ReferenceLyricInput input(
    List<ReferenceLyricLine> lines, {
    String? title,
    List<String> warnings = const [],
  }) => ReferenceLyricInput(
    lines: lines,
    timed: lines.any((line) => line.hasTimestamp),
    format: 'plain',
    title: title,
    warnings: warnings,
  );

  LyricDocument doc(
    List<LyricLine> lines, {
    Map<String, dynamic> metadata = const {},
  }) => LyricDocument(language: 'en', lines: lines, metadata: metadata);

  void expectInvariants(
    ReferenceFirstPipelineResult result, {
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
      lineIds: result.lines.map((line) => line.line.id).toList(),
      lockedVerdicts: result.lines
          .map((line) => line.verdict == ReferenceFirstVerdictLevel.locked)
          .toList(),
      sourceIndices: result.lines.map((line) => line.draftIndex).toList(),
      protectedSourceIndices: protectedSourceIndices,
      audioDuration: audioDuration,
      referenceIndices: result.lines.map((line) => line.referenceIndex).toList(),
    );
  }
  test('sanitizes headers and keeps reference indices and timing', () {
    final draft = doc([
      row('Keep your eyes on the road', 0, 3000, id: 'first'),
      row('Yeah we are going', 3000, 6000),
    ]);
    final draftSnapshot = snapshotLyricDocument(draft);
    final result = pipeline.build(
      draft: draft,
      reference: input([
        ref('Roadhouse Blues Lyrics'),
        ref('[Verse 1]'),
        ref('Keep your eyes on the road', start: 1500, end: 2500),
        ref("Yeah we're going"),
      ], title: 'Roadhouse Blues'),
    );

    expectInvariants(
      result,
      input: draft,
      inputSnapshot: draftSnapshot,
    );
    expect(result.removedReferenceLines, hasLength(2));
    expect(result.lines.map((line) => line.referenceIndex), [2, 3]);
    expect(result.proposedDocument.lines.map((line) => line.text), [
      'Keep your eyes on the road',
      "Yeah we're going",
    ]);
    expect(
      result.proposedDocument.lines.first.startTime,
      const Duration(milliseconds: 1500),
    );
    expect(
      result.proposedDocument.lines.first.endTime,
      const Duration(milliseconds: 2500),
    );
    expect(result.lines.first.timingProvenance, LyricTimingProvenance.reference);
    expect(result.proposedDocument.lines.last.startTime, const Duration(seconds: 3));
    expect(result.lines.last.timingProvenance, LyricTimingProvenance.mappedAsr);
  });

  test('interpolates missing reference lines as amber and exposes unmatched ASR rows', () {
    final draft = doc([
      row('第一句歌词', 0, 2000),
      row('unrelated recognition noise', 2000, 2500),
      row('第三句歌词', 4000, 6000),
    ]);
    final draftSnapshot = snapshotLyricDocument(draft);
    final result = pipeline.build(
      draft: draft,
      reference: input([
        ref('第一句歌词'),
        ref('第二句歌词'),
        ref('第三句歌词'),
      ]),
      audioDuration: const Duration(seconds: 8),
    );

    expectInvariants(
      result,
      input: draft,
      inputSnapshot: draftSnapshot,
      audioDuration: const Duration(seconds: 8),
    );
    expect(result.proposedDocument.lines.map((line) => line.text), [
      '第一句歌词',
      '第二句歌词',
      '第三句歌词',
    ]);
    expect(result.lines[1].verdict, ReferenceFirstVerdictLevel.amber);
    expect(result.lines[1].timingProvenance, LyricTimingProvenance.autoRepaired);
    expect(
      result.lines[1].reasons,
      contains(ReferenceFirstReason.interpolatedTiming),
    );
    expect(result.lines[1].line.startTime, const Duration(milliseconds: 2500));
    expect(result.lines[1].line.endTime, const Duration(seconds: 4));
    expect(result.droppedLines.single.draftIndex, 1);
    expect(result.droppedLines.single.line.text, 'unrelated recognition noise');
  });

  test('does not change a protected line and keeps it locked', () {
    final protected = row('protected lyrics', 1200, 3700, id: 'keep-me');
    final draft = doc([protected, row('second lyric', 4000, 6000)]);
    final draftSnapshot = snapshotLyricDocument(draft);
    final result = pipeline.build(
      draft: draft,
      reference: input([ref('protected lyrics'), ref('second lyric')]),
      protectedDraftIndices: const {0},
      audioDuration: const Duration(seconds: 8),
    );

    expectInvariants(
      result,
      input: draft,
      inputSnapshot: draftSnapshot,
      protectedSourceIndices: const {0},
      audioDuration: const Duration(seconds: 8),
    );
    final output = result.proposedDocument.lines.first;
    expect(output.text, protected.text);
    expect(output.startTime, protected.startTime);
    expect(output.endTime, protected.endTime);
    expect(output.id, protected.id);
    expect(result.lines.first.verdict, ReferenceFirstVerdictLevel.locked);
    expect(result.lines.first.reasons, contains(ReferenceFirstReason.protectedLine));
  });

  test('surfaces repaired timestamp conflicts as amber without mutating input', () {
    final original = doc([
      row('line one', 0, 3000),
      row('line two', 3000, 5000),
    ], metadata: {
      'nested': {'items': ['must', 'stay', 'unchanged']},
    });
    final originalSnapshot = snapshotLyricDocument(original);
    final result = pipeline.build(
      draft: original,
      reference: input([
        ref('line one', start: 0, end: 3000),
        ref('line two', start: 2000, end: 4000),
      ]),
      audioDuration: const Duration(seconds: 8),
    );

    expectInvariants(
      result,
      input: original,
      inputSnapshot: originalSnapshot,
      audioDuration: const Duration(seconds: 8),
    );
    expect(original.lines.first.endTime, const Duration(seconds: 3));
    expect(result.proposedDocument.lines.first.endTime, const Duration(seconds: 2));
    expect(result.proposedDocument.lines[1].startTime, const Duration(seconds: 2));
    expect(result.lines.first.verdict, ReferenceFirstVerdictLevel.amber);
    expect(result.lines.first.reasons, contains(ReferenceFirstReason.timelineAdjusted));
    expect(
      result.proposedDocument.lines.last.endTime,
      lessThanOrEqualTo(const Duration(seconds: 8)),
    );
  });

  test('rejects reference text that sanitizes to no usable lyrics', () {
    expect(
      () => pipeline.build(
        draft: doc([row('keep this draft', 0, 2000)]),
        reference: input([ref('[Chorus]'), ref('Lyrics')]),
      ),
      throwsArgumentError,
    );
  });
}
