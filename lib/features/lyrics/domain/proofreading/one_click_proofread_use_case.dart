import '../../../project/domain/models/lyric_document.dart';
import '../models/chinese_script_preference.dart';
import '../online/online_lyric_matcher.dart';
import '../services/chinese_script_unification_service.dart';
import '../services/lyric_alignment_service.dart';
import '../services/lyric_asr_loop_detector.dart';
import '../services/lyric_manual_edit_marker_service.dart';
import '../services/lyric_repetition_consistency_service.dart';
import '../services/lyric_text_cleanup_service.dart';
import '../services/lyric_timeline_repair_planner.dart';
import '../services/reference_alignment_batch_selector.dart';
import '../services/reference_timeline_completion_service.dart';
import 'apply_reference_alignment_use_case.dart';

/// Metadata key recording which online lyric a one-click pass used.
const String kOneClickProofreadMetadataKey = 'oneClickProofread';

/// What one pass of 一键校对 did, for the summary and the review that follows.
class OneClickProofreadResult {
  /// The proofread document; equal to the draft when nothing changed.
  final LyricDocument document;

  /// The online lyric that corrected the text; null without one.
  final OnlineLyricMatch? reference;

  /// Rows whose text the lyric corrected.
  final int correctedLines;

  /// Rows the recogniser missed, filled in from the lyric.
  final int insertedLines;

  /// Rows already spelt exactly as in the lyric; now trusted.
  final int verifiedLines;

  /// Rows the mechanical clean-up rewrote (punctuation, [音乐] marks …).
  final int cleanedLines;

  /// Rows written in the minority Chinese script (a 繁體 row in a 简体
  /// draft) converted to the script the rest of the draft uses.
  final int scriptFixes;

  /// Rows deleted as recogniser output that is not lyrics: captions such as
  /// 谢谢观看 and rows repeated by a recognition loop.
  final int removedLines;

  /// Rows the loop check shortened (deleted rows count as [removedLines]).
  final int loopFixes;

  /// Rows unified with the majority spelling of their repeats (only without
  /// a lyric, which is better evidence).
  final int repetitionFixes;

  /// Row timings repaired by rule (overlaps, zero lengths, short gaps).
  final int timelineFixes;

  /// Lyric rows that could not be applied safely and need a person: weak or
  /// ambiguous matches and missed rows without a safe slot.
  final int uncertainLines;

  /// Draft rows the lyric does not contain (ad-libs, or recogniser output
  /// the other steps could not prove wrong).
  final int unmatchedDraftLines;

  /// Rows left alone because they were edited by hand.
  final int skippedProtectedLines;

  /// A lyric was found but applying it would have broken the timeline, so
  /// only the clean-up steps ran.
  final bool referenceRejected;

  /// The first row this pass changed, to select in the editor.
  final int? firstChangedIndex;

  const OneClickProofreadResult({
    required this.document,
    required this.reference,
    this.correctedLines = 0,
    this.insertedLines = 0,
    this.verifiedLines = 0,
    this.cleanedLines = 0,
    this.scriptFixes = 0,
    this.removedLines = 0,
    this.loopFixes = 0,
    this.repetitionFixes = 0,
    this.timelineFixes = 0,
    this.uncertainLines = 0,
    this.unmatchedDraftLines = 0,
    this.skippedProtectedLines = 0,
    this.referenceRejected = false,
    this.firstChangedIndex,
  });

  bool get usedReference => reference != null && !referenceRejected;

  /// Whether the document differs from the draft in text, rows or timing.
  bool get hasChanges =>
      correctedLines > 0 ||
      insertedLines > 0 ||
      verifiedLines > 0 ||
      cleanedLines > 0 ||
      scriptFixes > 0 ||
      removedLines > 0 ||
      loopFixes > 0 ||
      repetitionFixes > 0 ||
      timelineFixes > 0;

  /// Rows that still deserve a look after the pass.
  int get remainingReviewCount => uncertainLines + unmatchedDraftLines;
}

