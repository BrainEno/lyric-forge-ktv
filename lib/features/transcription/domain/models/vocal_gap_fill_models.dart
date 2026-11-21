import '../../../lyrics/domain/models/vocal_check_record.dart';
import '../../../lyrics/domain/models/vocal_gap_fill_record.dart';
import '../../../lyrics/domain/services/lyric_span_rerecognition.dart';
import '../../../project/domain/models/lyric_document.dart';

/// Whether whole-song recognition ends by recognising the stretches the
/// vocal check found singing but no row in, and inserting what it hears
/// (D-047).
enum VocalGapFillPreference {
  /// Fill missed lines whenever the vocal check found any.
  automatic,

  /// Leave them for the editor's "全部识别" (D-046).
  off;

  /// Unknown or missing values keep the default.
  static VocalGapFillPreference fromName(Object? name) =>
      VocalGapFillPreference.values.asNameMap()[name] ??
      VocalGapFillPreference.automatic;
}

/// Why the step did not run.
enum VocalGapFillSkipReason {
  /// Switched off in the settings.
  disabled,

  /// No vocal check ran on this draft, so nothing says where lyrics are
  /// missing (recognition of a mix, a failed or skipped check).
  noVocalCheck,

  /// The vocal check found no stretch of singing without a row.
  noGaps,

  /// No stretch fits a recognition window (all too short or too long).
  noWindows,

  /// No recogniser is ready for clips.
  noEngine,

  /// The step itself failed; the draft is kept as it was.
  failed,
}

/// Why the step ended before trying every stretch.
enum VocalGapFillStopReason {
  /// A recogniser or the runtime was busy; every later stretch would fail
  /// the same way.
  busy,

  /// The run was cancelled.
  cancelled,
}

/// What happened to one stretch.
enum VocalGapFillOutcome {
  /// At least one row went in.
  filled,

  /// Every engine tried heard no words that fit the window.
  empty,

  /// Every engine tried failed.
  failed,

  /// Too short or too long for a window.
  unsendable,

  /// Left out to keep the step within its budget.
  overBudget,

  /// Not tried because the step stopped early.
  notTried,
}

/// One stretch in a [VocalGapFillReport].
class VocalGapFillSpanReport {
  final Duration start;
  final Duration end;
  final VocalGapFillOutcome outcome;

  /// The engine whose rows went in, for [VocalGapFillOutcome.filled].
  final LyricSpanEngine? engine;

  /// Whether that engine was the fallback.
  final bool fellBack;

  /// Rows inserted for this stretch.
  final int insertedLines;

  /// The last error, for [VocalGapFillOutcome.failed].
  final String? error;

  const VocalGapFillSpanReport({
    required this.start,
    required this.end,
    required this.outcome,
    this.engine,
    this.fellBack = false,
    this.insertedLines = 0,
    this.error,
  });

  Map<String, Object?> toJson() => {
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'outcome': outcome.name,
    'engine': ?engine?.name,
    if (fellBack) 'fellBack': true,
    if (insertedLines > 0) 'insertedLines': insertedLines,
    'error': ?error,
  };
}

/// What the step did, for `metadata.transcription.vocalGapFill`.
class VocalGapFillReport {
  final bool applied;
  final VocalGapFillSkipReason? skipReason;
  final VocalGapFillStopReason? stopReason;

  /// Engines in the order they were tried for each stretch.
  final List<LyricSpanEngine> engines;
  final List<VocalGapFillSpanReport> spans;
  final Duration elapsed;
  final String? error;

  const VocalGapFillReport._({
    required this.applied,
    this.skipReason,
    this.stopReason,
    this.engines = const [],
    this.spans = const [],
    this.elapsed = Duration.zero,
    this.error,
  });

  const VocalGapFillReport.applied({
    required List<LyricSpanEngine> engines,
    required List<VocalGapFillSpanReport> spans,
    required Duration elapsed,
    VocalGapFillStopReason? stopReason,
  }) : this._(
         applied: true,
         engines: engines,
         spans: spans,
         elapsed: elapsed,
         stopReason: stopReason,
       );

