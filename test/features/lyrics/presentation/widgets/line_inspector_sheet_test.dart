import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/layout/app_responsive.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/line_inspector_sheet.dart';

const _phone = Size(390, 844);
const _listKey = ValueKey('inspector-list');

Future<void> _open(
  WidgetTester tester, {
  Size size = _phone,
  bool editingText = false,
  String? previousLine = '前一句歌词',
  String? nextLine = '后一句歌词',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  Widget inspector(ScrollController controller) => ListView(
    key: _listKey,
    controller: controller,
    children: [
      for (var i = 0; i < 30; i++) SizedBox(height: 48, child: Text('row $i')),
    ],
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => LineInspectorSheet(
                  editingText: editingText,
                  previousLine: previousLine,
                  nextLine: nextLine,
                  inspectorBuilder: inspector,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Top edge of the sheet, in logical pixels from the top of the screen.
double _sheetTop(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(LineInspectorSheet.handleKey)).dy;

/// Where the top edge sits when the sheet fills [fraction] of [height].
double _topAt(double fraction, {double height = 844}) =>
    height * (1 - fraction);

void main() {
  group('LineInspectorSheet.sizesFor', () {
    AppLayoutSpec layout(Size size) =>
        AppResponsive.fromSize(size, desktopPlatform: false);

    test('opens part-way on a phone so the lyric list stays visible', () {
      final sizes = LineInspectorSheet.sizesFor(
        layout(_phone),
        editingText: false,
      );
      expect(sizes.initial, 0.62);
      expect(sizes.min, lessThan(sizes.initial));
      expect(sizes.max, greaterThan(sizes.initial));
      expect(sizes.snapSizes, [0.62]);
    });

    test('opens tall when the text field is focused on open', () {
      final sizes = LineInspectorSheet.sizesFor(
        layout(_phone),
        editingText: true,
      );
      expect(sizes.initial, sizes.max);
      expect(sizes.snapSizes, isEmpty);
    });

    test('opens nearly full height on short screens', () {
      final sizes = LineInspectorSheet.sizesFor(
        layout(const Size(800, 500)),
        editingText: false,
      );
      expect(sizes.initial, 0.96);
      expect(sizes.max, 0.96);
      expect(sizes.snapSizes, isEmpty);
    });
  });

  group('LineInspectorSheet.settleSize', () {
    const sizes = LineInspectorSheetSizes(initial: 0.62, min: 0.4, max: 0.92);

    test('rests at the closest stop after a slow drag', () {
      expect(LineInspectorSheet.settleSize(sizes, 0.45), 0.4);
      expect(LineInspectorSheet.settleSize(sizes, 0.58), 0.62);
      expect(LineInspectorSheet.settleSize(sizes, 0.81), 0.92);
    });

    test('moves one stop in the direction of a fling', () {
      expect(LineInspectorSheet.settleSize(sizes, 0.63, velocity: -900), 0.92);
      expect(LineInspectorSheet.settleSize(sizes, 0.61, velocity: 900), 0.4);
      expect(LineInspectorSheet.settleSize(sizes, 0.45, velocity: -900), 0.62);
    });

    test('stays at the ends when flung past them', () {
      expect(LineInspectorSheet.settleSize(sizes, 0.92, velocity: -900), 0.92);
      expect(LineInspectorSheet.settleSize(sizes, 0.4, velocity: 900), 0.4);
    });
  });

  group('LineInspectorSheet', () {
    testWidgets('opens at about 60 % with the neighbouring lines', (
      tester,
    ) async {
      await _open(tester);

      expect(_sheetTop(tester), closeTo(_topAt(0.62), 1));
      expect(find.byKey(LineInspectorSheet.contextKey), findsOneWidget);
      expect(find.text('上一行：前一句歌词'), findsOneWidget);
      expect(find.text('下一行：后一句歌词'), findsOneWidget);
      expect(find.text('row 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens tall for a new line being typed', (tester) async {
      await _open(tester, editingText: true);

      expect(_sheetTop(tester), closeTo(_topAt(0.92), 1));
    });

    testWidgets('opens nearly full height on a short screen', (tester) async {
      await _open(tester, size: const Size(800, 500));

      expect(_sheetTop(tester), closeTo(_topAt(0.96, height: 500), 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides the context block for the only line', (tester) async {
      await _open(tester, previousLine: null, nextLine: '  ');

      expect(find.byKey(LineInspectorSheet.contextKey), findsNothing);
      expect(find.textContaining('上一行'), findsNothing);
      expect(find.textContaining('下一行'), findsNothing);
    });

    testWidgets('shows only the neighbour that exists', (tester) async {
      await _open(tester, previousLine: null);

      expect(find.textContaining('上一行'), findsNothing);
      expect(find.text('下一行：后一句歌词'), findsOneWidget);
    });

    testWidgets('drags up by the handle to the full inspector', (tester) async {
      await _open(tester);

      await tester.drag(
        find.byKey(LineInspectorSheet.handleKey),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(_sheetTop(tester), closeTo(_topAt(0.92), 1));
    });

    testWidgets('drags down by the handle to reveal more of the list', (
      tester,
    ) async {
      await _open(tester);

      await tester.drag(
        find.byKey(LineInspectorSheet.handleKey),
        const Offset(0, 150),
      );
      await tester.pumpAndSettle();

      expect(_sheetTop(tester), closeTo(_topAt(0.4), 1));
      expect(find.byKey(LineInspectorSheet.handleKey), findsOneWidget);
    });

    testWidgets('pulling the inspector down at its top shrinks the sheet', (
      tester,
    ) async {
      await _open(tester);
      final openTop = _sheetTop(tester);

      await tester.drag(find.text('row 2'), const Offset(0, 200));
      await tester.pumpAndSettle();

      expect(_sheetTop(tester), greaterThan(openTop + 50));
      expect(find.byKey(_listKey), findsOneWidget);
    });

    testWidgets('closes from the labelled close button', (tester) async {
      await _open(tester);

      final close = find.byKey(LineInspectorSheet.closeKey);
      expect(find.byTooltip('关闭'), findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();

      expect(find.byKey(LineInspectorSheet.handleKey), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('stays above the on-screen keyboard', (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _open(tester, editingText: true);

      final listBottom = tester.getBottomLeft(find.byKey(_listKey)).dy;
      expect(listBottom, closeTo(844 - 300, 1));
      expect(_sheetTop(tester), closeTo(_topAt(0.92, height: 544), 1));
      expect(tester.takeException(), isNull);
    });
  });
}
