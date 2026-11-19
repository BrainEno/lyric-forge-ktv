import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/presentation/widgets/project_detail_columns.dart';

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = const Size(1800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const ProjectDetailColumns(
              gap: 24,
              main: SizedBox(height: 200, child: Text('歌词')),
              side: SizedBox(height: 120, child: Text('操作')),
            ),
          ),
        ),
      ),
    ),
  );
}

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

void main() {
  group('ProjectDetailColumns rules', () {
    test('two columns start at the threshold', () {
      expect(ProjectDetailColumns.useTwoColumns(879), isFalse);
      expect(ProjectDetailColumns.useTwoColumns(880), isTrue);
    });

    test('the side column is a third of the row within bounds', () {
      expect(ProjectDetailColumns.sideWidthFor(880), 320);
      expect(ProjectDetailColumns.sideWidthFor(1100), closeTo(374, 0.01));
      expect(ProjectDetailColumns.sideWidthFor(1600), 440);
    });
  });

  testWidgets('narrow widths stack the actions above the lyric cards', (
    tester,
  ) async {
    await _pump(tester, 600);

    final main = _rect(tester, ProjectDetailColumns.mainKey);
    final side = _rect(tester, ProjectDetailColumns.sideKey);
    expect(side.bottom, lessThan(main.top));
    expect(main.top - side.bottom, 24);
    expect(side.width, 600);
    expect(main.width, 600);
  });

  testWidgets('wide widths put the actions beside the lyric cards', (
    tester,
  ) async {
    await _pump(tester, 1200);

    final main = _rect(tester, ProjectDetailColumns.mainKey);
    final side = _rect(tester, ProjectDetailColumns.sideKey);
    expect(side.top, main.top);
    expect(side.left - main.right, 24);
    expect(side.width, closeTo(ProjectDetailColumns.sideWidthFor(1200), 0.01));
    expect(main.width, closeTo(1200 - 24 - side.width, 0.01));
  });

  testWidgets('the given width decides, not the window', (tester) async {
    // The test window is 1800 px wide, which used to mean two columns. A
    // content area of 860 px (rail, gutters, a split view) stacks instead.
    await _pump(tester, 860);
    expect(
      _rect(tester, ProjectDetailColumns.sideKey).top,
      lessThan(_rect(tester, ProjectDetailColumns.mainKey).top),
    );

    await _pump(tester, 940);
    expect(
      _rect(tester, ProjectDetailColumns.sideKey).top,
      _rect(tester, ProjectDetailColumns.mainKey).top,
    );
  });
}
