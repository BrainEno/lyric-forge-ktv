import '../../../project/domain/models/lyric_document.dart';
import 'lyric_repetition_consistency_service.dart';
import 'lyric_structure_advisor.dart';
import 'lyric_text_cleanup_service.dart';

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
///   merges them.
///
/// Counts ignore manual-edit protection on purpose: they describe the draft,
/// and each tool still asks before touching a hand-edited row.
class LyricDraftHealth {
  final int captionRows;
  final int repetitionGroups;
  final int longLines;
  final int fragments;

  const LyricDraftHealth({
    required this.captionRows,
    required this.repetitionGroups,
    required this.longLines,
    required this.fragments,
  });

  static const LyricDraftHealth clean = LyricDraftHealth(
    captionRows: 0,
    repetitionGroups: 0,
    longLines: 0,
    fragments: 0,
  );

  int get structureIssues => longLines + fragments;

  bool get hasIssues =>
      captionRows > 0 || repetitionGroups > 0 || structureIssues > 0;
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
  });

  final LyricTextCleanupService cleanup;
  final LyricRepetitionConsistencyService repetition;
  final LyricStructureAdvisor structure;

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
    );
  }
}
