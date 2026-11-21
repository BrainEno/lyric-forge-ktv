import '../../../lyrics/domain/models/vocal_check_record.dart';
import '../../../lyrics/domain/services/lyric_span_rerecognition.dart';
import '../../../lyrics/domain/services/lyric_vocal_check_actions.dart';
import '../../../lyrics/domain/services/lyric_vocal_gap_batch.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../models/vocal_gap_fill_models.dart';

/// Recognises `[start, end)` of the vocal audio — on the audio's timeline —
/// with [engine] and returns the rows it heard, on the audio's timeline.
///
/// Throws [LyricSpanRecognitionException]; `busy` and `cancelled` end the
/// whole step, anything else fails only this engine for this stretch.
typedef VocalGapClipRecognizer =
    Future<List<LyricLine>> Function({
      required Duration start,
      required Duration end,
      required LyricSpanEngine engine,
    });

/// Limits that keep the step a short tail of a whole-song run.
class VocalGapFillPolicy {
  /// Stretches sent at most; later ones are left for the editor.
  final int maxGaps;

  /// Total window length sent at most.
  final Duration maxAudio;

  const VocalGapFillPolicy({
    this.maxGaps = 24,
    this.maxAudio = const Duration(minutes: 4),
  });
}

/// The stretch being recognised, for progress messages.
class VocalGapFillProgress {
  /// 1-based position among the stretches sent.
  final int current;
  final int total;

  /// The window on the document's timeline.
  final Duration start;
  final Duration end;
  final LyricSpanEngine engine;

  /// Whether [engine] is the fallback for this stretch.
  final bool fallback;

  const VocalGapFillProgress({
    required this.current,
    required this.total,
    required this.start,
    required this.end,
    required this.engine,
    required this.fallback,
  });
}

/// The optional last step of whole-song recognition (D-047): every stretch
/// the vocal check (D-044) heard singing but no row in is recognised on its
/// own and what is heard goes into the draft, so the draft comes out with
/// missed lines already filled in.
///
/// It is the editor's "全部识别" (D-046) without the dialog: the same
/// windows ([LyricVocalGapBatch.plan]), the same engine fallback on an
/// empty result or an ordinary error, the same stop on a busy runtime or a
/// cancel, and the same single insertion ([LyricVocalGapBatch.apply]). The
/// rows that go in are listed in the document's `vocalGapFill` record so the
/// editor puts them in the review queue.
///
/// Nothing here touches audio or the disk; [VocalGapClipRecognizer] does.
class VocalGapFiller {
  const VocalGapFiller({
    this.batch = const LyricVocalGapBatch(),
    this.policy = const VocalGapFillPolicy(),
  });

  final LyricVocalGapBatch batch;
  final VocalGapFillPolicy policy;

