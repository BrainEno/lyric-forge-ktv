import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_actions.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_review_controls.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_inspector_pane.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_list_pane.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// The list and the inspector take the editor's review and playback groups
// directly (audit E-04). These tests pin what each pane now works out from
// the groups instead of receiving it precomputed.

const _document = LyricDocument(
  language: 'zh',
  globalOffset: Duration(milliseconds: 500),
  lines: [
    LyricLine(
      id: 'a',
      text: '第一行',
      startTime: Duration(seconds: 1),
      endTime: Duration(seconds: 4),
    ),
    LyricLine(
      id: 'b',
      text: '第二行',
      startTime: Duration(seconds: 4),
      endTime: Duration(seconds: 8),
    ),
    LyricLine(
      id: 'c',
      text: '第三行',
      startTime: Duration(seconds: 8),
      endTime: Duration(seconds: 12),
    ),
  ],
);

/// Row 1 is queued for review; rows 0 and 2 are not.
const _priority = LyricReviewPriority(lineIndex: 1, score: 50, reasons: []);

LyricReviewControls _review({
  int? selected,
  LyricReviewFilter filter = LyricReviewFilter.all,
  bool followPlayback = false,
  List<String>? calls,
}) {
  return LyricReviewControls(
    queue: const LyricReviewQueue(
      items: [_priority],
      lowConfidenceIndices: {},
      totalLines: 3,
      scoredLines: 3,
      reviewedLines: 0,
      confidenceThreshold: 70,
    ),
    priorityByIndex: const {1: _priority},
    filter: filter,
    selectedLineIndex: selected,
    followPlayback: followPlayback,
    onFilterChanged: (value) => calls?.add('filter:${value.name}'),
    onFollowPlaybackChanged: (value) => calls?.add('follow:$value'),
    onSelectLine: (index) => calls?.add('select:$index'),
    onDecision: (index, reviewed) => calls?.add('decide:$index:$reviewed'),
  );
}

LyricPlaybackControls _player({
  bool ours = true,
  bool playing = false,
  Duration position = Duration.zero,
  List<Duration>? seeks,
}) {
  return LyricPlaybackControls(
    state: const PlaybackState.idle().copyWith(
      isPlaying: playing,
      position: position,
    ),
    belongsToProject: ours,
    onSeek: (value) => seeks?.add(value),
    onToggle: () {},
  );
}

LyricLineEditActions _edits(List<String> calls, {bool merge = false}) {
  return LyricLineEditActions(
    onAddLine: () {},
    onInsertAtPlayback: () {},
    onUpdateLine: (index, _) => calls.add('update:$index'),
    onDeleteLine: (index) => calls.add('delete:$index'),
    onMergeLineWithNext: merge ? (index) => calls.add('merge:$index') : null,
    onUpdateOffset: (_) {},
    onSetStartFromPlayback: (index) => calls.add('start:$index'),
    onSetEndFromPlayback: (index) => calls.add('end:$index'),
  );
}

LyricListPane _list(LyricReviewControls review, {LyricDocument? document}) {
  return LyricListPane(
    document: document ?? _document,
    visibleIndices: const [0, 1, 2],
    review: review,
    activeAuditionLineIndex: null,
    auditionPlaying: false,
    currentPlaybackLine: null,
    focusRequestId: 0,
    focusLineIndex: null,
    fallbackCandidateFor: (_) => null,
    onPreviewLine: null,
    onInsertedLineFocus: (_) {},
    onSelectLine: (_) {},
    onUpdateLine: (_, _) {},
    onDeleteLine: (_) {},
  );
}