  const VocalGapFillReport.skipped(
    VocalGapFillSkipReason reason, {
    List<LyricSpanEngine> engines = const [],
    List<VocalGapFillSpanReport> spans = const [],
    String? error,
  }) : this._(
         applied: false,
         skipReason: reason,
         engines: engines,
         spans: spans,
         error: error,
       );

  int _count(VocalGapFillOutcome outcome) =>
      spans.where((span) => span.outcome == outcome).length;

  int get filledSpans => _count(VocalGapFillOutcome.filled);
  int get emptySpans => _count(VocalGapFillOutcome.empty);
  int get failedSpans => _count(VocalGapFillOutcome.failed);

  /// Stretches never sent to a recogniser, for whatever reason.
  int get unattemptedSpans =>
      _count(VocalGapFillOutcome.unsendable) +
      _count(VocalGapFillOutcome.overBudget) +
      _count(VocalGapFillOutcome.notTried);

  int get fallbackSpans => spans
      .where((span) => span.outcome == VocalGapFillOutcome.filled)
      .where((span) => span.fellBack)
      .length;

  int get insertedLines =>
      spans.fold<int>(0, (total, span) => total + span.insertedLines);

  /// One line for the run's progress stream.
  String get summary {
    if (!applied) {
      return switch (skipReason) {
        VocalGapFillSkipReason.disabled => '未自动补全漏句（已在设置中关闭）',
        VocalGapFillSkipReason.noVocalCheck => '未自动补全漏句（本次没有人声检查）',
        VocalGapFillSkipReason.noGaps => '人声检查没有发现漏句',
        VocalGapFillSkipReason.noWindows => '漏句片段过短或过长，未自动识别',
        VocalGapFillSkipReason.noEngine => '没有可用的识别引擎，未自动补全漏句',
        VocalGapFillSkipReason.failed => '自动补全漏句失败，已保留原草稿',
        null => '未自动补全漏句',
      };
    }
    final parts = <String>[
      filledSpans > 0
          ? '已自动补上 $filledSpans 处漏句（$insertedLines 行）'
          : '自动补全漏句没有识别出新歌词',
      if (emptySpans > 0) '$emptySpans 处没有识别出文字',
      if (failedSpans > 0) '$failedSpans 处识别失败',
      if (unattemptedSpans > 0) '$unattemptedSpans 处未识别',
    ];
    final stopped = switch (stopReason) {
      VocalGapFillStopReason.busy => '（识别服务忙，提前结束）',
      VocalGapFillStopReason.cancelled => '（已取消）',
      null => '',
    };
    return '${parts.join('，')}$stopped';
  }

  Map<String, Object?> toJson() => {
    'applied': applied,
    'skipReason': skipReason?.name,
    'stopReason': ?stopReason?.name,
    'engines': [for (final engine in engines) engine.name],
    'gaps': spans.length,
    'filledSpans': filledSpans,
    'emptySpans': emptySpans,
    'failedSpans': failedSpans,
    'unattemptedSpans': unattemptedSpans,
    'fallbackSpans': fallbackSpans,
    'insertedLines': insertedLines,
    'elapsedMs': elapsed.inMilliseconds,
    'spans': [for (final span in spans) span.toJson()],
    'error': ?error,
  };

  /// The record kept in the document for the editor, given the ids of the
  /// rows that went in.
  LyricVocalGapFillRecord record(List<String> insertedLineIds) =>
      LyricVocalGapFillRecord(
        insertedLineIds: List.unmodifiable(insertedLineIds),
        filledSpans: [
          for (final span in spans)
            if (span.outcome == VocalGapFillOutcome.filled)
              LyricVocalCheckSpan(span.start, span.end),
        ],
        emptySpans: emptySpans,
        failedSpans: failedSpans,
        unattemptedSpans: unattemptedSpans,
        fallbackSpans: fallbackSpans,
      );
}

/// A draft after the step, with what was done to it.
class VocalGapFillResult {
  final LyricDocument document;
  final VocalGapFillReport report;

  const VocalGapFillResult(this.document, this.report);
}