/// 一键校对: every safe correction in one undoable pass.
///
/// With an online lyric that matched the draft ([OnlineLyricMatch.accepted]):
/// the reference alignment's safe batch (D-006/D-010) corrects confidently
/// matched rows and fills missed rows into safe gaps, keeping the recording's
/// own timing (D-052); rows spelt exactly like the lyric are marked as
/// trusted. Then, with or without a lyric: the default text clean-up, the
/// simplified/traditional unification (D-053), the strong recognition-loop
/// fixes, (without a lyric) the clear repetition
/// unifications, and the confident timeline repairs. Rows edited by hand are
/// never changed. Anything uncertain is counted, not guessed.
class OneClickProofreadUseCase {
  const OneClickProofreadUseCase();

  static const LyricManualEditMarkerService _markers =
      LyricManualEditMarkerService();

  /// [scriptPreference] decides the Chinese script rows are unified to; by
  /// default the one recognition last unified to (see
  /// [scriptPreferenceFor]).
  OneClickProofreadResult build({
    required LyricDocument draft,
    OnlineLyricMatch? reference,
    Set<int> protectedIndices = const {},
    Duration? audioDuration,
    ChineseScriptPreference? scriptPreference,
    required DateTime appliedAt,
  }) {
    // Stable ids let protection and the first changed row follow rows
    // through insertions and deletions.
    var document = _markers.assignMissingLineIds(draft);
    final protectedIds = <String>{
      for (final index in protectedIndices)
        if (index >= 0 && index < document.lines.length)
          ?document.lines[index].id,
    };
    Set<int> protectedNow() => {
      for (var index = 0; index < document.lines.length; index++)
        if (protectedIds.contains(document.lines[index].id)) index,
    };
    final changedIds = <String>{};
    void markChanged(int index) {
      if (index < 0 || index >= document.lines.length) return;
      final id = document.lines[index].id;
      if (id != null) changedIds.add(id);
    }

    var corrected = 0;
    var inserted = 0;
    var verified = 0;
    var uncertain = 0;
    var unmatched = 0;
    var referenceRejected = false;
    var referenceTimelineRepairs = 0;
    final skippedProtected = <String>{};

    // Mechanical clean-up: punctuation, full-width letters, [音乐] marks and
    // caption boilerplate (谢谢观看) the recogniser invents on silence.
    final cleanup = const LyricTextCleanupService().plan(
      document,
      protectedIndices: protectedNow(),
    );
    for (final index in cleanup.skippedProtectedIndices) {
      if (document.lines[index].id case final id?) skippedProtected.add(id);
    }
    var removed = cleanup.removals.length;
    if (cleanup.hasChanges) {
      for (final change in cleanup.changes) {
        markChanged(change.index);
      }
      document = cleanup.applyTo(document);
    }

    // Simplified/traditional: recognisers mix both in one song. Only the
    // rows in the minority script change (or every row, when recognition
    // was told to output one script), so a consistent draft is untouched.
    final script = const ChineseScriptUnificationService().plan(
      document,
      preference: scriptPreference ?? scriptPreferenceFor(document),
      protectedIndices: protectedNow(),
    );
    for (final index in script.skippedProtectedIndices) {
      if (document.lines[index].id case final id?) skippedProtected.add(id);
    }
    if (script.hasChanges) {
      for (final change in script.changes) {
        markChanged(change.index);
      }
      document = script.applyTo(document);
    }

    // Recognition loops: only findings far beyond what songs repeat.
    const loopDetector = LyricAsrLoopDetector();
    final loops = loopDetector.plan(document, protectedIndices: protectedNow());
    final loopPositions = loops.defaultPositions.toSet();
    var loopFixes = 0;
    if (loopPositions.isNotEmpty) {
      final counts = loops.countFor(loopPositions);
      loopFixes = counts.rewritten;
      removed += counts.removed;
      for (final position in loopPositions) {
        final issue = loops.issues[position];
        if (!issue.removesRows) markChanged(issue.index);
      }
      document = loops.applyTo(document, loopPositions);
    }

    if (reference != null && reference.accepted) {
      final plan = const ApplyReferenceAlignmentUseCase().prepare(
        draft: document,
        input: reference.input,
        protectedLineIndices: protectedNow(),
        audioDuration: audioDuration,
      );
      final completion = const ReferenceTimelineCompletionService().buildPlan(
        document: document,
        alignment: plan.alignment,
        audioDuration: audioDuration,
      );
      final selection = const ReferenceAlignmentBatchSelector().select(
        alignment: plan.alignment,
        completionPlan: completion,
        minimumSimilarity: plan.minimumSimilarity,
        protectedLineIndices: plan.protectedLineIndices,
      );
      var acceptedMissing = selection.safeMissingReferenceIndices;
      var proposal = plan.apply(
        acceptedReferenceIndices: selection.safeReferenceIndices,
        acceptedMissingReferenceIndices: acceptedMissing,
        overriddenAsrLineIndices: const {},
        applyReferenceTiming: false,
      );
      if (_breaksTimeline(proposal) && acceptedMissing.isNotEmpty) {
        acceptedMissing = const {};
        proposal = plan.apply(
          acceptedReferenceIndices: selection.safeReferenceIndices,
          acceptedMissingReferenceIndices: acceptedMissing,
          overriddenAsrLineIndices: const {},
          applyReferenceTiming: false,
        );
      }
      if (_breaksTimeline(proposal)) {
        referenceRejected = true;
      } else {
        final result = proposal.result;
        final before = document;
        if (result.hasChanges) {
          document = proposal.materialize(appliedAt: appliedAt);
        }
        corrected = result.corrections.length;
        inserted = result.insertions.length;
        referenceTimelineRepairs = result.timelineRepairs.length;
        for (final correction in result.corrections) {
          markChanged(
            result.appliedIndexByOriginalIndex[correction.asrLineIndex] ??
                correction.asrLineIndex,
          );
        }
        for (final insertion in result.insertions) {
          markChanged(insertion.appliedLineIndex);
        }
        for (final index in result.skippedManuallyEditedIndices) {
          if (before.lines[index].id case final id?) skippedProtected.add(id);
        }

        // Rows the lyric confirms word for word are as trustworthy as rows
        // it corrected (which the applier sets to 100).
        final lines = List<LyricLine>.of(document.lines);
        for (final entry in plan.alignment.entries) {
          final asrIndex = entry.asrLineIndex;
          if (asrIndex == null ||
              entry.status != ReferenceLineAlignmentStatus.identical ||
              entry.ambiguous ||
              entry.structuralMismatch ||
              plan.protectedLineIndices.contains(asrIndex)) {
            continue;
          }
          final index =
              result.appliedIndexByOriginalIndex[asrIndex] ?? asrIndex;
          if (index >= lines.length) continue;
          final line = lines[index];
          if (!line.hasConfidenceScore || line.confidence >= 100) continue;
          lines[index] = line.copyWith(confidence: 100);
          verified++;
        }
        if (verified > 0) document = document.copyWith(lines: lines);

        final protectedReferences = {
          for (final entry in plan.alignment.entries)
            if (entry.asrLineIndex case final index?
                when plan.protectedLineIndices.contains(index))
              entry.referenceIndex,
        };
        uncertain =
            selection.uncertainReferenceIndices
                .difference(protectedReferences)
                .length +
            selection.uncertainMissingReferenceIndices.length +
            (selection.safeMissingReferenceIndices.length -
                acceptedMissing.length);
        unmatched = plan.alignment.unmatchedAsrIndices.length;
        document = document.copyWith(
          metadata: {
            ...document.metadata,
            kOneClickProofreadMetadataKey: _provenance(reference, appliedAt),
          },
        );
      }
    }

    // Without a lyric, the other repeats of a chorus are the best evidence.
    var repetitionFixes = 0;
    if (reference == null || !reference.accepted || referenceRejected) {
      final report = const LyricRepetitionConsistencyService().analyze(
        document,
        protectedIndices: protectedNow(),
      );
      final choices = <int, int>{
        for (var index = 0; index < report.groups.length; index++)
          if (report.groups[index].selectedByDefault)
            index: report.groups[index].recommendedVariant!,
      };
      final changes = report.changesFor(document, choices);
      if (changes.isNotEmpty) {
        repetitionFixes = changes.length;
        for (final change in changes) {
          markChanged(change.index);
        }
        document = LyricRepetitionReport.apply(document, changes);
      }
    }

    // Timing repairs that follow from the neighbours; re-slotting a row out
    // of order is a judgement and is left to the timeline check.
    final timeline = const LyricTimelineRepairPlanner().plan(
      document,
      protectedIndices: protectedNow(),
      audioDuration: audioDuration,
    );
    final timelinePositions = {
      for (var position = 0; position < timeline.fixes.length; position++)
        if (timeline.fixes[position].confident) position,
    };
    if (timelinePositions.isNotEmpty) {
      for (final position in timelinePositions) {
        markChanged(timeline.fixes[position].index);
      }
      document = timeline.applyTo(document, timelinePositions);
    }

    int? firstChanged;
    for (var index = 0; index < document.lines.length; index++) {
      if (changedIds.contains(document.lines[index].id)) {
        firstChanged = index;
        break;
      }
    }

    final result = OneClickProofreadResult(
      document: document,
      reference: reference != null && reference.accepted ? reference : null,
      correctedLines: corrected,
      insertedLines: inserted,
      verifiedLines: verified,
      cleanedLines: cleanup.changes.length,
      scriptFixes: script.changes.length,
      removedLines: removed,
      loopFixes: loopFixes,
      repetitionFixes: repetitionFixes,
      timelineFixes: timelinePositions.length + referenceTimelineRepairs,
      uncertainLines: uncertain,
      unmatchedDraftLines: unmatched,
      skippedProtectedLines: skippedProtected.length,
      referenceRejected: referenceRejected,
      firstChangedIndex: firstChanged,
    );
    // Nothing changed: hand back the caller's own document, without ids.
    if (!result.hasChanges) {
      return OneClickProofreadResult(
        document: draft,
        reference: result.reference,
        uncertainLines: uncertain,
        unmatchedDraftLines: unmatched,
        skippedProtectedLines: skippedProtected.length,
        referenceRejected: referenceRejected,
      );
    }
    return result;
  }

