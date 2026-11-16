import '../../../project/domain/models/lyric_document.dart';
import 'lyric_asr_loop_detector.dart';
import 'lyric_pace_analyzer.dart';
import 'lyric_repetition_consistency_service.dart';
import 'lyric_structure_advisor.dart';
import 'lyric_text_cleanup_service.dart';
import 'lyric_timeline_repair_planner.dart';

/// Mechanical problems in a recognised draft that a batch tool can fix.
///
/// Each count matches what the corresponding tool would offer when opened, so
/// a hint never promises work the tool then cannot find:
///
/// * [captionRows] — caption boilerplate (谢谢观看, 字幕由…提供) and rows that are
///   nothing but [音乐]-style annotations: the text clean-up tool deletes them;
/// * [repetitionGroups] — a repeated line spelt differently across its
///   occurrences: the repeated-line consistency tool unifies them;
/// * [longLines] and [fragments] — rows too long for one karaoke line and
///   fragments a recogniser pause cut off: the line-structure tool splits and
///   merges them;
/// * [timelineRows] — rows with timeline faults (overlaps, an end before the
///   start, a start out of lyric order): the timeline check repairs what it
///   can by rule and lists the rest for manual timing;
/// * [paceRows] — rows sung far faster or slower than the rest of the song
///   (an end cut at a breath, a row spanning an interlude, dropped or
///   invented words): the pace check proposes end times and lists the rest
///   for listening;
/// * [loopRows] — rows where the recogniser looped (a phrase repeated a dozen
///   times in one row, or a run of identical rows): the recognition loop
///   check cuts them down.
///
/// Counts ignore manual-edit protection on purpose: they describe the draft,
/// and each tool still asks before touching a hand-edited row.
class LyricDraftHealth {
  final int captionRows;
  final int repetitionGroups;
  final int longLines;
  final int fragments;
  final int timelineRows;
  final int paceRows;
  final int loopRows;

  const LyricDraftHealth({
    required this.captionRows,
    required this.repetitionGroups,
    required this.longLines,
    required this.fragments,
    this.timelineRows = 0,
    this.paceRows = 0,
    this.loopRows = 0,
  });

  static const LyricDraftHealth clean = LyricDraftHealth(
    captionRows: 0,
    repetitionGroups: 0,
    longLines: 0,
    fragments: 0,
  );

  int get structureIssues => longLines + fragments;

  bool get hasIssues =>
      captionRows > 0 ||
      repetitionGroups > 0 ||
      structureIssues > 0 ||
      timelineRows > 0 ||
      paceRows > 0 ||
      loopRows > 0;
}

/// Computes [LyricDraftHealth] for a document.
///
/// The editor rebuilds on every playback tick, so results are memoised per
/// document instance: documents are immutable and every edit produces a new
/// one, which makes identity a safe cache key.
class LyricDraftHealthService {
  const LyricDraftHealthService({
    this.cleanup = const LyricTextCleanupService(),
    this.repetition = const LyricRepetitionConsistencyService(),
    this.structure = const LyricStructureAdvisor(),
    this.timeline = const LyricTimelineRepairPlanner(),
    this.pace = const LyricPaceAnalyzer(),
    this.loops = const LyricAsrLoopDetector(),
  });

  final LyricTextCleanupService cleanup;
  final LyricRepetitionConsistencyService repetition;
  final LyricStructureAdvisor structure;
  final LyricTimelineRepairPlanner timeline;
  final LyricPaceAnalyzer pace;
  final LyricAsrLoopDetector loops;

  static final Expando<LyricDraftHealth> _cache = Expando<LyricDraftHealth>(
    'LyricDraftHealth',
  );

  /// [analyze], computed once per document instance.
  LyricDraftHealth cached(LyricDocument document) =>
      _cache[document] ??= analyze(document);

  LyricDraftHealth analyze(LyricDocument document) {
    if (document.lines.isEmpty) return LyricDraftHealth.clean;

    var captionRows = 0;
    for (final line in document.lines) {
      final text = line.text;
      if (text.trim().isEmpty) continue;
      if (cleanup.isAsrBoilerplate(text) || cleanup.isAnnotationOnly(text)) {
        captionRows++;
      }
    }

    final plan = structure.analyze(document);
    return LyricDraftHealth(
      captionRows: captionRows,
      repetitionGroups: repetition.analyze(document).groups.length,
      longLines: plan.splitCount,
      fragments: plan.mergeCount,
      // Without the audio length here, a tail past the audio end is only
      // found once the tool is opened with the project's audio.
      timelineRows: timeline.plan(document).problemRowCount,
      paceRows: pace.plan(document).issues.length,
      loopRows: loops.loopRowCount(document),
    );
  }
}
