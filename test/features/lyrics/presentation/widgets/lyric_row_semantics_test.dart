import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_review_controls.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_list_pane.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_row_semantics.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_word_timing_strip.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

Duration _ms(int value) => Duration(milliseconds: value);

const _first = LyricLine(
  id: 'a',
  text: '月亮代表我的心',
  startTime: Duration(milliseconds: 12400),
  endTime: Duration(milliseconds: 15100),
);

const _priority = LyricReviewPriority(lineIndex: 1, score: 60, reasons: []);

const _document = LyricDocument(
  language: 'zh',
  lines: [
    _first,
    LyricLine(
      id: 'b',
      text: '你问我爱你有多深',
      startTime: Duration(milliseconds: 15100),
      endTime: Duration(milliseconds: 18000),
    ),
    LyricLine(
      id: 'c',
      text: '',
      startTime: Duration(milliseconds: 18000),
      endTime: Duration(milliseconds: 20000),
    ),
  ],
);

/// The editor list over [_document], with row 1 queued and [selected]
/// selected; every row callback records what it did in [calls].
Widget _list(List<String> calls, {int? selected, LyricDocument? document}) {
  final lines = document ?? _document;
  return MaterialApp(
    home: Scaffold(
      body: LyricListPane(
        document: lines,
        visibleIndices: const [0, 1, 2],
        review: LyricReviewControls(
          queue: const LyricReviewQueue(
            items: [_priority],
            lowConfidenceIndices: {},
            totalLines: 3,
            scoredLines: 3,
            reviewedLines: 0,
            confidenceThreshold: 70,
          ),
          priorityByIndex: const {1: _priority},
          filter: LyricReviewFilter.all,
          selectedLineIndex: selected,
          followPlayback: false,
          onFilterChanged: (_) {},
          onFollowPlaybackChanged: (_) {},
          onSelectLine: (_) {},
          onDecision: (_, _) {},
        ),
        activeAuditionLineIndex: null,
        auditionPlaying: false,
        currentPlaybackLine: 0,
        focusRequestId: 0,
        focusLineIndex: null,
        fallbackCandidateFor: (_) => null,
        onPreviewLine: (index) => calls.add('audition:$index'),
        onInsertedLineFocus: (_) {},
        onSelectLine: (index) => calls.add('select:$index'),
        onUpdateLine: (index, _) => calls.add('update:$index'),
        onDeleteLine: (index) => calls.add('delete:$index'),
        onSplitLine: (index, offset) => calls.add('split:$index'),
        onMergeLineWithNext: (index) => calls.add('merge:$index'),
        onSetStartFromPlayback: (index) => calls.add('markStart:$index'),
        onSetEndFromPlayback: (index) => calls.add('markEnd:$index'),
      ),
    ),
  );
}

/// The [Semantics] widget whose label starts with [prefix].
Semantics _semanticsStartingWith(WidgetTester tester, String prefix) {
  return tester.widget<Semantics>(
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (widget.properties.label?.startsWith(prefix) ?? false),
    ),
  );
}

List<String> _actionLabels(Semantics semantics) => [
  for (final action in semantics.properties.customSemanticsActions!.keys)
    action.label,
];

