import '../../../project/domain/models/lyric_document.dart';
import 'asr_consensus_analyzer.dart';
import 'asr_hallucination_filter.dart';
import 'asr_repetition_analyzer.dart';
import 'lyric_tokenizer.dart';
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
  final LyricTokenizer tokenizer;
  final int greenConfidenceThreshold;

  static const int _maxLeadingSkippedSpans = 12;
  static const int _maxSpansPerLine = 128;

  const AsrFirstPipeline({
    this.consensusAnalyzer = const AsrConsensusAnalyzer(),
    this.hallucinationFilter = const AsrHallucinationCandidateFilter(),
    this.repetitionAnalyzer = const AsrRepetitionAnalyzer(),
    this.tokenizer = const LyricTokenizer(),
    this.greenConfidenceThreshold = 80,
  }) : assert(greenConfidenceThreshold >= 0 && greenConfidenceThreshold <= 100);

  ProofreadResult build({
    required LyricDocument draft,
    LyricDocument? secondary,
    Set<int> protectedDraftIndices = const {},
    Duration? audioDuration,
    List<ProofreadAlignmentSpan> forcedAlignmentSpans = const [],
    bool forcedAlignmentRequested = false,
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

    final shouldTrackAlignment =
        forcedAlignmentRequested || forcedAlignmentSpans.isNotEmpty;
    final alignmentMatch = shouldTrackAlignment
        ? _matchAlignmentSpans(
            draft.lines,
            forcedAlignmentSpans,
            audioDuration: audioDuration,
          )
        : null;
    final alignmentTokensByLine =
        alignmentMatch?.tokensByLine ?? const <int, List<TimedLyricToken>>{};
    final alignmentDiagnostics = alignmentMatch?.diagnostics;
    final hallucinationIndices = hallucinations
        .map((item) => item.primaryIndex)
        .toSet();
    final repetitionIndices = repetitions
        .map((item) => item.primaryIndex)
        .toSet();
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
    if (alignmentDiagnostics != null) {
      notes.add(
        'forcedAlignmentMatchedLines:${alignmentDiagnostics.matchedLineCount}/'
        '${alignmentDiagnostics.totalLineCount}',
      );
      if (alignmentDiagnostics.hasSkippedSpans) {
        notes.add(
          'forcedAlignmentSkippedSpans:${alignmentDiagnostics.skippedSpanCount}',
        );
      }
      if (alignmentDiagnostics.hasUnmatchedLines) {
        notes.add(
          'forcedAlignmentUnmatchedLineNumbers:'
          '${alignmentDiagnostics.unmatchedLineNumbers.join(',')}',
        );
      }
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
      // An unscored line is not a low-scoring line: without an engine score the
      // threshold has nothing to compare against, so flagging it here would put
      // every line of a Qwen draft in the review queue.
      if (line.isLowConfidence(greenConfidenceThreshold)) {
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
      final alignedTokens =
          alignmentTokensByLine[index] ?? const <TimedLyricToken>[];
      if (alignmentDiagnostics != null && alignedTokens.isEmpty) {
        reasons.add(ProofreadReason.noTimingEvidence);
      }

      final hasRisk = reasons.any(
        (reason) => {
          ProofreadReason.asrDisagreement,
          ProofreadReason.lowConfidence,
          ProofreadReason.suspectedHallucination,
          ProofreadReason.repeatedSegment,
          ProofreadReason.timingConflict,
          ProofreadReason.noTimingEvidence,
        }.contains(reason),
      );
      final verdict = locked
          ? ProofreadVerdict.locked
          : hasRisk || secondary == null
          ? ProofreadVerdict.amber
          : ProofreadVerdict.green;
      final risk =
          reasons.contains(ProofreadReason.suspectedHallucination) ||
              reasons.contains(ProofreadReason.timingConflict)
          ? ProofreadRisk.high
          : hasRisk
          ? ProofreadRisk.medium
          : ProofreadRisk.low;

      // Preserve the source line exactly; this stage only creates review data.
      outputLines.add(line);
      results.add(
        ProofreadLineResult(
          lineId: line.id,
          line: line,
          verdict: verdict,
          reasons: reasons,
          risk: risk,
          tokens: alignedTokens,
        ),
      );
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
      alignmentDiagnostics: alignmentDiagnostics,
    );
  }

  _AlignmentSpanMatchingResult _matchAlignmentSpans(
    List<LyricLine> lines,
    List<ProofreadAlignmentSpan> spans, {
    required Duration? audioDuration,
  }) {
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
    final unmatchedLineIndices = <int>[];
    var cursor = 0;
    var skippedSpanCount = 0;

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final target = _normalizeAlignmentText(lines[lineIndex].text);
      if (target.isEmpty) {
        unmatchedLineIndices.add(lineIndex);
        continue;
      }

      final range = _findAlignmentRange(
        target: target,
        spans: spans,
        cursor: cursor,
      );
      if (range == null) {
        // Keep the cursor on the last confirmed boundary. A later lyric line
        // may still match within the bounded look-ahead even if this line did
        // not; failing one row must not cascade into losing all later rows.
        unmatchedLineIndices.add(lineIndex);
        continue;
      }

      skippedSpanCount += range.startIndex - cursor;
      matched[lineIndex] = [
        for (
          var tokenIndex = range.startIndex;
          tokenIndex <= range.endIndex;
          tokenIndex++
        )
          TimedLyricToken(
            text: spans[tokenIndex].text,
            interval: ProofreadTimeInterval(
              start: spans[tokenIndex].start,
              end: spans[tokenIndex].end,
            ),
            // The endpoint returns timings, not calibrated confidence.
            confidence: null,
            source: ProofreadTimeSource.forcedAligner,
          ),
      ];
      cursor = range.endIndex + 1;
    }

    return _AlignmentSpanMatchingResult(
      tokensByLine: matched,
      diagnostics: ProofreadAlignmentDiagnostics(
        totalLineCount: lines.length,
        matchedLineCount: matched.length,
        skippedSpanCount: skippedSpanCount,
        unmatchedLineIndices: unmatchedLineIndices,
      ),
    );
  }

  _AlignmentSpanRange? _findAlignmentRange({
    required String target,
    required List<ProofreadAlignmentSpan> spans,
    required int cursor,
  }) {
    if (cursor >= spans.length) return null;
    final lastStart = cursor + _maxLeadingSkippedSpans < spans.length
        ? cursor + _maxLeadingSkippedSpans
        : spans.length - 1;

    // Search from the earliest possible position first. This preserves source
    // order for repeated chorus lines and avoids reusing already consumed
    // spans. Both dimensions are capped to bound work on long recordings.
    for (var startIndex = cursor; startIndex <= lastStart; startIndex++) {
      final joined = StringBuffer();
      final lastEnd = startIndex + _maxSpansPerLine < spans.length
          ? startIndex + _maxSpansPerLine
          : spans.length;
      for (var endIndex = startIndex; endIndex < lastEnd; endIndex++) {
        joined.write(_normalizeAlignmentText(spans[endIndex].text));
        final candidate = joined.toString();
        if (candidate == target) {
          return _AlignmentSpanRange(startIndex, endIndex);
        }
        // Normalized text can only grow as more spans are appended. Once it
        // exceeds the target, this start position cannot produce an exact hit.
        if (candidate.length > target.length) break;
      }
    }
    return null;
  }

  String _normalizeAlignmentText(String value) {
    // Use the shared Unicode-width and CJK token rules so matching is stable
    // across full-width Latin text, Chinese punctuation, and Japanese kana.
    // Apostrophes are ignored here because a backend may split contractions
    // into separate timed spans (for example, "it" + "'s").
    return tokenizer.tokenize(value).join().replaceAll("'", '');
  }
}

class _AlignmentSpanMatchingResult {
  final Map<int, List<TimedLyricToken>> tokensByLine;
  final ProofreadAlignmentDiagnostics diagnostics;

  _AlignmentSpanMatchingResult({
    required Map<int, List<TimedLyricToken>> tokensByLine,
    required this.diagnostics,
  }) : tokensByLine = Map.unmodifiable({
         for (final entry in tokensByLine.entries)
           entry.key: List<TimedLyricToken>.unmodifiable(entry.value),
       });
}

class _AlignmentSpanRange {
  final int startIndex;
  final int endIndex;

  const _AlignmentSpanRange(this.startIndex, this.endIndex);
}
