import '../models/reference_lyric_input.dart';
import 'forced_alignment_proofread_service.dart';
import 'reference_text_sanitizer.dart';

/// Fail-closed outcome of preparing or matching reference alignment evidence.
enum ReferenceForcedAlignmentStatus {
  ready,
  noUsableLyrics,
  invalidReference,
  referenceLimitExceeded,
  invalidAudio,
  alignmentUnavailable,
  spanLimitExceeded,
  invalidSpan,
  textMismatch,
  incompleteAlignment,
  extraSpans,
}

/// Immutable line sent to the aligner, retaining the input's original index.
class ReferenceAlignmentLine {
  final int referenceIndex;
  final String text;

  const ReferenceAlignmentLine._(this.referenceIndex, this.text);
}

/// A validated snapshot of sanitized reference text, suitable for one run.
class PreparedReferenceAlignment {
  final List<ReferenceAlignmentLine> lines;

  PreparedReferenceAlignment._(List<ReferenceAlignmentLine> lines)
    : lines = List.unmodifiable(lines);

  String get text => lines.map((line) => line.text).join('\n');
}

class ReferenceAlignmentPreparation {
  final ReferenceForcedAlignmentStatus status;
  final PreparedReferenceAlignment? prepared;

  const ReferenceAlignmentPreparation._(this.status, this.prepared);
}

/// A proposed absolute audio interval, not an instruction to change a document.
class ReferenceForcedTimingProposal {
  final int referenceIndex;
  final String referenceText;
  final Duration start;
  final Duration end;

  /// This label describes the input to the aligner, not confidence or accuracy.
  String get source => 'forcedAlignment(reference)';

  const ReferenceForcedTimingProposal._({
    required this.referenceIndex,
    required this.referenceText,
    required this.start,
    required this.end,
  });
}

/// No partial proposals are exposed on any failure.
class ReferenceForcedAlignmentPlan {
  final ReferenceForcedAlignmentStatus status;
  final List<ReferenceForcedTimingProposal> proposals;

  /// The first input line or output span implicated by failure, if known.
  /// Reference indices use the original, unsanitized input's index space.
  final int? referenceIndex;
  final int? spanIndex;

  ReferenceForcedAlignmentPlan._({
    required this.status,
    List<ReferenceForcedTimingProposal> proposals = const [],
    this.referenceIndex,
    this.spanIndex,
  }) : proposals = List.unmodifiable(proposals);

  bool get isReady => status == ReferenceForcedAlignmentStatus.ready;
}

/// Matches the *entire* sanitized reference to an ordered aligner response.
///
/// This is deliberately stricter than ASR evidence matching: no skipping,
/// interpolation, overlap, cross-line spans or partial output is allowed.
/// Matching only ignores case and whitespace, so punctuation, scripts and
/// symbols cannot disappear silently. It does not prove that the words were
/// sung or that the backend's boundaries are accurate. Protected rows, editor
/// revisions, selection, timeline conflicts and persistence belong to a later
/// caller; no draft is read or mutated by this planner.
class ReferenceForcedAlignmentPlanner {
  static const maxReferenceLines = 4000;
  static const maxReferenceCodeUnits = 200000;
  static const maxLineCodeUnits = 4096;
  static const maxSpans = 20000;
  static const maxSpanCodeUnits = 4096;
  static const maxTotalSpanCodeUnits = 200000;

  final ReferenceTextSanitizer sanitizer;
  const ReferenceForcedAlignmentPlanner({
    this.sanitizer = const ReferenceTextSanitizer(),
  });

  ReferenceAlignmentPreparation prepare(ReferenceLyricInput reference) {
    if (reference.lines.length > maxReferenceLines ||
        (reference.title?.length ?? 0) > maxLineCodeUnits ||
        (reference.artist?.length ?? 0) > maxLineCodeUnits) {
      return const ReferenceAlignmentPreparation._(
        ReferenceForcedAlignmentStatus.referenceLimitExceeded,
        null,
      );
    }
    var total = 0;
    for (final line in reference.lines) {
      final text = line.text;
      // A line containing a newline would make the sanitizer's source indices
      // differ from ReferenceLyricInput's line indices.
      if (text.contains('\n') || text.contains('\r')) {
        return const ReferenceAlignmentPreparation._(
          ReferenceForcedAlignmentStatus.invalidReference,
          null,
        );
      }
      total += text.length;
      if (text.length > maxLineCodeUnits || total > maxReferenceCodeUnits) {
        return const ReferenceAlignmentPreparation._(
          ReferenceForcedAlignmentStatus.referenceLimitExceeded,
          null,
        );
      }
    }
    final sanitized = sanitizer.sanitize(
      reference.lines.map((line) => line.text).join('\n'),
      title: reference.title,
      artist: reference.artist,
    );
    final removed = sanitized.removed.map((item) => item.originalIndex).toSet();
    final lines = <ReferenceAlignmentLine>[];
    var cleanIndex = 0;
    for (var index = 0; index < reference.lines.length; index++) {
      if (removed.contains(index) ||
          reference.lines[index].text.trim().isEmpty) {
        continue;
      }
      if (cleanIndex >= sanitized.lines.length) {
        return const ReferenceAlignmentPreparation._(
          ReferenceForcedAlignmentStatus.invalidReference,
          null,
        );
      }
      final text = sanitized.lines[cleanIndex++];
      if (_normalize(text).isEmpty) {
        return const ReferenceAlignmentPreparation._(
          ReferenceForcedAlignmentStatus.invalidReference,
          null,
        );
      }
      lines.add(ReferenceAlignmentLine._(index, text));
    }
    if (lines.isEmpty) {
      return const ReferenceAlignmentPreparation._(
        ReferenceForcedAlignmentStatus.noUsableLyrics,
        null,
      );
    }
    if (cleanIndex != sanitized.lines.length) {
      return const ReferenceAlignmentPreparation._(
        ReferenceForcedAlignmentStatus.invalidReference,
        null,
      );
    }
    return ReferenceAlignmentPreparation._(
      ReferenceForcedAlignmentStatus.ready,
      PreparedReferenceAlignment._(lines),
    );
  }