void main() {
  group('rowLabel', () {
    test('reads number, time span and text in one sentence', () {
      expect(
        LyricRowSemantics.rowLabel(index: 0, line: _first),
        '第 1 行，00:12.40 到 00:15.10，月亮代表我的心',
      );
    });

    test('an empty row says so instead of reading nothing', () {
      final label = LyricRowSemantics.rowLabel(
        index: 2,
        line: _document.lines[2],
      );
      expect(label, '第 3 行，00:18.00 到 00:20.00，${LyricRowSemantics.emptyText}');
    });

    test('states that were only colour or an icon are spoken', () {
      final label = LyricRowSemantics.rowLabel(
        index: 0,
        line: _first.copyWith(isChorus: true),
        playing: true,
        priority: _priority,
        hasCandidate: true,
        isSecondarySuggestion: true,
        isManuallyEdited: true,
      );
      expect(
        label,
        '第 1 行，00:12.40 到 00:15.10，月亮代表我的心，副歌，正在播放，'
        '待复核，优先级 60，有另一引擎的候选，建议补入，已手动修改',
      );
    });

    test('a reviewed row drops the review prompts', () {
      final label = LyricRowSemantics.rowLabel(
        index: 0,
        line: _first,
        isReviewed: true,
        priority: _priority,
        hasCandidate: true,
        isSecondarySuggestion: true,
      );
      expect(label, endsWith('月亮代表我的心，已复核'));
    });
  });

  group('small labels', () {
    test('a time span is read without the dash', () {
      expect(
        LyricRowSemantics.timeRange(_ms(1000), _ms(61500)),
        '00:01.00 到 01:01.50',
      );
    });

    test('an editable time says which one and that it can change', () {
      expect(
        LyricRowSemantics.editableTime(start: true, time: _ms(1200)),
        '开始时间 00:01.20，点按修改',
      );
      expect(
        LyricRowSemantics.editableTime(start: false, time: _ms(3400)),
        '结束时间 00:03.40，点按修改',
      );
    });

    test('a word chip says whether a tap seeks', () {
      expect(
        LyricRowSemantics.wordChip(
          word: ' 我 ',
          start: _ms(1000),
          end: _ms(1400),
          canSeek: true,
        ),
        '我，00:01.00 到 00:01.40，点按跳到这里',
      );
      expect(
        LyricRowSemantics.wordChip(
          word: '',
          start: _ms(1000),
          end: _ms(1400),
          canSeek: false,
        ),
        '${LyricRowSemantics.emptyText}，00:01.00 到 00:01.40',
      );
    });
  });

  group('rowActions', () {
    test('lists only the edits that exist, in menu order', () {
      final actions = LyricRowSemantics.rowActions(
        onEditText: () {},
        onSplit: () {},
        onDelete: () {},
      );
      expect(actions.keys.map((action) => action.label), [
        LyricRowSemantics.editText,
        LyricRowSemantics.split,
        LyricRowSemantics.delete,
      ]);
    });

    test('a read-only row offers nothing', () {
      expect(LyricRowSemantics.rowActions(), isEmpty);
    });

    test('the audition action follows the play state', () {
      String audition({required bool playing}) {
        final actions = LyricRowSemantics.rowActions(
          onAudition: () {},
          auditionPlaying: playing,
        );
        return actions.keys.single.label;
      }

      expect(audition(playing: false), LyricRowSemantics.auditionPlay);
      expect(audition(playing: true), LyricRowSemantics.auditionPause);
    });

    test('each action runs its own callback', () {
      final calls = <String>[];
      final actions = LyricRowSemantics.rowActions(
        onMerge: () => calls.add('merge'),
        onCopy: () => calls.add('copy'),
      );
      actions[const CustomSemanticsAction(label: LyricRowSemantics.copy)]!();
      actions[const CustomSemanticsAction(label: LyricRowSemantics.merge)]!();
      expect(calls, ['copy', 'merge']);
    });
  });

  group('editor rows', () {
    late List<String> calls;

    setUp(() => calls = <String>[]);

    Future<void> pump(WidgetTester tester, Widget widget) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(widget);
    }

    testWidgets('each row is one labelled node, not loose pieces', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _list(calls, selected: 1));

      expect(
        find.bySemanticsLabel(RegExp(r'^第 1 行，00:12\.40 到 00:15\.10，')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^第 2 行，.*待复核')), findsOneWidget);
      // The pieces are not read a second time on their own.
      expect(find.bySemanticsLabel('月亮代表我的心'), findsNothing);
      expect(find.bySemanticsLabel('00:12.40'), findsNothing);
      handle.dispose();
    });

    testWidgets('the selection, the playhead and the tap are on the node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _list(calls, selected: 1));

      final first = _semanticsStartingWith(tester, '第 1 行');
      final second = _semanticsStartingWith(tester, '第 2 行');
      expect(first.properties.label, contains('正在播放'));
      expect(first.properties.selected, isFalse);
      expect(second.properties.selected, isTrue);
      expect(second.properties.button, isTrue);

      second.properties.onTap!();
      expect(calls, ['select:1']);
      handle.dispose();
    });

    testWidgets('gesture-only edits are custom actions', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _list(calls));

      final first = _semanticsStartingWith(tester, '第 1 行');
      expect(_actionLabels(first), [
        LyricRowSemantics.auditionPlay,
        LyricRowSemantics.editText,
        LyricRowSemantics.editStart,
        LyricRowSemantics.editEnd,
        LyricRowSemantics.startFromPlayback,
        LyricRowSemantics.endFromPlayback,
        LyricRowSemantics.split,
        LyricRowSemantics.merge,
        LyricRowSemantics.copy,
        LyricRowSemantics.delete,
      ]);

      final actions = first.properties.customSemanticsActions!;
      for (final label in [
        LyricRowSemantics.auditionPlay,
        LyricRowSemantics.startFromPlayback,
        LyricRowSemantics.split,
        LyricRowSemantics.merge,
        LyricRowSemantics.delete,
      ]) {
        actions[CustomSemanticsAction(label: label)]!();
      }
      expect(calls, [
        'audition:0',
        'markStart:0',
        'split:0',
        'merge:0',
        'delete:0',
      ]);

      // The last row has nothing to merge with.
      final last = _semanticsStartingWith(tester, '第 3 行');
      expect(_actionLabels(last), isNot(contains(LyricRowSemantics.merge)));
      handle.dispose();
    });

    testWidgets('a reviewed row says so', (tester) async {
      final handle = tester.ensureSemantics();
      final reviewed = const LyricReviewDecisionService().setReviewed(
        _document,
        1,
        reviewed: true,
      );
      await pump(tester, _list(calls, document: reviewed));

      final second = _semanticsStartingWith(tester, '第 2 行');
      expect(second.properties.label, endsWith('已复核'));
      expect(second.properties.label, isNot(contains('待复核')));
      handle.dispose();
    });

    testWidgets('the inline editor names its two times', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _list(calls));

      // The long press that opens the editor, as a screen reader sends it.
      _semanticsStartingWith(tester, '第 1 行').properties.onLongPress!();
      await tester.pumpAndSettle();

      expect(find.byType(InlineLyricEditorRow), findsOneWidget);
      expect(find.bySemanticsLabel('开始时间 00:12.40，点按修改'), findsOneWidget);
      expect(find.bySemanticsLabel('结束时间 00:15.10，点按修改'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('→')), findsNothing);
      handle.dispose();
    });
  });

  group('word timing chips', () {
    final timed = LyricLine(
      text: '我爱你',
      startTime: _ms(1000),
      endTime: _ms(6000),
      words: [
        LyricWordTiming(text: '我', start: _ms(1000), end: _ms(1400)),
        LyricWordTiming(text: '爱', start: _ms(1400), end: _ms(1800)),
        LyricWordTiming(text: '你', start: _ms(2000), end: _ms(6000)),
      ],
    );

    testWidgets('a seekable chip is a button that says where it jumps', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final seeks = <Duration>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricWordTimingStrip(line: timed, onSeek: seeks.add),
          ),
        ),
      );

      final chip = _semanticsStartingWith(tester, '爱，');
      expect(chip.properties.label, '爱，00:01.40 到 00:01.80，点按跳到这里');
      expect(chip.properties.button, isTrue);
      chip.properties.onTap!();
      expect(seeks, [_ms(1400)]);
      // The start time printed under the word is not read on its own.
      expect(find.bySemanticsLabel('0:01.4'), findsNothing);
      handle.dispose();
    });

    testWidgets('a display-only chip is not announced as a button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LyricWordTimingStrip(line: timed))),
      );

      final chip = _semanticsStartingWith(tester, '我，');
      expect(chip.properties.label, '我，00:01.00 到 00:01.40');
      expect(chip.properties.button, isFalse);
      expect(chip.properties.onTap, isNull);
      handle.dispose();
    });
  });
}
