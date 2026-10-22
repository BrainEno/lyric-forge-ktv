import '../../../project/domain/models/lyric_document.dart';
import '../models/reference_lyric_input.dart';
import '../models/reference_lyric_line.dart';
import '../models/timing_provenance.dart';
import '../services/lyric_alignment_service.dart';
import '../services/reference_alignment_applier.dart';
import 'proofread_constants.dart';
import 'reference_text_sanitizer.dart';
import 'reference_token_aligner.dart';

enum ReferenceFirstVerdictLevel { locked, green, amber }

enum ReferenceFirstReason {
  lowConfidenceAlignment,
  ambiguousAlignment,
  structuralMismatch,
  referenceTimestamp,
  mappedAsrTiming,
  interpolatedTiming,
  estimatedTailTiming,
  timelineAdjusted,
  protectedLine,
  referenceImportWarning,
}

class ReferenceFirstLineProposal {
  final int? referenceIndex;
  final int? draftIndex;
  final LyricLine line;
  final ReferenceFirstVerdictLevel verdict;
  final Set<ReferenceFirstReason> reasons;
  final LyricTimingProvenance timingProvenance;

  ReferenceFirstLineProposal({
    required this.referenceIndex,
    required this.draftIndex,
    required this.line,
    required this.verdict,
    required Set<ReferenceFirstReason> reasons,
    required this.timingProvenance,
  }) : reasons = Set.unmodifiable(reasons);
}

class ReferenceFirstDroppedLine {
  final int draftIndex;
  final LyricLine line;
  const ReferenceFirstDroppedLine(this.draftIndex, this.line);
}

class ReferenceFirstPipelineResult {
  final LyricDocument proposedDocument;
  final List<ReferenceFirstLineProposal> lines;
  final List<ReferenceFirstDroppedLine> droppedLines;
  final List<RemovedLine> removedReferenceLines;
  final List<String> warnings;
  final double tokenCoverage;
  final bool tokenDpBudgetExceeded;

  ReferenceFirstPipelineResult({
    required this.proposedDocument,
    required List<ReferenceFirstLineProposal> lines,
    required List<ReferenceFirstDroppedLine> droppedLines,
    required List<RemovedLine> removedReferenceLines,
    required List<String> warnings,
    required this.tokenCoverage,
    required this.tokenDpBudgetExceeded,
  }) : lines = List.unmodifiable(lines),
       droppedLines = List.unmodifiable(droppedLines),
       removedReferenceLines = List.unmodifiable(removedReferenceLines),
       warnings = List.unmodifiable(warnings);

  bool get hasAmberVerdicts =>
      lines.any((line) => line.verdict == ReferenceFirstVerdictLevel.amber);
}

/// Produces a non-persisted proposal; the caller remains responsible for applying it.
class ReferenceFirstPipeline {
  final ReferenceTextSanitizer sanitizer;
  final ReferenceTokenAligner tokenAligner;
  final LyricAlignmentService lineAligner;
  final ReferenceAlignmentApplier applier;

  const ReferenceFirstPipeline({
    this.sanitizer = const ReferenceTextSanitizer(),
    this.tokenAligner = const ReferenceTokenAligner(),
    this.lineAligner = const LyricAlignmentService(),
    this.applier = const ReferenceAlignmentApplier(),
  });

