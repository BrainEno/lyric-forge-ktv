import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/app_loading_state.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows a labelled spinner without text by default', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AppLoadingState()));

    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.semanticsLabel, AppLoadingState.defaultSemanticsLabel);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a message appears below the spinner and labels it', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AppLoadingState(message: '正在读取工程')));

    final spinnerFinder = find.byType(CircularProgressIndicator);
    final spinner = tester.widget<CircularProgressIndicator>(spinnerFinder);
    expect(spinner.semanticsLabel, '正在读取工程');
    expect(find.text('正在读取工程'), findsOneWidget);
    final textTop = tester.getTopLeft(find.text('正在读取工程')).dy;
    final spinnerBottom = tester.getBottomLeft(spinnerFinder).dy;
    expect(textTop, greaterThan(spinnerBottom));
  });

  testWidgets('fits inside a short pane', (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(height: 120, child: AppLoadingState(message: '正在读取音乐库')),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  group('AppInlineLoading', () {
    // The spinner builds its own Container, so the card is the one with a
    // decoration.
    Finder card() => find.descendant(
      of: find.byType(AppInlineLoading),
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.decoration != null,
      ),
    );

    testWidgets('puts a small labelled spinner beside the text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const Center(child: AppInlineLoading(message: '正在检查磁盘'))),
      );

      final spinnerFinder = find.byType(CircularProgressIndicator);
      final spinner = tester.widget<CircularProgressIndicator>(spinnerFinder);
      expect(spinner.semanticsLabel, '正在检查磁盘');
      expect(spinner.strokeWidth, 2);
      expect(
        tester.getSize(spinnerFinder),
        const Size.square(AppInlineLoading.spinnerSize),
      );
      // Beside, not below: the text starts right of the spinner on its row.
      final text = find.text('正在检查磁盘');
      expect(
        tester.getTopLeft(text).dx,
        greaterThan(tester.getTopRight(spinnerFinder).dx),
      );
      expect(
        tester.getCenter(text).dy,
        moreOrLessEquals(tester.getCenter(spinnerFinder).dy, epsilon: 2),
      );
    });

    testWidgets('unframed it hugs its content', (tester) async {
      await tester.pumpWidget(
        _host(const Center(child: AppInlineLoading(message: '正在重新识别…'))),
      );

      expect(card(), findsNothing);
      final width = tester.getSize(find.byType(AppInlineLoading)).width;
      expect(width, lessThan(300));
    });

    testWidgets('framed it fills the width inside a rounded card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Padding(
            padding: EdgeInsets.all(16),
            child: AppInlineLoading(message: '正在检测电脑配置', framed: true),
          ),
        ),
      );

      final frame = tester.widget<Container>(card());
      final decoration = frame.decoration! as BoxDecoration;
      expect(decoration.borderRadius, isNotNull);
      expect(decoration.border, isNotNull);
      final width = tester.getSize(find.byType(AppInlineLoading)).width;
      expect(width, moreOrLessEquals(800 - 32));
    });

    testWidgets('long text wraps instead of overflowing', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 160,
            child: AppInlineLoading(
              message: '正在检查安装磁盘可用空间，这可能需要一点时间…',
              framed: true,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('is announced as a live region', (tester) async {
      await tester.pumpWidget(
        _host(const Center(child: AppInlineLoading(message: '正在检查磁盘'))),
      );

      expect(
        find.descendant(
          of: find.byType(AppInlineLoading),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
    });
  });
}