void main() {
  group('LyricListPane reads the review group', () {
    test('filter and follow come from the group', () {
      final pane = _list(
        _review(filter: LyricReviewFilter.suggested, followPlayback: true),
      );

      expect(pane.filter, LyricReviewFilter.suggested);
      expect(pane.followPlayback, isTrue);
    });

    test('a selection past the end selects nothing', () {
      expect(_list(_review(selected: 2)).selectedIndex, 2);
      expect(_list(_review(selected: 3)).selectedIndex, isNull);
      expect(_list(_review(selected: -1)).selectedIndex, isNull);
      expect(_list(_review()).selectedIndex, isNull);
    });

    test('show all clears the filter, and is absent when unfiltered', () {
      final calls = <String>[];

      expect(_list(_review(calls: calls)).onShowAllLines, isNull);

      final filtered = _list(
        _review(filter: LyricReviewFilter.suggested, calls: calls),
      );
      filtered.onShowAllLines!();
      expect(calls, ['filter:all']);
    });

    testWidgets('the selected and queued rows are marked', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _list(_review(selected: 2)))),
      );

      final rows = tester
          .widgetList<LyricReviewRow>(find.byType(LyricReviewRow))
          .toList();
      expect(rows.map((row) => row.selected), [false, false, true]);
      expect(rows.map((row) => row.priority?.score), [null, 50, null]);
    });
  });

  group('InspectorPane reads both groups', () {
    late List<String> calls;
    late List<Duration> seeks;

    setUp(() {
      calls = <String>[];
      seeks = <Duration>[];
    });

    Future<LineInspector?> pump(
      WidgetTester tester, {
      required LyricReviewControls review,
      required LyricPlaybackControls player,
      LyricDocument document = _document,
      bool merge = false,
    }) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: InspectorPane(
                document: document,
                review: review,
                player: player,
                fallbackCandidate: null,
                edits: _edits(calls, merge: merge),
                onPreviewLine: (index) => calls.add('preview:$index'),
                autofocusText: false,
                focusRequestId: 0,
              ),
            ),
          ),
        ),
      );
      final finder = find.byType(LineInspector);
      if (finder.evaluate().isEmpty) return null;
      return tester.widget<LineInspector>(finder);
    }

    testWidgets('no selection, or one past the end, shows the placeholder', (
      tester,
    ) async {
      expect(await pump(tester, review: _review(), player: _player()), isNull);
      expect(find.byType(NoSelectionInspector), findsOneWidget);

      expect(
        await pump(tester, review: _review(selected: 7), player: _player()),
        isNull,
      );
      expect(find.byType(NoSelectionInspector), findsOneWidget);
    });

    testWidgets('a queued row can be marked through the group', (tester) async {
      final inspector = await pump(
        tester,
        review: _review(selected: 1, calls: calls),
        player: _player(),
      );

      expect(inspector!.index, 1);
      expect(inspector.isReviewed, isFalse);
      inspector.onReviewDecision!(true);
      expect(calls, ['decide:1:true']);
    });

    testWidgets('a row outside the queue has nothing to record', (
      tester,
    ) async {
      final inspector = await pump(
        tester,
        review: _review(selected: 0, calls: calls),
        player: _player(),
      );

      expect(inspector!.onReviewDecision, isNull);
    });

    testWidgets('a reviewed row outside the queue can be taken back', (
      tester,
    ) async {
      final reviewed = const LyricReviewDecisionService().setReviewed(
        _document,
        0,
        reviewed: true,
      );
      final inspector = await pump(
        tester,
        document: reviewed,
        review: _review(selected: 0, calls: calls),
        player: _player(),
      );

      expect(inspector!.isReviewed, isTrue);
      inspector.onReviewDecision!(false);
      expect(calls, ['decide:0:false']);
    });

    testWidgets('the playhead row and play state come from the player', (
      tester,
    ) async {
      // Row 1 starts at 4 s; with the 0.5 s offset it is sung from 4.5 s.
      final inspector = await pump(
        tester,
        review: _review(selected: 1),
        player: _player(
          playing: true,
          position: const Duration(milliseconds: 4600),
        ),
      );

      expect(inspector!.isCurrentPlaybackLine, isTrue);
      expect(inspector.isPlaying, isTrue);
    });

    testWidgets('our song: seek adds the offset, playhead edits work', (
      tester,
    ) async {
      final inspector = await pump(
        tester,
        review: _review(selected: 1),
        player: _player(seeks: seeks),
      );

      inspector!.onSeekToTime!(const Duration(seconds: 5));
      expect(seeks, [const Duration(milliseconds: 5500)]);
      inspector.onUsePlaybackAsStart!();
      inspector.onUsePlaybackAsEnd!();
      expect(calls, ['start:1', 'end:1']);
    });

    testWidgets('another song: no seeking and no playhead edits', (
      tester,
    ) async {
      final inspector = await pump(
        tester,
        review: _review(selected: 1),
        player: _player(
          ours: false,
          playing: true,
          position: const Duration(milliseconds: 4600),
        ),
      );

      expect(inspector!.onSeekToTime, isNull);
      expect(inspector.onUsePlaybackAsStart, isNull);
      expect(inspector.onUsePlaybackAsEnd, isNull);
      expect(inspector.isCurrentPlaybackLine, isFalse);
      expect(inspector.isPlaying, isFalse);
    });

    testWidgets('the merge edit is offered except on the last row', (
      tester,
    ) async {
      var inspector = await pump(
        tester,
        review: _review(selected: 2),
        player: _player(),
        merge: true,
      );
      expect(inspector!.onMergeWithNext, isNull);

      inspector = await pump(
        tester,
        review: _review(selected: 1),
        player: _player(),
        merge: true,
      );
      inspector!.onMergeWithNext!();
      inspector.onPreview();
      expect(calls, ['merge:1', 'preview:1']);
    });
  });
}