  ReferenceFirstPipelineResult build({
    required LyricDocument draft,
    required ReferenceLyricInput reference,
    Set<int> protectedDraftIndices = const {},
    Duration? audioDuration,
    double autoReplaceThreshold = LyricAlignmentService.defaultAutoReplaceThreshold,
  }) {
    if (!autoReplaceThreshold.isFinite ||
        autoReplaceThreshold < 0 ||
        autoReplaceThreshold > 1) {
      throw ArgumentError.value(autoReplaceThreshold, 'autoReplaceThreshold');
    }
    if (protectedDraftIndices.any((i) => i < 0 || i >= draft.lines.length)) {
      throw ArgumentError.value(protectedDraftIndices, 'protectedDraftIndices');
    }

    final sanitized = sanitizer.sanitize(
      reference.lines.map((line) => line.text).join('\n'),
      title: reference.title,
      artist: reference.artist,
    );
    final removed = sanitized.removed.map((line) => line.originalIndex).toSet();
    final refs = <ReferenceLyricLine>[];
    final originalRefIndices = <int>[];
    var cleanIndex = 0;
    for (var i = 0; i < reference.lines.length; i++) {
      if (removed.contains(i) || reference.lines[i].text.trim().isEmpty) continue;
      final original = reference.lines[i];
      refs.add(ReferenceLyricLine(
        text: sanitized.lines[cleanIndex++],
        startTime: original.startTime,
        endTime: original.endTime,
      ));
      originalRefIndices.add(i);
    }
    if (refs.isEmpty) {
      throw ArgumentError('Reference lyrics contain no usable lyric lines');
    }

    final tokenResult = tokenAligner.align(
      referenceText: refs.map((line) => line.text).join(' '),
      draftText: draft.lines.map((line) => line.text).join(' '),
    );
    final alignment = lineAligner.align(
      document: draft,
      referenceLines: refs,
      autoReplaceThreshold: autoReplaceThreshold,
    );
    final applied = applier.apply(
      document: draft,
      alignment: alignment,
      applyReferenceTiming: true,
      acceptedReferenceIndices: {
        for (final entry in alignment.entries) entry.referenceIndex,
      },
      acceptedMissingReferenceIndices: alignment.missingReferenceIndices.toSet(),
      protectedLineIndices: protectedDraftIndices,
      audioDuration: audioDuration,
    );

    final matched = alignment.entries
        .where((entry) => entry.asrLineIndex != null)
        .map((entry) => entry.asrLineIndex!)
        .toSet();
    final dropped = <ReferenceFirstDroppedLine>[
      for (var i = 0; i < draft.lines.length; i++)
        if (!matched.contains(i) && !protectedDraftIndices.contains(i))
          ReferenceFirstDroppedLine(i, draft.lines[i]),
    ];
    final appliedLines = List<LyricLine>.from(applied.document.lines);
    for (final i in protectedDraftIndices) {
      final at = applied.appliedIndexByOriginalIndex[i];
      if (at != null) appliedLines[at] = draft.lines[i];
    }
    final dropApplied = {
      for (final item in dropped)
        if (applied.appliedIndexByOriginalIndex[item.draftIndex] case final int at)
          at,
    };
    final outputAt = <int, int>{};
    final outputLines = <LyricLine>[];
    for (var i = 0; i < appliedLines.length; i++) {
      if (dropApplied.contains(i)) continue;
      outputAt[i] = outputLines.length;
      outputLines.add(appliedLines[i]);
    }

    final proposals = <int, ReferenceFirstLineProposal>{};
    final warnings = [...reference.conflicts, ...reference.warnings];
    for (final entry in alignment.entries) {
      final appliedIndex = entry.asrLineIndex == null
          ? _insertionIndex(applied.insertions, entry.referenceIndex)
          : applied.appliedIndexByOriginalIndex[entry.asrLineIndex];
      final outputIndex = appliedIndex == null ? null : outputAt[appliedIndex];
      if (outputIndex == null) throw StateError('Missing reference output row');
      final source = refs[entry.referenceIndex];
      final protected = entry.asrLineIndex != null &&
          protectedDraftIndices.contains(entry.asrLineIndex);
      final provenance = protected
          ? _sourceProvenance(draft, draft.lines[entry.asrLineIndex!])
          : applied.timingProvenanceByAppliedIndex[appliedIndex!] ??
              (source.startTime != null
                  ? LyricTimingProvenance.reference
                  : LyricTimingProvenance.mappedAsr);
      final reasons = <ReferenceFirstReason>{};
      if (protected) {
        reasons.add(ReferenceFirstReason.protectedLine);
      } else {
        if (entry.status == ReferenceLineAlignmentStatus.lowConfidence ||
            entry.status == ReferenceLineAlignmentStatus.missing ||
            entry.similarity < autoReplaceThreshold) {
          reasons.add(ReferenceFirstReason.lowConfidenceAlignment);
        }
        if (entry.ambiguous ||
            entry.status == ReferenceLineAlignmentStatus.ambiguous) {
          reasons.add(ReferenceFirstReason.ambiguousAlignment);
        }
        if (entry.structuralMismatch) {
          reasons.add(ReferenceFirstReason.structuralMismatch);
        }
        if (source.startTime != null) {
          reasons.add(ReferenceFirstReason.referenceTimestamp);
        } else if (entry.asrLineIndex == null) {
          reasons.add(provenance == LyricTimingProvenance.estimatedTail
              ? ReferenceFirstReason.estimatedTailTiming
              : ReferenceFirstReason.interpolatedTiming);
        } else {
          reasons.add(ReferenceFirstReason.mappedAsrTiming);
        }
        if (source.startTime != null &&
            (source.endTime == null || source.endTime! <= source.startTime!)) {
          reasons.add(ReferenceFirstReason.interpolatedTiming);
        }
        if (warnings.isNotEmpty) reasons.add(ReferenceFirstReason.referenceImportWarning);
        if (applied.timelineRepairs.any((repair) => repair.lineIndex == appliedIndex)) {
          reasons.add(ReferenceFirstReason.timelineAdjusted);
        }
      }
      proposals[outputIndex] = ReferenceFirstLineProposal(
        referenceIndex: originalRefIndices[entry.referenceIndex],
        draftIndex: entry.asrLineIndex,
        line: outputLines[outputIndex],
        verdict: protected
            ? ReferenceFirstVerdictLevel.locked
            : _needsReview(reasons) ? ReferenceFirstVerdictLevel.amber
            : ReferenceFirstVerdictLevel.green,
        reasons: reasons,
        timingProvenance: reasons.contains(ReferenceFirstReason.timelineAdjusted)
            ? LyricTimingProvenance.autoRepaired
            : reasons.contains(ReferenceFirstReason.interpolatedTiming)
                ? LyricTimingProvenance.interpolated
                : provenance,
      );
    }

    for (final i in protectedDraftIndices.difference(matched)) {
      final appliedIndex = applied.appliedIndexByOriginalIndex[i];
      final at = appliedIndex == null ? null : outputAt[appliedIndex];
      if (at == null) continue;
      final line = outputLines[at];
      proposals[at] = ReferenceFirstLineProposal(
        referenceIndex: null,
        draftIndex: i,
        line: line,
        verdict: ReferenceFirstVerdictLevel.locked,
        reasons: const {ReferenceFirstReason.protectedLine},
        timingProvenance: _sourceProvenance(draft, line),
      );
    }

    final ordered = <ReferenceFirstLineProposal>[
      for (var i = 0; i < outputLines.length; i++)
        proposals[i] ?? (throw StateError('Output row $i has no verdict')),
    ];
    for (var i = 1; i < ordered.length; i++) {
      if (ordered[i - 1].line.endTime <= ordered[i].line.startTime) continue;
      for (final at in [i - 1, i]) {
        final item = ordered[at];
        if (item.verdict == ReferenceFirstVerdictLevel.locked) continue;
        ordered[at] = ReferenceFirstLineProposal(
          referenceIndex: item.referenceIndex,
          draftIndex: item.draftIndex,
          line: item.line,
          verdict: ReferenceFirstVerdictLevel.amber,
          reasons: {...item.reasons, ReferenceFirstReason.timelineAdjusted},
          timingProvenance: item.timingProvenance,
        );
      }
    }

    return ReferenceFirstPipelineResult(
      proposedDocument: applied.document.copyWith(
        lines: [for (final item in ordered) item.line],
      ),
      lines: ordered,
      droppedLines: dropped,
      removedReferenceLines: sanitized.removed,
      warnings: warnings,
      tokenCoverage: tokenResult.referenceCoverage,
      tokenDpBudgetExceeded: tokenResult.dpBudgetExceeded,
    );
  }

  int? _insertionIndex(List<AppliedReferenceInsertion> insertions, int refIndex) {
    for (final item in insertions) {
      if (item.referenceIndex == refIndex) return item.appliedLineIndex;
    }
    return null;
  }

  bool _needsReview(Set<ReferenceFirstReason> reasons) => reasons.any((reason) =>
      reason != ReferenceFirstReason.referenceTimestamp &&
      reason != ReferenceFirstReason.mappedAsrTiming);

  LyricTimingProvenance _sourceProvenance(LyricDocument doc, LyricLine line) {
    final stored = doc.metadata[kLyricTimingProvenanceKey];
    return stored is Map && line.id != null
        ? LyricTimingProvenance.fromName(stored[line.id]) ??
            LyricTimingProvenance.manual
        : LyricTimingProvenance.manual;
  }
}
