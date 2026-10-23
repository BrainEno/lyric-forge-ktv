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

  test('accepts one verdict per output line and exposes grouped verdicts', () {
    final first = line('hello', 0, 900, id: 'line-1');
    final second = line('world', 1000, 1900, id: 'line-2');
    final result = ProofreadResult(
      proposedDocument: document([first, second]),
      lines: [
        ProofreadLineResult(
          lineId: first.id,
          line: first,
          verdict: ProofreadVerdict.green,
          reasons: const {ProofreadReason.asrAgreement},
          risk: ProofreadRisk.low,
        ),
        ProofreadLineResult(
          lineId: second.id,
          line: second,
          verdict: ProofreadVerdict.amber,
          reasons: const {ProofreadReason.noTimingEvidence},
          risk: ProofreadRisk.high,
        ),
      ],
      referenceCoverage: 0.5,
    );

    expect(result.greenLines.single.line.text, 'hello');
    expect(result.amberLines.single.line.text, 'world');
    expect(result.lockedLines, isEmpty);
    expect(() => result.lines.add(result.lines.first), throwsUnsupportedError);
    expect(() => result.lines.first.reasons.add(ProofreadReason.timingConflict),
        throwsUnsupportedError);
  });

  test('rejects invalid coverage, duplicate stable IDs, and missing verdicts', () {
    final first = line('hello', 0, 900, id: 'duplicate');
    final second = line('world', 1000, 1900, id: 'duplicate');
    expect(
      () => ProofreadResult(
        proposedDocument: document([first]),
        lines: [
          ProofreadLineResult(
            lineId: first.id,
            line: first,
            verdict: ProofreadVerdict.green,
            reasons: const {},
            risk: ProofreadRisk.low,
          ),
        ],
        referenceCoverage: double.nan,
      ),
      throwsArgumentError,
    );
    expect(
      () => ProofreadResult(
        proposedDocument: document([first, second]),
        lines: [
          ProofreadLineResult(
            lineId: first.id,
            line: first,
            verdict: ProofreadVerdict.green,
            reasons: const {},
            risk: ProofreadRisk.low,
          ),
          ProofreadLineResult(
            lineId: second.id,
            line: second,
            verdict: ProofreadVerdict.green,
            reasons: const {},
            risk: ProofreadRisk.low,
          ),
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
  });
}
