import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/app_router.dart';
import 'package:lyric_forge_ktv/main.dart';

void main() {
  testWidgets('LyricForge app root keeps production shell wiring', (
    WidgetTester tester,
  ) async {
    MaterialApp? builtApp;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final root = const LyricForgeApp().build(context);
            expect(root, isA<MaterialApp>());
            builtApp = root as MaterialApp;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(builtApp, isNotNull);
    expect(builtApp!.title, 'LyricForge KTV');
    expect(builtApp!.initialRoute, Routes.home);
    expect(builtApp!.onGenerateRoute, isNotNull);
    expect(builtApp!.builder, isNotNull);
    expect(builtApp!.debugShowCheckedModeBanner, isFalse);
  });

  testWidgets('mobile root renders Navigator child without desktop overlay', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    MaterialApp? builtApp;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            builtApp = const LyricForgeApp().build(context) as MaterialApp;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final marker = Container(key: const ValueKey('mobile-navigator-child'));
    late Widget shell;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            shell = builtApp!.builder!(context, marker);
            return shell;
          },
        ),
      ),
    );

    expect(shell, same(marker));
    expect(builtApp!.navigatorObservers, isEmpty);
    expect(find.byKey(const ValueKey('mobile-navigator-child')), findsOneWidget);
  });
}
