import '../../../project/domain/models/lyric_document.dart';
import 'asr_consensus_analyzer.dart';
import 'asr_hallucination_filter.dart';
import 'asr_repetition_analyzer.dart';
import 'proofread_result.dart';

/// Builds a non-persisted, ASR-first review proposal from one or two transcripts.
///
/// This first orchestration layer is intentionally conservative: it never
/// rewrites text or timestamps. When secondary evidence exists, consensus,
/// repetition and hallucination analyzers only affect review verdicts; a
/// future application layer can offer explicit, separately timed proposals.
class AsrFirstPipeline {
  final AsrConsensusAnalyzer consensusAnalyzer;
  final AsrHallucinationCandidateFilter hallucinationFilter;
  final AsrRepetitionAnalyzer repetitionAnalyzer;
  final int greenConfidenceThreshold;

  const AsrFirstPipeline({
    this.consensusAnalyzer = const AsrConsensusAnalyzer(),
    this.hallucinationFilter = const AsrHallucinationCandidateFilter(),
    this.repetitionAnalyzer = const AsrRepetitionAnalyzer(),
    this.greenConfidenceThreshold = 80,
  }) : assert(greenConfidenceThreshold >= 0 && greenConfidenceThreshold <= 100);

  ProofreadResult build({
    required LyricDocument draft,
    LyricDocument? secondary,
    Set<int> protectedDraftIndices = const {},
    Duration? audioDuration,
    List<ProofreadAlignmentSpan> forcedAlignmentSpans = const [],
  }) {
    if (protectedDraftIndices.any(
      (index) => index < 0 || index >= draft.lines.length,
    )) {
      throw ArgumentError.value(protectedDraftIndices, 'protectedDraftIndices');
    }
    if (audioDuration != null && audioDuration <= Duration.zero) {
      throw ArgumentError.value(audioDuration, 'audioDuration');
    }

    final consensus = secondary == null
        ? null
        : consensusAnalyzer.analyze(primary: draft, secondary: secondary);
    final hallucinations = consensus == null
        ? const <AsrHallucinationCandidate>[]
        : hallucinationFilter.analyze(consensus).candidates;
    final repetitions = consensus == null
        ? const <AsrRepetitionSuggestion>[]
        : repetitionAnalyzer.analyze(consensus).suggestions;

    final alignmentTokensByLine = _matchAlignmentSpans(
      draft.lines,
      forcedAlignmentSpans,
      audioDuration: audioDuration,
    );
    final hallucinationIndices = hallucinations.map((item) => item.primaryIndex).toSet();
    final repetitionIndices = repetitions.map((item) => item.primaryIndex).toSet();
    final consensusByIndex = {
      for (final row in consensus?.rows ?? const <AsrConsensusRow>[])
        row.primaryIndex: row,
    };
    final notes = <String>[];
    if (secondary == null) {
      notes.add('secondaryAsrUnavailable');
    }
    if (hallucinations.isNotEmpty) {
      notes.add('hallucinationCandidates:${hallucinations.length}');
    }
    if (repetitions.isNotEmpty) {
      notes.add('repetitionSuggestions:${repetitions.length}');
    }
    if (forcedAlignmentSpans.isNotEmpty) {
      notes.add(
        'forcedAlignmentMatchedLines:${alignmentTokensByLine.length}/${draft.lines.length}',
      );
    }

    final outputLines = <LyricLine>[];
    final results = <ProofreadLineResult>[];
    for (var index = 0; index < draft.lines.length; index++) {
      final line = draft.lines[index];
      final reasons = <ProofreadReason>{};
      final locked = protectedDraftIndices.contains(index);
      final consensusRow = consensusByIndex[index];

      if (locked) reasons.add(ProofreadReason.protectedLine);
      if (consensusRow?.status == AsrConsensusStatus.agreement) {
        reasons.add(ProofreadReason.asrAgreement);
      } else if (consensusRow != null) {
        reasons.add(ProofreadReason.asrDisagreement);
      }
      if (line.confidence < greenConfidenceThreshold) {
        reasons.add(ProofreadReason.lowConfidence);
      }
      if (hallucinationIndices.contains(index)) {
        reasons.add(ProofreadReason.suspectedHallucination);
      }
      if (repetitionIndices.contains(index)) {
        reasons.add(ProofreadReason.repeatedSegment);
      }
      if (audioDuration != null &&
          (line.startTime.isNegative ||
              line.endTime <= line.startTime ||
              line.endTime > audioDuration)) {
        reasons.add(ProofreadReason.timingConflict);
      }
      if (consensusRow == null && secondary != null) {
        reasons.add(ProofreadReason.noTimingEvidence);
      }
      final alignedTokens = alignmentTokensByLine[index] ?? const <TimedLyricToken>[];
      if (forcedAlignmentSpans.isNotEmpty && alignedTokens.isEmpty) {
        reasons.add(ProofreadReason.noTimingEvidence);
      }

      final hasRisk = reasons.any((reason) => {
        ProofreadReason.asrDisagreement,
        ProofreadReason.lowConfidence,
        ProofreadReason.suspectedHallucination,
        ProofreadReason.repeatedSegment,
        ProofreadReason.timingConflict,
        ProofreadReason.noTimingEvidence,
      }.contains(reason));
      final verdict = locked
          ? ProofreadVerdict.locked
          : hasRisk || secondary == null
          ? ProofreadVerdict.amber
          : ProofreadVerdict.green;
      final risk = reasons.contains(ProofreadReason.suspectedHallucination) ||
              reasons.contains(ProofreadReason.timingConflict)
          ? ProofreadRisk.high
          : hasRisk
          ? ProofreadRisk.medium
          : ProofreadRisk.low;

      // Preserve the source line exactly; this stage only creates review data.
      outputLines.add(line);
      results.add(ProofreadLineResult(
        lineId: line.id,
        line: line,
        verdict: verdict,
        reasons: reasons,
        risk: risk,
        tokens: alignedTokens,
      ));
    }

    return ProofreadResult(
      proposedDocument: LyricDocument(
        language: draft.language,
        lines: outputLines,
        globalOffset: draft.globalOffset,
        metadata: draft.metadata,
      ),
      lines: results,
      referenceCoverage: 0,
      notes: notes,
    );
  }

