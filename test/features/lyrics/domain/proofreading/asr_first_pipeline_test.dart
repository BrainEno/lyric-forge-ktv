import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_first_pipeline.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_result.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

import 'shared_proofread_pipeline_invariants.dart';

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

  LyricDocument doc(
    List<LyricLine> lines, {
    Map<String, dynamic> metadata = const {},
  }) => LyricDocument(language: 'en', lines: lines, metadata: metadata);

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
      lockedVerdicts: result.lines
          .map((line) => line.verdict == ProofreadVerdict.locked)
          .toList(),
      sourceIndices: List<int>.generate(
        result.proposedDocument.lines.length,
        (index) => index,
      ),
      protectedSourceIndices: protectedSourceIndices,
      audioDuration: audioDuration,
      timingConflictVerdicts: result.lines
          .map((line) => line.reasons.contains(ProofreadReason.timingConflict))
          .toList(),
    );
  }

  test('without secondary ASR, preserves draft and marks rows for review', () {
    final original = doc(
      [row('first lyric', 0, 1000, id: 'one')],
      metadata: {'nested': {'items': ['original', 'metadata']}},
    );
    final originalSnapshot = snapshotLyricDocument(original);
    final result = pipeline.build(draft: original);

    expectInvariants(
      result,
      input: original,
      inputSnapshot: originalSnapshot,
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

    final primarySnapshot = snapshotLyricDocument(primary);
    final secondarySnapshot = snapshotLyricDocument(secondary);
    final result = pipeline.build(
      draft: primary,
      secondary: secondary,
      protectedDraftIndices: const {0},
      audioDuration: const Duration(seconds: 3),
    );

    expectInvariants(
      result,
      input: primary,
      inputSnapshot: primarySnapshot,
      protectedSourceIndices: const {0},
      audioDuration: const Duration(seconds: 3),
    );
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

    final result = pipeline.build(
      draft: primary,
      secondary: secondary,
      audioDuration: const Duration(seconds: 2),
    );

    expectInvariants(
      result,
      input: primary,
      inputSnapshot: primarySnapshot,
      audioDuration: const Duration(seconds: 2),
    );
    expect(snapshotLyricDocument(secondary), secondarySnapshot);
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
    final result = pipeline.build(
      draft: draft,
      audioDuration: duration,
    );
    expectInvariants(
      result,
      input: draft,
      inputSnapshot: before,
      audioDuration: duration,
    );
    expect(result.proposedDocument.lines.last.endTime, duration);
  });

  test('marks out-of-audio timing as a conflict without mutating the draft', () {
    final draft = doc([row('too long', 3000, 5000, id: 'too-long')]);
    final before = snapshotLyricDocument(draft);
    final result = pipeline.build(
      draft: draft,
      audioDuration: const Duration(seconds: 4),
    );
    // ASR-first is diagnostic-only: preserve the source interval and flag it.
    expectInvariants(
      result,
      input: draft,
      inputSnapshot: before,
      audioDuration: const Duration(seconds: 4),
    );
    expect(result.lines.single.verdict, ProofreadVerdict.amber);
    expect(
      result.lines.single.reasons,
      contains(ProofreadReason.timingConflict),
    );
    expect(
      result.proposedDocument.lines.single.endTime,
      const Duration(seconds: 5),
    );
  });

  test('attaches forced-alignment tokens without changing lyric text or line timing', () {
    final draft = doc([
      row('Hello world!', 0, 1200, id: 'one'),
      row('Good night', 2000, 3000, id: 'two'),
    ]);
    final before = snapshotLyricDocument(draft);
    final result = pipeline.build(
      draft: draft,
      audioDuration: const Duration(seconds: 4),
      forcedAlignmentSpans: [
        ProofreadAlignmentSpan(
          text: 'Hello',
          start: Duration.zero,
          end: const Duration(milliseconds: 350),
        ),
        ProofreadAlignmentSpan(
          text: 'world',
          start: const Duration(milliseconds: 400),
          end: const Duration(milliseconds: 900),
        ),
        ProofreadAlignmentSpan(
          text: 'Good',
          start: const Duration(seconds: 2),
          end: const Duration(milliseconds: 2400),
        ),
        ProofreadAlignmentSpan(
          text: 'night',
          start: const Duration(milliseconds: 2450),
          end: const Duration(seconds: 3),
        ),
      ],
    );

    expect(snapshotLyricDocument(draft), before);
    expect(result.proposedDocument.lines.map((line) => line.text),
        ['Hello world!', 'Good night']);
    expect(result.proposedDocument.lines[0].startTime,
        const Duration(milliseconds: 0));
    expect(result.lines[0].tokens.map((token) => token.text), ['Hello', 'world']);
    expect(result.lines[0].tokens.first.source, ProofreadTimeSource.forcedAligner);
    expect(result.lines[0].tokens.first.confidence, isNull);
    expect(result.lines[1].tokens.map((token) => token.text), ['Good', 'night']);
    expect(result.notes, contains('forcedAlignmentMatchedLines:2/2'));
  });

  test('marks unmatched lines for review when alignment evidence is incomplete', () {
    final draft = doc([
      row('known lyric', 0, 1000, id: 'one'),
      row('unmatched lyric', 1200, 2200, id: 'two'),
    ]);
    final result = pipeline.build(
      draft: draft,
      forcedAlignmentSpans: [
        ProofreadAlignmentSpan(
          text: 'known',
          start: Duration.zero,
          end: const Duration(milliseconds: 300),
        ),
        ProofreadAlignmentSpan(
          text: 'lyric',
          start: const Duration(milliseconds: 350),
          end: const Duration(milliseconds: 700),
        ),
      ],
    );

    expect(result.lines[0].tokens, hasLength(2));
    expect(result.lines[1].tokens, isEmpty);
    expect(result.lines[1].reasons, contains(ProofreadReason.noTimingEvidence));
    expect(result.lines[1].verdict, ProofreadVerdict.amber);
    expect(result.proposedDocument.lines, draft.lines);
  });

  test('matches full-width Latin, Chinese, and Japanese punctuation consistently', () {
    final draft = doc([
      row('Ｈｅｌｌｏ ｗｏｒｌｄ！', 0, 1200, id: 'latin'),
      row('月亮代表我的心。', 1500, 2800, id: 'chinese'),
      row('「こんにちは、世界！」', 3000, 4500, id: 'japanese'),
    ]);
    final before = snapshotLyricDocument(draft);
    final result = pipeline.build(
      draft: draft,
      audioDuration: const Duration(seconds: 5),
      forcedAlignmentSpans: [
        ProofreadAlignmentSpan(
          text: 'Hello',
          start: const Duration(milliseconds: 100),
          end: const Duration(milliseconds: 300),
        ),
        ProofreadAlignmentSpan(
          text: 'world!',
          start: const Duration(milliseconds: 350),
          end: const Duration(milliseconds: 700),
        ),
        ProofreadAlignmentSpan(
          text: '月亮代表',
          start: const Duration(milliseconds: 1600),
          end: const Duration(milliseconds: 2100),
        ),
        ProofreadAlignmentSpan(
          text: '我的',
          start: const Duration(milliseconds: 2150),
          end: const Duration(milliseconds: 2350),
        ),
        ProofreadAlignmentSpan(
          text: '心。',
          start: const Duration(milliseconds: 2400),
          end: const Duration(milliseconds: 2700),
        ),
        ProofreadAlignmentSpan(
          text: 'こんにちは',
          start: const Duration(milliseconds: 3100),
          end: const Duration(milliseconds: 3600),
        ),
        ProofreadAlignmentSpan(
          text: '世界！',
          start: const Duration(milliseconds: 3650),
          end: const Duration(milliseconds: 4200),
        ),
      ],
    );

    expect(snapshotLyricDocument(draft), before);
    expect(result.lines.map((line) => line.tokens.map((token) => token.text).join()),
        ['Helloworld!', '月亮代表我的心。', 'こんにちは世界！']);
    expect(result.notes, contains('forcedAlignmentMatchedLines:3/3'));
    expect(result.proposedDocument.lines, draft.lines);
  });


  test('recovers later line evidence around an inserted ad-lib span', () {
    final draft = doc([
      row('hello', 0, 500, id: 'hello'),
      row('world', 600, 1200, id: 'world'),
    ]);
    final before = snapshotLyricDocument(draft);
    final result = pipeline.build(
      draft: draft,
      audioDuration: const Duration(seconds: 2),
      forcedAlignmentSpans: [
        ProofreadAlignmentSpan(
          text: 'hello',
          start: const Duration(milliseconds: 100),
          end: const Duration(milliseconds: 300),
        ),
        ProofreadAlignmentSpan(
          text: 'yeah',
          start: const Duration(milliseconds: 400),
          end: const Duration(milliseconds: 500),
        ),
        ProofreadAlignmentSpan(
          text: 'world',
          start: const Duration(milliseconds: 700),
          end: const Duration(milliseconds: 900),
        ),
      ],
    );

    final diagnostics = result.alignmentDiagnostics!;
    expect(diagnostics.totalLineCount, 2);
    expect(diagnostics.matchedLineCount, 2);
    expect(diagnostics.lineCoverage, 1);
    expect(diagnostics.skippedSpanCount, 1);
    expect(diagnostics.unmatchedLineIndices, isEmpty);
    expect(diagnostics.isComplete, isFalse);
    expect(result.lines.map((line) => line.tokens.map((token) => token.text)),
        [ ['hello'], ['world'] ]);
    expect(result.notes, contains('forcedAlignmentSkippedSpans:1'));
    expect(snapshotLyricDocument(draft), before);
  });

  test('later lines can match even when an earlier lyric line has no evidence', () {
    final draft = doc([
      row('missing words', 0, 700, id: 'missing'),
      row('hello', 800, 1200, id: 'hello'),
    ]);
    final result = pipeline.build(
      draft: draft,
      forcedAlignmentSpans: [
        ProofreadAlignmentSpan(
          text: 'hello',
          start: const Duration(milliseconds: 900),
          end: const Duration(milliseconds: 1100),
        ),
      ],
    );

    final diagnostics = result.alignmentDiagnostics!;
    expect(result.lines[0].tokens, isEmpty);
    expect(result.lines[1].tokens.map((token) => token.text), ['hello']);
    expect(diagnostics.matchedLineCount, 1);
    expect(diagnostics.lineCoverage, 0.5);
    expect(diagnostics.unmatchedLineIndices, [0]);
    expect(diagnostics.unmatchedLineNumbers, [1]);
    expect(result.notes, contains('forcedAlignmentUnmatchedLineNumbers:1'));
  });

  test('keeps extra-span recovery bounded to avoid distant false matches', () {
    final draft = doc([row('hello', 0, 1000, id: 'hello')]);
    final spans = <ProofreadAlignmentSpan>[
      for (var index = 0; index < 13; index++)
        ProofreadAlignmentSpan(
          text: 'uh$index',
          start: Duration(milliseconds: 100 + index * 100),
          end: Duration(milliseconds: 150 + index * 100),
        ),
      ProofreadAlignmentSpan(
        text: 'hello',
        start: const Duration(milliseconds: 1600),
        end: const Duration(milliseconds: 1800),
      ),
    ];
    final result = pipeline.build(
      draft: draft,
      audioDuration: const Duration(seconds: 3),
      forcedAlignmentSpans: spans,
    );

    expect(result.lines.single.tokens, isEmpty);
    expect(result.alignmentDiagnostics!.matchedLineCount, 0);
    expect(result.alignmentDiagnostics!.unmatchedLineNumbers, [1]);
    expect(result.notes, contains('forcedAlignmentMatchedLines:0/1'));
  });

  test('matches repeated chorus lines with distinct sequential spans', () {
    final draft = doc([
      row('oh yeah', 0, 600, id: 'chorus-1'),
      row('oh yeah', 2000, 2600, id: 'chorus-2'),
    ]);
    final result = pipeline.build(
      audioDuration: const Duration(seconds: 4),
      forcedAlignmentSpans: [
        ProofreadAlignmentSpan(
          text: 'oh',
          start: const Duration(milliseconds: 100),
          end: const Duration(milliseconds: 250),
        ),
        ProofreadAlignmentSpan(
          text: 'yeah',
          start: const Duration(milliseconds: 300),
          end: const Duration(milliseconds: 550),
        ),
        ProofreadAlignmentSpan(
          text: 'oh',
          start: const Duration(milliseconds: 2100),
          end: const Duration(milliseconds: 2250),
        ),
        ProofreadAlignmentSpan(
          text: 'yeah',
          start: const Duration(milliseconds: 2300),
          end: const Duration(milliseconds: 2550),
        ),
      ],
    );

    expect(result.lines[0].tokens.map((token) => token.text), ['oh', 'yeah']);
    expect(result.lines[1].tokens.map((token) => token.text), ['oh', 'yeah']);
    expect(result.lines[0].tokens.first.interval.start,
        const Duration(milliseconds: 100));
    expect(result.lines[1].tokens.first.interval.start,
        const Duration(milliseconds: 2100));
    expect(result.alignmentDiagnostics!.matchedLineCount, 2);
    expect(result.alignmentDiagnostics!.skippedSpanCount, 0);
  });

  test('records zero coverage when the aligner succeeds with no spans', () {
    final draft = doc([row('hello world', 0, 1000, id: 'line')]);
    final result = pipeline.build(
      draft: draft,
      forcedAlignmentRequested: true,
    );

    expect(result.alignmentDiagnostics, isNotNull);
    expect(result.alignmentDiagnostics!.matchedLineCount, 0);
    expect(result.alignmentDiagnostics!.lineCoverage, 0);
    expect(result.alignmentDiagnostics!.unmatchedLineNumbers, [1]);
    expect(result.lines.single.reasons, contains(ProofreadReason.noTimingEvidence));
  });

  test('rejects forced-alignment spans outside the audio or out of order', () {
    final draft = doc([row('hello', 0, 1000)]);
    expect(
      () => pipeline.build(
        draft: draft,
        audioDuration: const Duration(seconds: 1),
        forcedAlignmentSpans: [
          ProofreadAlignmentSpan(
            text: 'hello',
            start: Duration.zero,
            end: const Duration(seconds: 2),
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => pipeline.build(
        draft: draft,
        forcedAlignmentSpans: [
          ProofreadAlignmentSpan(
            text: 'world',
            start: const Duration(milliseconds: 500),
            end: const Duration(milliseconds: 700),
          ),
          ProofreadAlignmentSpan(
            text: 'hello',
            start: Duration.zero,
            end: const Duration(milliseconds: 200),
          ),
        ],
      ),
      throwsArgumentError,
    );
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
