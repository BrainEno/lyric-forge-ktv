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
}
