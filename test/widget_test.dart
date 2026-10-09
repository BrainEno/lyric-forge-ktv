import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/app_chrome_controller.dart';
import 'package:lyric_forge_ktv/core/navigation/app_router.dart';
import 'package:lyric_forge_ktv/main.dart';

void main() {
  testWidgets('Elysium Player app root keeps production shell wiring', (
    WidgetTester tester,
  ) async {
    MaterialApp? builtApp;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final root = const ElysiumPlayerApp().build(context);
            expect(root, isA<MaterialApp>());
            builtApp = root as MaterialApp;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(builtApp, isNotNull);
    expect(builtApp!.title, 'Elysium Player');
    expect(builtApp!.initialRoute, Routes.home);
    expect(builtApp!.onGenerateRoute, isNotNull);
    expect(builtApp!.builder, isNotNull);
    expect(builtApp!.debugShowCheckedModeBanner, isFalse);
  });

  testWidgets('mobile root renders Navigator child without desktop overlay', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    AppChromeController.enterImmersive();

    try {
      MaterialApp? builtApp;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              builtApp = const ElysiumPlayerApp().build(context) as MaterialApp;
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
      await tester.pump();

      expect(shell, isNot(isA<Overlay>()));
      expect(builtApp!.navigatorObservers, hasLength(1));
      expect(
        find.byKey(const ValueKey('mobile-navigator-child')),
        findsOneWidget,
      );
      expect(
        find.byType(Overlay),
        findsOneWidget,
        reason: 'mobile chrome must not add the desktop-only Overlay',
      );
    } finally {
      // Flutter verifies foundation debug globals before addTearDown callbacks
      // run, so restore this override before the test body returns.
      debugDefaultTargetPlatformOverride = null;
      AppChromeController.exitImmersive();
    }
  });
}