  /// [draft] with every stretch it could fill filled.
  ///
  /// Never throws: a failure of the step leaves [draft] unchanged, with a
  /// report saying why. [engines] are tried in order for each stretch.
  Future<VocalGapFillResult> fill(
    LyricDocument draft, {
    required List<LyricSpanEngine> engines,
    required VocalGapClipRecognizer recognize,
    Duration? audioDuration,
    void Function(VocalGapFillProgress progress)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final record = LyricVocalCheckRecord.fromMetadata(draft.metadata);
    if (record == null) {
      return VocalGapFillResult(
        draft,
        const VocalGapFillReport.skipped(VocalGapFillSkipReason.noVocalCheck),
      );
    }
    final spans = record.openSpans(draft);
    if (spans.isEmpty) {
      return VocalGapFillResult(
        draft,
        const VocalGapFillReport.skipped(VocalGapFillSkipReason.noGaps),
      );
    }
    final order = List<LyricSpanEngine>.unmodifiable(engines.toSet());
    if (order.isEmpty) {
      return VocalGapFillResult(
        draft,
        VocalGapFillReport.skipped(
          VocalGapFillSkipReason.noEngine,
          spans: [
            for (final span in spans)
              VocalGapFillSpanReport(
                start: span.start,
                end: span.end,
                outcome: VocalGapFillOutcome.notTried,
              ),
          ],
        ),
      );
    }

    final plan = batch.plan(draft, spans, audioDuration: audioDuration);
    final selection = _select(plan);
    if (selection.sent.isEmpty) {
      return VocalGapFillResult(
        draft,
        VocalGapFillReport.skipped(
          VocalGapFillSkipReason.noWindows,
          engines: order,
          spans: selection.reports,
        ),
      );
    }

    final reports = [...selection.reports];
    final insertions = <int, LyricVocalGapInsertion>{};
    final offset = draft.globalOffset ?? Duration.zero;
    VocalGapFillStopReason? stop;
    for (final (position, slot) in selection.sent.indexed) {
      final window = plan.items[slot].window!;
      final attempt = await _recognize(
        window,
        engines: order,
        offset: offset,
        recognize: recognize,
        progress: (engine, fallback) => onProgress?.call(
          VocalGapFillProgress(
            current: position + 1,
            total: selection.sent.length,
            start: window.start,
            end: window.end,
            engine: engine,
            fallback: fallback,
          ),
        ),
      );
      final insertion = attempt.insertion;
      if (insertion != null) insertions[slot] = insertion;
      reports[slot] = VocalGapFillSpanReport(
        start: window.span.start,
        end: window.span.end,
        outcome: attempt.outcome,
        engine: attempt.engine,
        fellBack: attempt.fellBack,
        insertedLines: insertion?.newLines.length ?? 0,
        error: attempt.error,
      );
      stop = attempt.stop;
      if (stop != null) break;
    }

    return _apply(
      draft,
      plan: plan,
      insertions: insertions,
      reports: reports,
      engines: order,
      stop: stop,
      elapsed: stopwatch.elapsed,
    );
  }

  /// Which planned stretches are sent, and a report for every stretch with
  /// the unsent ones already decided.
  _Selection _select(LyricVocalGapBatchPlan plan) {
    final reports = <VocalGapFillSpanReport>[];
    final sent = <int>[];
    var budget = Duration.zero;
    for (final (index, item) in plan.items.indexed) {
      final window = item.window;
      VocalGapFillOutcome outcome;
      if (!item.isSendable || window == null) {
        outcome = VocalGapFillOutcome.unsendable;
      } else if (sent.length >= policy.maxGaps ||
          budget + window.length > policy.maxAudio) {
        outcome = VocalGapFillOutcome.overBudget;
      } else {
        sent.add(index);
        budget += window.length;
        outcome = VocalGapFillOutcome.notTried;
      }
      reports.add(
        VocalGapFillSpanReport(
          start: item.span.start,
          end: item.span.end,
          outcome: outcome,
        ),
      );
    }
    return _Selection(sent, reports);
  }

  Future<_Attempt> _recognize(
    LyricVocalGapWindow window, {
    required List<LyricSpanEngine> engines,
    required Duration offset,
    required VocalGapClipRecognizer recognize,
    required void Function(LyricSpanEngine engine, bool fallback) progress,
  }) async {
    final audio = window.onAudio(offset);
    var heardNothing = false;
    String? error;
    for (final (index, engine) in engines.indexed) {
      progress(engine, index > 0);
      try {
        final lines = await recognize(
          start: audio.start,
          end: audio.end,
          engine: engine,
        );
        final insertion = batch.actions.insertion(
          window,
          recognized: LyricVocalCheckActions.toDocumentTimeline(lines, offset),
        );
        if (!insertion.isEmpty) {
          return _Attempt(
            VocalGapFillOutcome.filled,
            insertion: insertion,
            engine: engine,
            fellBack: index > 0,
          );
        }
        heardNothing = true;
      } on LyricSpanRecognitionException catch (failure) {
        if (failure.cancelled || failure.busy) {
          return _Attempt(
            VocalGapFillOutcome.notTried,
            error: failure.message,
            stop: failure.cancelled
                ? VocalGapFillStopReason.cancelled
                : VocalGapFillStopReason.busy,
          );
        }
        error = failure.message;
      } on Object catch (failure) {
        // A recogniser bug fails this engine for this stretch, not the run.
        error = '$failure';
      }
    }
    return heardNothing
        ? const _Attempt(VocalGapFillOutcome.empty)
        : _Attempt(VocalGapFillOutcome.failed, error: error);
  }

  VocalGapFillResult _apply(
    LyricDocument draft, {
    required LyricVocalGapBatchPlan plan,
    required Map<int, LyricVocalGapInsertion> insertions,
    required List<VocalGapFillSpanReport> reports,
    required List<LyricSpanEngine> engines,
    required VocalGapFillStopReason? stop,
    required Duration elapsed,
  }) {
    LyricVocalGapBatchResult? applied;
    try {
      applied = batch.apply(draft, insertions: insertions.values.toList());
    } on Object catch (error) {
      return VocalGapFillResult(
        draft,
        VocalGapFillReport.skipped(
          VocalGapFillSkipReason.failed,
          engines: engines,
          spans: reports,
          error: '$error',
        ),
      );
    }
    if (applied == null) {
      return VocalGapFillResult(
        draft,
        VocalGapFillReport.applied(
          engines: engines,
          spans: reports,
          elapsed: elapsed,
          stopReason: stop,
        ),
      );
    }

    // Making the rows of neighbouring stretches consecutive can drop a
    // fragment, so count what actually went in, per window.
    final document = applied.document;
    final inserted = [
      for (final index in applied.insertedIndices) document.lines[index],
    ];
    final counted = [
      for (final (slot, report) in reports.indexed)
        insertions[slot] == null
            ? report
            : _recount(report, insertions[slot]!.window, inserted),
    ];
    final report = VocalGapFillReport.applied(
      engines: engines,
      spans: counted,
      elapsed: elapsed,
      stopReason: stop,
    );
    final ids = [for (final line in inserted) ?line.id];
    return VocalGapFillResult(
      document.copyWith(
        metadata: report.record(ids).writeTo(document.metadata),
      ),
      report,
    );
  }

  static VocalGapFillSpanReport _recount(
    VocalGapFillSpanReport report,
    LyricVocalGapWindow window,
    List<LyricLine> inserted,
  ) {
    final count = inserted
        .where(
          (line) =>
              line.startTime >= window.start && line.startTime < window.end,
        )
        .length;
    return VocalGapFillSpanReport(
      start: report.start,
      end: report.end,
      outcome: count > 0 ? report.outcome : VocalGapFillOutcome.empty,
      engine: count > 0 ? report.engine : null,
      fellBack: count > 0 && report.fellBack,
      insertedLines: count,
      error: report.error,
    );
  }
}

class _Selection {
  /// Indices into the plan's items, in timeline order.
  final List<int> sent;
  final List<VocalGapFillSpanReport> reports;

  const _Selection(this.sent, this.reports);
}

class _Attempt {
  final VocalGapFillOutcome outcome;
  final LyricVocalGapInsertion? insertion;
  final LyricSpanEngine? engine;
  final bool fellBack;
  final String? error;
  final VocalGapFillStopReason? stop;

  const _Attempt(
    this.outcome, {
    this.insertion,
    this.engine,
    this.fellBack = false,
    this.error,
    this.stop,
  });
}
