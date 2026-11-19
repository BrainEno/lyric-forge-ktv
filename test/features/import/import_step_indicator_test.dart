import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/features/import/presentation/widgets/import_step_indicator.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

Color? _markerColor(WidgetTester tester, ImportStep step) {
  final marker = tester.widget<Container>(
    find.byKey(ValueKey('import-step:${step.name}')),
  );
  return (marker.decoration! as BoxDecoration).color;
}

void main() {
  testWidgets('the preparation step is current and choosing songs is next', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const ImportStepIndicator(current: ImportStep.prepare)),
    );

    expect(find.text('准备识别环境'), findsOneWidget);
    expect(find.text('选择歌曲'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(_markerColor(tester, ImportStep.prepare), AppColors.accent);
    expect(_markerColor(tester, ImportStep.choose), AppColors.bgSurface);
  });

  testWidgets('on the second step the first one shows a check', (tester) async {
    await tester.pumpWidget(
      _host(const ImportStepIndicator(current: ImportStep.choose)),
    );

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    expect(_markerColor(tester, ImportStep.choose), AppColors.accent);
  });

  testWidgets('screen readers hear one summary instead of loose labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const ImportStepIndicator(current: ImportStep.prepare)),
    );

    final summary = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == '第 1 步，共 2 步：准备识别环境',
    );
    expect(summary, findsOneWidget);
    expect(tester.widget<Semantics>(summary).child, isA<ExcludeSemantics>());
  });

  testWidgets('fits a narrow window without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(const ImportStepIndicator(current: ImportStep.choose)),
    );

    expect(tester.takeException(), isNull);
  });

  test('the environment gate is titled for what it does', () {
    final gate = File(
      'lib/features/import/presentation/screens/'
      'transcription_ready_import_screen.dart',
    ).readAsStringSync();
    final import = File(
      'lib/features/import/presentation/screens/import_audio_screen.dart',
    ).readAsStringSync();

    expect(gate, contains("title: const Text('准备识别环境')"));
    expect(gate, contains('ImportStepIndicator(current: ImportStep.prepare)'));
    expect(import, contains('ImportStepIndicator(current: ImportStep.choose)'));
    expect(import, isNot(contains('_FeaturePill')));
  });
}
