import 'package:flutter/foundation.dart';

import '../../../player/domain/models/playback_state.dart';
import '../../domain/models/lyric_review_queue.dart';
import '../../domain/services/lyric_review_priority_service.dart';
import 'lyric_editor_toolbar.dart';

// Two more groups of LyricEditorContent inputs (audit E-04, after
// lyric_editor_actions.dart). The review queue and the player used to arrive
// as thirteen separate arguments, and the content worked out which rows a
// filter shows, which row is selected and where the playhead is from those
// loose values. Each group now carries its values and answers those
// questions itself, so the rules can be tested without building the editor.

/// Where the review queue stands and what the user can do with it.
@immutable
class LyricReviewControls {
  const LyricReviewControls({
    required this.queue,
    required this.priorityByIndex,
    required this.filter,
    required this.selectedLineIndex,
    required this.followPlayback,
    required this.onFilterChanged,
    required this.onFollowPlaybackChanged,
    required this.onSelectLine,
    required this.onDecision,
  });

  final LyricReviewQueue queue;

  /// The queue's priorities by row, cached by the screen.
  final Map<int, LyricReviewPriority> priorityByIndex;
  final LyricReviewFilter filter;

  /// The row the editor last selected; may point past the end after rows
  /// were deleted, see [selectionWithin].
  final int? selectedLineIndex;
  final bool followPlayback;
  final ValueChanged<LyricReviewFilter> onFilterChanged;
  final ValueChanged<bool> onFollowPlaybackChanged;
  final ValueChanged<int> onSelectLine;

  /// Records (`true`) or clears (`false`) the review of a row.
  final void Function(int index, bool reviewed) onDecision;

  /// The rows [filter] shows for a document of [lineCount] rows. All rows
  /// keep their order; a filtered list puts the most urgent rows first and
  /// keeps document order between rows of the same priority.
  List<int> visibleIndices(int lineCount) {
    final indices = <int>[
      for (var index = 0; index < lineCount; index++)
        if (_shows(index)) index,
    ];
    if (filter != LyricReviewFilter.all) {
      indices.sort((left, right) {
        final byPriority = _score(right).compareTo(_score(left));
        return byPriority != 0 ? byPriority : left.compareTo(right);
      });
    }
    return indices;
  }

  /// [selectedLineIndex] when it is still a row of a [lineCount]-row
  /// document; null otherwise, so no pane shows a row that is gone.
  int? selectionWithin(int lineCount) {
    final index = selectedLineIndex;
    if (index == null || index < 0 || index >= lineCount) return null;
    return index;
  }

  /// The row 开始复核 opens: the most urgent one, or null when nothing needs
  /// review.
  int? get firstQueuedLine =>
      queue.isEmpty ? null : queue.items.first.lineIndex;

  /// Whether a row can be marked or unmarked: it is in the queue, or it was
  /// already reviewed and the user may take that back.
  bool canRecordDecision(int index, {required bool isReviewed}) =>
      isReviewed || priorityByIndex.containsKey(index);

  bool _shows(int index) => switch (filter) {
    LyricReviewFilter.all => true,
    LyricReviewFilter.needsReview => queue.needsReview(index),
    LyricReviewFilter.lowConfidence => queue.isLowConfidence(index),
  };

  int _score(int index) => priorityByIndex[index]?.score ?? 0;
}

/// The player as the editor sees it: its state, whether it is playing this
/// project at all, and the two things the editor asks of it.
@immutable
class LyricPlaybackControls {
  const LyricPlaybackControls({
    required this.state,
    required this.belongsToProject,
    required this.onSeek,
    required this.onToggle,
  });

  final PlaybackState state;

  /// The player holds this project's audio. When it holds another song, its
  /// position and play state say nothing about these lyrics.
  final bool belongsToProject;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onToggle;

  /// Playing this project's audio.
  bool get isPlaying => belongsToProject && state.isPlaying;

  /// The row being sung at the playhead, given each row's start time
  /// ([starts], in document order) and the document's global [offset]. Null
  /// when the player is on another song or there are no rows; before the
  /// first row it is the first row.
  int? lineAt(List<Duration> starts, {Duration offset = Duration.zero}) {
    if (!belongsToProject || starts.isEmpty) return null;
    for (var index = starts.length - 1; index >= 0; index--) {
      final shifted = starts[index] + offset;
      final effective = shifted.isNegative ? Duration.zero : shifted;
      if (state.position >= effective) return index;
    }
    return 0;
  }

  /// The paused playhead in document time (before the global [offset]), or
  /// null while the audio plays or belongs to another song: a moving
  /// playhead says nothing about where a line should end.
  Duration? pausedPlayhead({Duration offset = Duration.zero}) {
    if (!belongsToProject || state.isPlaying) return null;
    final shifted = state.position - offset;
    return shifted.isNegative ? Duration.zero : shifted;
  }
}
