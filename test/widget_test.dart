import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/app_chrome_controller.dart';
import 'package:lyric_forge_ktv/app/app.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/core/theme/app_appearance_host.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';

/// The MaterialApp the root builds for [variant]: the root is the appearance
/// host (decision D-042), whose builder makes the MaterialApp.
MaterialApp _materialAppOf(
  ElysiumPlayerApp app,
  BuildContext context, [
  AppThemeVariant variant = AppThemeVariant.dark,
]) {
  final root = app.build(context);
  expect(root, isA<AppAppearanceHost>());
  return (root as AppAppearanceHost).builder(context, variant) as MaterialApp;
}

void main() {
  testWidgets('Elysium Player app root keeps production shell wiring', (
    WidgetTester tester,
  ) async {
    MaterialApp? builtApp;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            builtApp = _materialAppOf(const ElysiumPlayerApp(), context);
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

  testWidgets('mobile root renders the Navigator child under the chrome', (
    WidgetTester tester,
  ) async {
    AppChromeController.enterImmersive();

    try {
      MaterialApp? builtApp;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              builtApp = _materialAppOf(
                const ElysiumPlayerApp(desktopChromeOverride: false),
                context,
              );
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
      // The chrome has its own overlay on mobile too: without one the bottom
      // bar's destination tooltips had nowhere to go and threw.
      expect(
        find.byType(Overlay),
        findsNWidgets(2),
        reason: 'the app overlay plus the chrome overlay',
      );
    } finally {
      // Unmount listeners before restoring the shared chrome controller. This
      // keeps the test isolated when it runs as part of the full suite.
      await tester.pumpWidget(const SizedBox.shrink());
      AppChromeController.exitImmersive();
    }
  });

  testWidgets('the root builds the theme of the chosen variant', (
    WidgetTester tester,
  ) async {
    final built = <AppThemeVariant, MaterialApp>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            for (final variant in AppThemeVariant.values) {
              built[variant] = _materialAppOf(
                const ElysiumPlayerApp(),
                context,
                variant,
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(built[AppThemeVariant.dark]!.theme!.brightness, Brightness.dark);
    expect(built[AppThemeVariant.light]!.theme!.brightness, Brightness.light);
    expect(
      built[AppThemeVariant.light]!.theme!.scaffoldBackgroundColor,
      AppPalette.light.bgBase,
    );
    // AppColors switches at once, so the Material theme must not cross-fade.
    for (final app in built.values) {
      expect(app.themeAnimationDuration, Duration.zero);
    }
  });
}
