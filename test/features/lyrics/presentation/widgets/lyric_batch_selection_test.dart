import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_selection_bar.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_shift_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_list_pane.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

import 'lyric_list_pane_test.dart' show reviewFor;

LyricDocument _document(int count) => LyricDocument(
  language: 'zh',
  lines: [
    for (var index = 0; index < count; index++)
      LyricLine(
        id: 'line-$index',
        text: '第 ${index + 1} 行',
        startTime: Duration(seconds: index * 4 + 1),
        endTime: Duration(seconds: index * 4 + 3),
      ),
  ],
);

/// What the list asked the batch controls to do.
class _Batch {
  final toggled = <(int, bool)>[];
  final ranges = <(int, List<int>)>[];
  final all = <List<int>>[];
  final selectedRows = <int>[];
  int ended = 0;
  int deleted = 0;

  LyricBatchControls controls({required bool active, Set<int>? chosen}) =>
      LyricBatchControls(
        active: active,
        selected: chosen ?? const {},
        onToggle: (index, {includeCurrent = false}) =>
            toggled.add((index, includeCurrent)),
        onRange: (index, order) => ranges.add((index, order)),
        onSelectAll: all.add,
        onEnd: () => ended++,
        onDelete: () => deleted++,
      );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('the list in batch mode', () {
    late _Batch batch;

    setUp(() => batch = _Batch());

    Widget host({
      bool active = false,
      Set<int>? chosen,
      List<int>? visible,
      int? selectedLine = 0,
    }) {
      final document = _document(5);
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: LyricListPane(
              document: document,
              visibleIndices: visible ?? const [0, 1, 2, 3, 4],
              review: reviewFor(document, selectedLine: selectedLine),
              activeAuditionLineIndex: null,
              auditionPlaying: false,
              currentPlaybackLine: null,
              focusRequestId: 0,
              focusLineIndex: null,
              fallbackCandidateFor: (_) => null,
              onPreviewLine: null,
              onInsertedLineFocus: (_) {},
              onSelectLine: batch.selectedRows.add,
              onUpdateLine: (_, _) {},
              onDeleteLine: (_) {},
              batch: batch.controls(active: active, chosen: chosen),
            ),
          ),
        ),
      );
    }

    Future<void> tapWith(
      WidgetTester tester,
      LogicalKeyboardKey modifier,
      String text,
    ) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.tap(find.text(text));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    testWidgets('Ctrl+click adds a row and keeps the one selected before', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tapWith(tester, LogicalKeyboardKey.controlLeft, '第 3 行');
      expect(batch.toggled, [(2, true)]);
      expect(batch.selectedRows, isEmpty);
    });

    testWidgets('Shift+click chooses through the shown rows', (tester) async {
      await tester.pumpWidget(host(visible: [0, 2, 4]));
      await tapWith(tester, LogicalKeyboardKey.shiftLeft, '第 5 行');
      expect(batch.ranges.single.$1, 4);
      expect(batch.ranges.single.$2, [0, 2, 4]);
    });

    testWidgets('a long press starts choosing instead of editing', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.longPress(find.text('第 2 行'));
      await tester.pump();
      expect(batch.toggled, [(1, false)]);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('in batch mode a tap chooses and the rows show check boxes', (
      tester,
    ) async {
      await tester.pumpWidget(host(active: true, chosen: {1}));
      expect(find.byKey(const ValueKey('lyric_row_check_0')), findsOneWidget);
      expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
      expect(
        find.byIcon(Icons.check_box_outline_blank_rounded),
        findsNWidgets(4),
      );

      await tester.tap(find.text('第 4 行'));
      await tester.pump();
      expect(batch.toggled, [(3, false)]);
      expect(batch.selectedRows, isEmpty);
    });

    testWidgets('keys: Shift+↓ extends, Ctrl+A, Ctrl+Delete and Esc', (
      tester,
    ) async {
      await tester.pumpWidget(host(active: true, chosen: {0, 1}));
      await tester.tap(find.text('第 1 行'));
      await tester.pump();
      batch.toggled.clear();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(batch.ranges.single.$1, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(batch.all.single, [0, 1, 2, 3, 4]);
      expect(batch.deleted, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(batch.ended, 1);
    });
  });

  group('LyricBatchActionBar', () {
    final calls = <String>[];

    Widget bar({
      int count = 2,
      bool allReviewed = false,
      bool canMerge = true,
      double textScale = 1,
    }) {
      return MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: LyricBatchActionBar(
            count: count,
            allReviewed: allReviewed,
            canMerge: canMerge,
            onEnd: () => calls.add('end'),
            onSelectAll: () => calls.add('all'),
            onMarkReviewed: (value) => calls.add('reviewed $value'),
            onShift: () => calls.add('shift'),
            onMerge: () => calls.add('merge'),
            onCopy: () => calls.add('copy'),
            onDelete: () => calls.add('delete'),
          ),
        ),
      );
    }

    setUp(calls.clear);

    testWidgets('a wide window labels every action', (tester) async {
      await _setSize(tester, const Size(1400, 800));
      await tester.pumpWidget(bar());
      expect(find.text('已选 2 行'), findsOneWidget);
      for (final label in ['全选', '标记已复核', '平移时间', '合并成一行', '复制文字', '删除']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.byKey(LyricBatchActionBar.reviewKey));
      await tester.tap(find.byKey(LyricBatchActionBar.mergeKey));
      await tester.tap(find.byKey(LyricBatchActionBar.deleteKey));
      await tester.tap(find.byKey(LyricBatchActionBar.endKey));
      expect(calls, ['reviewed true', 'merge', 'delete', 'end']);
    });

    testWidgets('all reviewed offers to clear the marks', (tester) async {
      await _setSize(tester, const Size(1400, 800));
      await tester.pumpWidget(bar(allReviewed: true));
      await tester.tap(find.text('取消复核'));
      expect(calls, ['reviewed false']);
    });

    testWidgets('merge is off with a reason when rows are apart', (
      tester,
    ) async {
      await _setSize(tester, const Size(1400, 800));
      await tester.pumpWidget(bar(canMerge: false));
      final merge = tester.widget<TextButton>(
        find.byKey(LyricBatchActionBar.mergeKey),
      );
      expect(merge.onPressed, isNull);
      expect(
        find.byTooltip(LyricBatchStrings.mergeNeedsNeighbours),
        findsOneWidget,
      );
    });

    testWidgets('nothing chosen: only leaving and choosing all work', (
      tester,
    ) async {
      await _setSize(tester, const Size(1400, 800));
      await tester.pumpWidget(bar(count: 0, canMerge: false));
      expect(find.text(LyricBatchStrings.nothingChosen), findsOneWidget);
      final delete = tester.widget<TextButton>(
        find.byKey(LyricBatchActionBar.deleteKey),
      );
      expect(delete.onPressed, isNull);
    });

    testWidgets('a phone at double text size keeps three and a menu', (
      tester,
    ) async {
      await _setSize(tester, const Size(320, 568));
      await tester.pumpWidget(bar(textScale: 2));
      expect(tester.takeException(), isNull);
      expect(find.byKey(LyricBatchActionBar.reviewKey), findsOneWidget);
      expect(find.byKey(LyricBatchActionBar.shiftKey), findsOneWidget);
      expect(find.byKey(LyricBatchActionBar.deleteKey), findsOneWidget);
      expect(find.byKey(LyricBatchActionBar.mergeKey), findsNothing);

      await tester.tap(find.byKey(LyricBatchActionBar.moreKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('合并成一行'));
      await tester.pumpAndSettle();
      expect(calls, ['merge']);
    });

    test('the 多选 tooltip names the platform key', () {
      expect(
        LyricBatchStrings.startTooltip(TargetPlatform.macOS),
        contains('⌘+点击'),
      );
      expect(
        LyricBatchStrings.startTooltip(TargetPlatform.windows),
        contains('Ctrl+点击'),
      );
    });
  });

  group('the batch shift dialog', () {
    Future<void> open(WidgetTester tester, List<int> rows) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLyricBatchShiftDialog(
                context,
                document: _document(4),
                rows: rows,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('steps preview the moved rows and confirm the offset', (
      tester,
    ) async {
      Duration? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showLyricBatchShiftDialog(
                  context,
                  document: _document(4),
                  rows: const [0, 2],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('平移 2 行的时间'), findsOneWidget);
      final confirm = find.byKey(LyricBatchShiftDialog.confirmKey);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.tap(find.byKey(LyricBatchShiftDialog.nudgeKey(1000)));
      await tester.tap(find.byKey(LyricBatchShiftDialog.nudgeKey(-100)));
      await tester.pump();
      expect(find.text('第 1 行  0:01.00 → 0:01.90'), findsOneWidget);
      expect(find.text('第 3 行  0:09.00 → 0:09.90'), findsOneWidget);

      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(picked, const Duration(milliseconds: 900));
    });

    testWidgets('a typed offset that is not a number is explained', (
      tester,
    ) async {
      await open(tester, const [1]);
      await tester.enterText(find.byKey(LyricBatchShiftDialog.offsetKey), 'x');
      await tester.pump();
      expect(find.text('请输入秒数，例如 0.5 或 -1.2'), findsOneWidget);
      final confirm = find.byKey(LyricBatchShiftDialog.confirmKey);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    });

    testWidgets('an overlap it would cause is shown before confirming', (
      tester,
    ) async {
      await open(tester, const [0]);
      await tester.enterText(
        find.byKey(LyricBatchShiftDialog.offsetKey),
        '2.5',
      );
      await tester.pump();
      expect(find.textContaining('会新增'), findsOneWidget);
    });
  });
}