  Map<int, List<TimedLyricToken>> _matchAlignmentSpans(
    List<LyricLine> lines,
    List<ProofreadAlignmentSpan> spans, {
    required Duration? audioDuration,
  }) {
    if (spans.isEmpty) return const {};
    var previousStart = Duration.zero;
    for (var index = 0; index < spans.length; index++) {
      final span = spans[index];
      if (span.start < previousStart ||
          (audioDuration != null && span.end > audioDuration)) {
        throw ArgumentError.value(
          spans,
          'forcedAlignmentSpans',
          'Spans must be start-ordered and stay within audio duration.',
        );
      }
      previousStart = span.start;
    }

    final matched = <int, List<TimedLyricToken>>{};
    var cursor = 0;
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final target = _normalizeAlignmentText(lines[lineIndex].text);
      if (target.isEmpty) continue;
      final joined = StringBuffer();
      for (var endIndex = cursor;
          endIndex < spans.length && endIndex - cursor < 128;
          endIndex++) {
        joined.write(_normalizeAlignmentText(spans[endIndex].text));
        final candidate = joined.toString();
        if (candidate == target) {
          matched[lineIndex] = [
            for (var tokenIndex = cursor; tokenIndex <= endIndex; tokenIndex++)
              TimedLyricToken(
                text: spans[tokenIndex].text,
                interval: ProofreadTimeInterval(
                  start: spans[tokenIndex].start,
                  end: spans[tokenIndex].end,
                ),
                confidence: 60,
                source: ProofreadTimeSource.forcedAligner,
              ),
          ];
          cursor = endIndex + 1;
          break;
        }
        if (candidate.length > target.length + 2) break;
      }
    }
    return matched;
  }

  String _normalizeAlignmentText(String value) {
    return value
        .toLowerCase()
        .replaceAll(
          RegExp(r'[\s.,!?，。！？、:;…\-—()（）\[\]{}"“”‘’]'),
          '',
        );
  }
}
