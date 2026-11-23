import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_review_controls.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';

LyricReviewPriority _priority(int index, int score) =>
    LyricReviewPriority(lineIndex: index, score: score, reasons: const []);

/// Rows 1, 3 and 4 need review; 3 and 4 also have a low engine score.
final _priorities = [_priority(4, 60), _priority(1, 30), _priority(3, 60)];

final _queue = LyricReviewQueue(
  items: _priorities,
  lowConfidenceIndices: const {3, 4},
  totalLines: 6,
  scoredLines: 6,
  reviewedLines: 0,
  confidenceThreshold: kLyricReviewConfidenceThreshold,
);

LyricReviewControls _review({
  LyricReviewQueue? queue,
  LyricReviewFilter filter = LyricReviewFilter.all,
  int? selected,
  List<String>? calls,
}) {
  final effective = queue ?? _queue;
  return LyricReviewControls(
    queue: effective,
    priorityByIndex: effective.byIndex,
    filter: filter,
    selectedLineIndex: selected,
    followPlayback: true,
    onFilterChanged: (value) => calls?.add('filter:${value.name}'),
    onFollowPlaybackChanged: (value) => calls?.add('follow:$value'),
    onSelectLine: (index) => calls?.add('select:$index'),
    onDecision: (index, reviewed) => calls?.add('decide:$index:$reviewed'),
  );
}

LyricPlaybackControls _player({
  Duration position = Duration.zero,
  bool playing = false,
  bool ours = true,
}) {
  return LyricPlaybackControls(
    state: const PlaybackState.idle().copyWith(
      position: position,
      isPlaying: playing,
    ),
    belongsToProject: ours,
    onSeek: (_) {},
    onToggle: () {},
  );
}

const _starts = [
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 9),
];

void main() {
  group('LyricReviewControls', () {
    test('the full list keeps every row in document order', () {
      expect(_review().visibleIndices(6), [0, 1, 2, 3, 4, 5]);
    });

    test('建议复核 lists queued rows, most urgent first', () {
      final review = _review(filter: LyricReviewFilter.suggested);
      // 3 and 4 share a score, so they keep document order.
      expect(review.visibleIndices(6), [3, 4, 1]);
    });

    test('rows past the end of the document are never listed', () {
      final review = _review(filter: LyricReviewFilter.suggested);
      expect(review.visibleIndices(4), [3, 1]);
      expect(review.visibleIndices(0), isEmpty);
    });

    test('a selection survives only while its row exists', () {
      expect(_review(selected: 2).selectionWithin(6), 2);
      expect(_review(selected: 5).selectionWithin(6), 5);
      expect(_review(selected: 6).selectionWithin(6), isNull);
      expect(_review(selected: -1).selectionWithin(6), isNull);
      expect(_review().selectionWithin(6), isNull);
    });

    test('开始复核 opens the most urgent row', () {
      expect(_review().firstQueuedLine, 4);
      expect(_review(queue: LyricReviewQueue.empty).firstQueuedLine, isNull);
    });

    test('a decision is offered for queued or already reviewed rows', () {
      final review = _review();
      expect(review.canRecordDecision(1, isReviewed: false), isTrue);
      expect(review.canRecordDecision(2, isReviewed: false), isFalse);
      // A reviewed row has left the queue; the user can still take it back.
      expect(review.canRecordDecision(2, isReviewed: true), isTrue);
    });

    test('callbacks pass straight through to the screen', () {
      final calls = <String>[];
      final review = _review(calls: calls);
      review.onFilterChanged(LyricReviewFilter.suggested);
      review.onFollowPlaybackChanged(false);
      review.onSelectLine(3);
      review.onDecision(3, true);
      expect(calls, [
        'filter:suggested',
        'follow:false',
        'select:3',
        'decide:3:true',
      ]);
    });
  });

  group('LyricPlaybackControls', () {
    test('plays only while the player holds this project', () {
      expect(_player(playing: true).isPlaying, isTrue);
      expect(_player(playing: true, ours: false).isPlaying, isFalse);
      expect(_player().isPlaying, isFalse);
    });

    test('finds the row being sung at the playhead', () {
      Duration at(int seconds) => Duration(seconds: seconds);
      expect(_player(position: at(0)).lineAt(_starts), 0);
      expect(_player(position: at(5)).lineAt(_starts), 1);
      expect(_player(position: at(8)).lineAt(_starts), 1);
      expect(_player(position: at(30)).lineAt(_starts), 2);
    });

    test('shifts row starts by the global offset', () {
      final player = _player(position: const Duration(seconds: 5));
      // With a one-second delay row 1 starts at 6 s, so 5 s is still row 0.
      expect(player.lineAt(_starts, offset: const Duration(seconds: 1)), 0);
      // An early offset that would start a row before zero clamps to zero.
      expect(player.lineAt(_starts, offset: const Duration(seconds: -9)), 2);
    });

    test('has no current row for another song or an empty document', () {
      final other = _player(position: const Duration(seconds: 5), ours: false);
      expect(other.lineAt(_starts), isNull);
      expect(_player().lineAt(const []), isNull);
    });

    test('offers the playhead as a break only while paused', () {
      final paused = _player(position: const Duration(seconds: 7));
      expect(paused.pausedPlayhead(), const Duration(seconds: 7));
      expect(
        paused.pausedPlayhead(offset: const Duration(seconds: 2)),
        const Duration(seconds: 5),
      );
      expect(
        paused.pausedPlayhead(offset: const Duration(seconds: 9)),
        Duration.zero,
      );
      final playing = _player(
        position: const Duration(seconds: 7),
        playing: true,
      );
      expect(playing.pausedPlayhead(), isNull);
      final other = _player(position: const Duration(seconds: 7), ours: false);
      expect(other.pausedPlayhead(), isNull);
    });
  });
}
