import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/services/lyric_manual_edit_marker_service.dart';
import '../../domain/services/lyric_review_decision_service.dart';

/// What happened to a [ReviewInboxBulkReview] request.
enum BulkReviewStatus {
  /// The change is saved.
  saved,

  /// The project changed since the inbox read it (usually in the editor);
  /// nothing was written.
  conflict,

  /// Every line was already confirmed, or the project has no lyrics.
  unchanged,
}

/// Result of marking a project reviewed, or of undoing that.
class BulkReviewResult {
  const BulkReviewResult._({
    required this.status,
    this.previous,
    this.saved,
    this.markedLines = 0,
  });

  final BulkReviewStatus status;

  /// The project as it was before the change; the undo restores it.
  final ProjectManifest? previous;

  /// The project as saved.
  final ProjectManifest? saved;

  /// Lines confirmed by this change that were not confirmed before.
  final int markedLines;

  bool get canUndo =>
      status == BulkReviewStatus.saved && previous != null && saved != null;
}

/// "全部标为已复核" from the review inbox (audit R-03).
///
/// Confirming a project used to mean opening it in the editor and marking
/// the queued lines one by one, even when the user had already checked the
/// song elsewhere. This marks every line of one project as reviewed and
/// saves it, with the same optimistic revision check the editor uses, so a
/// newer save is never overwritten. The decisions are the editor's own
/// (fingerprinted per line), so editing a line's text or timing later puts
/// it back in the queue.
class ReviewInboxBulkReview {
  ReviewInboxBulkReview(
    this._projects, {
    LyricReviewDecisionService decisions = const LyricReviewDecisionService(),
    LyricManualEditMarkerService markers = const LyricManualEditMarkerService(),
    DateTime Function()? clock,
  }) : _decisions = decisions,
       _markers = markers,
       _clock = clock ?? DateTime.now;

  final ProjectRepository _projects;
  final LyricReviewDecisionService _decisions;
  final LyricManualEditMarkerService _markers;
  final DateTime Function() _clock;

  /// Marks every line of [project] reviewed and saves it.
  ///
  /// Lines from older documents without stable IDs get one first, as the
  /// editor does on open. Repository errors other than a revision conflict
  /// are rethrown for the caller to report.
  Future<BulkReviewResult> markAllReviewed(ProjectManifest project) async {
    final document = project.lyricDocument;
    if (document == null || document.lines.isEmpty) {
      return const BulkReviewResult._(status: BulkReviewStatus.unchanged);
    }
    final now = _clock();
    final before = _decisions.reviewedIndices(document).length;
    final updated = _decisions.setAllReviewed(
      _markers.assignMissingLineIds(document),
      reviewedAt: now,
    );
    if (identical(updated, document)) {
      return const BulkReviewResult._(status: BulkReviewStatus.unchanged);
    }
    final marked = _decisions.reviewedIndices(updated).length - before;
    try {
      final saved = await _projects.updateProjectIfUnchanged(
        project.copyWith(lyricDocument: updated, updatedAt: now),
        expectedRevision: project.revision,
      );
      return BulkReviewResult._(
        status: BulkReviewStatus.saved,
        previous: project,
        saved: saved,
        markedLines: marked,
      );
    } on ProjectUpdateConflictException {
      return const BulkReviewResult._(status: BulkReviewStatus.conflict);
    }
  }

  /// Puts back the lyrics from before [result], if nothing saved the
  /// project since.
  Future<BulkReviewResult> undo(BulkReviewResult result) async {
    final previous = result.previous;
    final saved = result.saved;
    if (!result.canUndo || previous == null || saved == null) {
      return const BulkReviewResult._(status: BulkReviewStatus.unchanged);
    }
    try {
      final restored = await _projects.updateProjectIfUnchanged(
        saved.copyWith(
          lyricDocument: previous.lyricDocument,
          updatedAt: _clock(),
        ),
        expectedRevision: saved.revision,
      );
      return BulkReviewResult._(
        status: BulkReviewStatus.saved,
        previous: saved,
        saved: restored,
      );
    } on ProjectUpdateConflictException {
      return const BulkReviewResult._(status: BulkReviewStatus.conflict);
    }
  }
}
