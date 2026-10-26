import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_result.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  LyricLine line(String text, int start, int end, {String? id}) => LyricLine(
    id: id,
    text: text,
    startTime: Duration(milliseconds: start),
    endTime: Duration(milliseconds: end),
  );

  LyricDocument document(List<LyricLine> lines) =>
      LyricDocument(language: 'en', lines: lines);

  ProofreadLineResult row(LyricLine value, ProofreadVerdict verdict) =>
      ProofreadLineResult(
        lineId: value.id,
        line: value,
        verdict: verdict,
        reasons: const {ProofreadReason.asrAgreement},
        risk: ProofreadRisk.low,
      );

  test('accepts one verdict per output line and exposes grouped verdicts', () {
    final first = line('hello', 0, 900, id: 'line-1');
    final second = line('world', 1000, 1900, id: 'line-2');
    final result = ProofreadResult(
      proposedDocument: document([first, second]),
      lines: [
        row(first, ProofreadVerdict.green),
        row(second, ProofreadVerdict.amber),
      ],
      referenceCoverage: 0.5,
    );

    expect(result.greenLines.single.line.text, 'hello');
    expect(result.amberLines.single.line.text, 'world');
    expect(result.lockedLines, isEmpty);
    expect(() => result.lines.add(result.lines.first), throwsUnsupportedError);
    expect(
      () => result.lines.first.reasons.add(ProofreadReason.timingConflict),
      throwsUnsupportedError,
    );
  });

  test('rejects invalid coverage, duplicate stable IDs, and missing verdicts', () {
    final first = line('hello', 0, 900, id: 'duplicate');
    final second = line('world', 1000, 1900, id: 'duplicate');
    expect(
      () => ProofreadResult(
        proposedDocument: document([first]),
        lines: [row(first, ProofreadVerdict.green)],
        referenceCoverage: double.nan,
      ),
      throwsArgumentError,
    );
    expect(
      () => ProofreadResult(
        proposedDocument: document([first, second]),
        lines: [
          row(first, ProofreadVerdict.green),
          row(second, ProofreadVerdict.green),
        ],
        referenceCoverage: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ProofreadResult(
        proposedDocument: document([first]),
        lines: const [],
        referenceCoverage: 0,
      ),
      throwsArgumentError,
    );
  });

  test('rejects verdict rows that do not match proposed output order/content', () {
    final first = line('hello', 0, 900, id: 'line-1');
    final second = line('world', 1000, 1900, id: 'line-2');
    final altered = line('different text', 1000, 1900, id: 'line-2');

    expect(
      () => ProofreadResult(
        proposedDocument: document([first, second]),
        lines: [
          row(first, ProofreadVerdict.green),
          row(altered, ProofreadVerdict.amber),
        ],
        referenceCoverage: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ProofreadResult(
        proposedDocument: document([first, second]),
        lines: [
          row(second, ProofreadVerdict.green),
          row(first, ProofreadVerdict.amber),
        ],
        referenceCoverage: 1,
      ),
      throwsArgumentError,
    );
  });

  test('copies input collections so later caller mutation cannot alter result', () {
    final lyric = line('hello', 0, 900, id: 'line-1');
    final inputRows = <ProofreadLineResult>[row(lyric, ProofreadVerdict.green)];
    final inputNotes = <String>['initial note'];
    final result = ProofreadResult(
      proposedDocument: document([lyric]),
      lines: inputRows,
      notes: inputNotes,
      referenceCoverage: 1,
    );

    inputRows.clear();
    inputNotes.add('late mutation');

    expect(result.lines, hasLength(1));
    expect(result.notes, ['initial note']);
    expect(() => result.notes.add('forbidden'), throwsUnsupportedError);
  });


  test('alignment diagnostics report coverage and freeze unmatched indices', () {
    final indices = <int>[0, 2];
    final diagnostics = ProofreadAlignmentDiagnostics(
      totalLineCount: 4,
      matchedLineCount: 2,
      skippedSpanCount: 3,
      unmatchedLineIndices: indices,
    );
    indices.clear();

    expect(diagnostics.lineCoverage, 0.5);
    expect(diagnostics.unmatchedLineIndices, [0, 2]);
    expect(diagnostics.unmatchedLineNumbers, [1, 3]);
    expect(diagnostics.hasUnmatchedLines, isTrue);
    expect(diagnostics.hasSkippedSpans, isTrue);
    expect(diagnostics.isComplete, isFalse);
    expect(
      () => diagnostics.unmatchedLineIndices.add(3),
      throwsUnsupportedError,
    );
    expect(
      ProofreadAlignmentDiagnostics(
        totalLineCount: 0,
        matchedLineCount: 0,
        skippedSpanCount: 0,
        unmatchedLineIndices: const [],
      ).lineCoverage,
      1,
    );
  });

  test('alignment diagnostics reject inconsistent counts and line indices', () {
    expect(
      () => ProofreadAlignmentDiagnostics(
        totalLineCount: 2,
        matchedLineCount: 2,
        skippedSpanCount: 0,
        unmatchedLineIndices: [1],
      ),
      throwsArgumentError,
    );
    expect(
      () => ProofreadAlignmentDiagnostics(
        totalLineCount: 2,
        matchedLineCount: 0,
        skippedSpanCount: 0,
        unmatchedLineIndices: [0, 0],
      ),
      throwsArgumentError,
    );
    expect(
      () => ProofreadAlignmentDiagnostics(
        totalLineCount: 2,
        matchedLineCount: 1,
        skippedSpanCount: 0,
        unmatchedLineIndices: [2],
      ),
      throwsArgumentError,
    );
    expect(
      () => ProofreadAlignmentDiagnostics(
        totalLineCount: 2,
        matchedLineCount: 1,
        skippedSpanCount: -1,
        unmatchedLineIndices: [0],
      ),
      throwsArgumentError,
    );
  });

  test('validates timing intervals and confidence ranges', () {
    expect(
      () => ProofreadTimeInterval(
        start: const Duration(milliseconds: -1),
        end: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => ProofreadTimeInterval(
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => TimedLyricToken(
        text: 'word',
        interval: ProofreadTimeInterval(
          start: Duration.zero,
          end: const Duration(milliseconds: 500),
        ),
        confidence: 101,
        source: ProofreadTimeSource.primaryAsr,
      ),
      throwsArgumentError,
    );
    expect(
      () => ProofreadAdlib(
        text: 'yeah',
        interval: ProofreadTimeInterval(
          start: Duration.zero,
          end: const Duration(milliseconds: 300),
        ),
        confidence: -1,
        source: ProofreadTimeSource.secondaryAsr,
      ),
      throwsArgumentError,
    );
    expect(
      () => ProofreadAdlib(
        text: '   ',
        interval: ProofreadTimeInterval(
          start: Duration.zero,
          end: const Duration(milliseconds: 300),
        ),
        confidence: 80,
        source: ProofreadTimeSource.secondaryAsr,
      ),
      throwsArgumentError,
    );
  });
}