  /// The script preference recorded by the last unification (recognition
  /// applies the user's 中文字形 setting and records it), else automatic.
  static ChineseScriptPreference scriptPreferenceFor(LyricDocument document) {
    final record = ChineseScriptUnificationRecord.tryParse(
      document.metadata[ChineseScriptUnificationService.metadataKey],
    );
    if (record == null || record.preference == ChineseScriptPreference.keep) {
      return ChineseScriptPreference.auto;
    }
    return record.preference;
  }

  static bool _breaksTimeline(ReferenceAlignmentProposal proposal) =>
      proposal.result.timelineComparison?.hasIntroducedSeriousIssues == true;

  static Map<String, dynamic> _provenance(
    OnlineLyricMatch match,
    DateTime appliedAt,
  ) => <String, dynamic>{
    'appliedAt': appliedAt.toIso8601String(),
    'source': match.candidate.source.name,
    'sourceId': match.candidate.sourceId,
    'title': match.candidate.title,
    'artist': match.candidate.artist,
    'draftCoverage': double.parse(match.draftCoverage.toStringAsFixed(3)),
    'referenceCoverage': double.parse(
      match.referenceCoverage.toStringAsFixed(3),
    ),
    'timed': match.input.timed,
    if (match.timingOffset != null)
      'timingOffsetMs': match.timingOffset!.inMilliseconds,
    'timingDropped': match.timingDropped,
  };
}
