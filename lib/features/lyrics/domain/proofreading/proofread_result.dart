import '../../../project/domain/models/lyric_document.dart';

enum ProofreadVerdict { locked, green, amber }

enum ProofreadReason {
  asrAgreement,
  asrDisagreement,
  lowConfidence,
  referenceCorrection,
  ambiguousAlignment,
  structuralMismatch,
  repeatedSegment,
  suspectedHallucination,
  missingReferenceLine,
  interpolatedTiming,
  estimatedTiming,
  timingAdjusted,
  timingConflict,
  protectedLine,
  importWarning,
  noTimingEvidence,
}

enum ProofreadRisk { low, medium, high }

enum ProofreadTimeSource {
  primaryAsr,
  secondaryAsr,
  forcedAligner,
  reference,
  interpolated,
  manual,
}

/// A validated half-open interval in the audio timeline: [start, end).
class ProofreadTimeInterval {
  final Duration start;
  final Duration end;

  ProofreadTimeInterval({required this.start, required this.end}) {
    if (start.isNegative) {
      throw ArgumentError.value(start, 'start', 'Must be non-negative.');
    }
    if (end <= start) {
      throw ArgumentError.value(end, 'end', 'Must be greater than start.');
    }
  }

  Duration get duration => end - start;
}

/// Word/token-level timing evidence. Confidence is normalized to 0..100.
class TimedLyricToken {
  final String text;
  final ProofreadTimeInterval interval;
  final int confidence;
  final ProofreadTimeSource source;

  TimedLyricToken({
    required this.text,
    required this.interval,
    required this.confidence,
    required this.source,
  }) {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'Must not be empty.');
    }
    if (confidence < 0 || confidence > 100) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'Must be in 0..100.',
      );
    }
  }
}

class ProofreadLineResult {
  final String? lineId;
  final LyricLine line;
  final ProofreadVerdict verdict;
  final Set<ProofreadReason> reasons;
  final ProofreadRisk risk;
  final List<TimedLyricToken> tokens;

  ProofreadLineResult({
    required this.lineId,
    required this.line,
    required this.verdict,
    required Set<ProofreadReason> reasons,
    required this.risk,
    List<TimedLyricToken> tokens = const [],
  }) : reasons = Set.unmodifiable(reasons),
       tokens = List.unmodifiable(tokens);
}

class ProofreadDroppedLine {
  final int sourceIndex;
  final LyricLine line;
  final Set<ProofreadReason> reasons;

  ProofreadDroppedLine({
    required this.sourceIndex,
    required this.line,
    required Set<ProofreadReason> reasons,
  }) : reasons = Set.unmodifiable(reasons) {
    if (sourceIndex < 0) {
      throw ArgumentError.value(
        sourceIndex,
        'sourceIndex',
        'Must be non-negative.',
      );
    }
  }
}

class ProofreadAdlib {
  final String text;
  final ProofreadTimeInterval interval;
  final int confidence;
  final ProofreadTimeSource source;

  ProofreadAdlib({
    required this.text,
    required this.interval,
    required this.confidence,
    required this.source,
  }) {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'Must not be empty.');
    }
    if (confidence < 0 || confidence > 100) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'Must be in 0..100.',
      );
    }
  }
}

/// Shared, immutable output contract for both proofreading strategies.
///
/// Constructing a result never persists or applies changes to the source
/// document.
class ProofreadResult {
  final LyricDocument proposedDocument;
  final List<ProofreadLineResult> lines;
  final List<ProofreadDroppedLine> droppedLines;
  final List<ProofreadAdlib> adlibs;
  final List<String> notes;
  final double referenceCoverage;
  final bool autoFellBackToAsr;

  ProofreadResult({
    required this.proposedDocument,
    required List<ProofreadLineResult> lines,
    List<ProofreadDroppedLine> droppedLines = const [],
    List<ProofreadAdlib> adlibs = const [],
    List<String> notes = const [],
    required this.referenceCoverage,
    this.autoFellBackToAsr = false,
  }) : lines = List.unmodifiable(lines),
       droppedLines = List.unmodifiable(droppedLines),
       adlibs = List.unmodifiable(adlibs),
       notes = List.unmodifiable(notes) {
    if (!referenceCoverage.isFinite ||
        referenceCoverage < 0 ||
        referenceCoverage > 1) {
      throw ArgumentError.value(
        referenceCoverage,
        'referenceCoverage',
        'Must be in 0..1.',
      );
    }
    if (lines.length != proposedDocument.lines.length) {
      throw ArgumentError(
        'Each proposed document line must have exactly one verdict.',
      );
    }
    final ids = lines.map((row) => row.lineId).whereType<String>().toList();
    if (ids.toSet().length != ids.length) {
      throw ArgumentError('Non-null line IDs must be unique.');
    }
  }

  List<ProofreadLineResult> get greenLines {
    return lines
        .where((row) => row.verdict == ProofreadVerdict.green)
        .toList(growable: false);
  }

  List<ProofreadLineResult> get amberLines {
    return lines
        .where((row) => row.verdict == ProofreadVerdict.amber)
        .toList(growable: false);
  }

  List<ProofreadLineResult> get lockedLines {
    return lines
        .where((row) => row.verdict == ProofreadVerdict.locked)
        .toList(growable: false);
  }
}