  ReferenceForcedAlignmentPlan plan({
    required PreparedReferenceAlignment reference,
    required List<ForcedAlignedSpan> spans,
    required Duration audioDuration,
  }) {
    ReferenceForcedAlignmentPlan failure(
      ReferenceForcedAlignmentStatus status, {
      int? line,
      int? span,
    }) => ReferenceForcedAlignmentPlan._(
      status: status,
      referenceIndex: line,
      spanIndex: span,
    );

    if (audioDuration <= Duration.zero) {
      return failure(ReferenceForcedAlignmentStatus.invalidAudio);
    }
    if (spans.length > maxSpans) {
      return failure(ReferenceForcedAlignmentStatus.spanLimitExceeded);
    }
    var previousEnd = Duration.zero;
    var totalSpanLength = 0;
    for (var index = 0; index < spans.length; index++) {
      final span = spans[index];
      totalSpanLength += span.text.length;
      if (totalSpanLength > maxTotalSpanCodeUnits) {
        return failure(
          ReferenceForcedAlignmentStatus.spanLimitExceeded,
          span: index,
        );
      }
      if (span.text.length > maxSpanCodeUnits ||
          _normalize(span.text).isEmpty ||
          span.start.isNegative ||
          span.end <= span.start ||
          span.start < previousEnd ||
          span.end > audioDuration) {
        return failure(ReferenceForcedAlignmentStatus.invalidSpan, span: index);
      }
      previousEnd = span.end;
    }

    final proposals = <ReferenceForcedTimingProposal>[];
    var cursor = 0;
    for (final line in reference.lines) {
      final target = _normalize(line.text);
      final firstSpan = cursor;
      var matched = 0;
      while (matched < target.length) {
        if (cursor >= spans.length) {
          return failure(
            ReferenceForcedAlignmentStatus.incompleteAlignment,
            line: line.referenceIndex,
            span: cursor,
          );
        }
        final piece = _normalize(spans[cursor].text);
        if (!target.startsWith(piece, matched)) {
          return failure(
            ReferenceForcedAlignmentStatus.textMismatch,
            line: line.referenceIndex,
            span: cursor,
          );
        }
        matched += piece.length;
        cursor++;
      }
      proposals.add(
        ReferenceForcedTimingProposal._(
          referenceIndex: line.referenceIndex,
          referenceText: line.text,
          start: spans[firstSpan].start,
          end: spans[cursor - 1].end,
        ),
      );
    }
    if (cursor != spans.length) {
      return failure(ReferenceForcedAlignmentStatus.extraSpans, span: cursor);
    }
    return ReferenceForcedAlignmentPlan._(
      status: ReferenceForcedAlignmentStatus.ready,
      proposals: proposals,
    );
  }

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

/// Executes a prepared reference alignment without mutating project state.
/// Resource contention remains a typed retryable exception, just like the
/// existing ASR-first workflow; runtime failures return an explicit status.
class ReferenceForcedAlignmentService {
  final ForcedAlignmentRunner runner;
  final ReferenceForcedAlignmentPlanner planner;

  const ReferenceForcedAlignmentService({
    required this.runner,
    this.planner = const ReferenceForcedAlignmentPlanner(),
  });

  Future<ReferenceForcedAlignmentPlan> build({
    required ReferenceLyricInput reference,
    required String audioPath,
    required String language,
    required Duration audioDuration,
  }) async {
    final preparation = planner.prepare(reference);
    final prepared = preparation.prepared;
    if (prepared == null) {
      return ReferenceForcedAlignmentPlan._(status: preparation.status);
    }
    if (audioPath.trim().isEmpty ||
        language.trim().isEmpty ||
        audioDuration <= Duration.zero) {
      return ReferenceForcedAlignmentPlan._(
        status: ReferenceForcedAlignmentStatus.invalidAudio,
      );
    }
    late final List<ForcedAlignedSpan> spans;
    try {
      spans = await runner(
        audioPath: audioPath,
        text: prepared.text,
        language: language,
        audioDuration: audioDuration,
      );
    } on ForcedAlignmentResourceBusyException {
      rethrow;
    } on Exception {
      return ReferenceForcedAlignmentPlan._(
        status: ReferenceForcedAlignmentStatus.alignmentUnavailable,
      );
    }
    return planner.plan(
      reference: prepared,
      spans: spans,
      audioDuration: audioDuration,
    );
  }
}
