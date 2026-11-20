import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/app_destinations.dart';
import 'package:lyric_forge_ktv/core/navigation/app_navigation_shell.dart';
import 'package:lyric_forge_ktv/core/theme/app_appearance.dart';
import 'package:lyric_forge_ktv/core/theme/app_appearance_host.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_theme_menu_button.dart';

void main() {
  late AppAppearanceController controller;
  late MemoryAppearanceStore store;

  setUp(() {
    store = MemoryAppearanceStore();
    controller = AppAppearanceController(store: store);
  });

  tearDown(() => AppColors.usePalette(AppPalette.dark));

  Future<void> pumpAt(WidgetTester tester, Widget widget, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  group('AppThemeMenuButton', () {
    Widget host({bool extended = false}) {
      return AppAppearanceHost(
        controller: controller,
        builder: (context, variant) => MaterialApp(
          theme: AppTheme.themeFor(variant.palette),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                width: 200,
                child: AppThemeMenuButton(
                  controller: controller,
                  extended: extended,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows the icon and name of the theme in use', (tester) async {
      await tester.pumpWidget(host());

      expect(find.byKey(AppThemeMenuButton.buttonKey), findsOneWidget);
      expect(find.byIcon(AppThemeVariant.dark.icon), findsOneWidget);
      expect(
        find.byTooltip(AppThemeMenuButton.tooltipFor(AppThemeVariant.dark)),
        findsOneWidget,
      );
    });

    test('the tooltip names the theme and the action', () {
      expect(
        AppThemeMenuButton.tooltipFor(AppThemeVariant.light),
        contains('浅色'),
      );
      expect(
        AppThemeMenuButton.tooltipFor(AppThemeVariant.dark),
        contains('切换主题'),
      );
    });

    testWidgets('opens a list of every theme, the current one checked', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.tap(find.byKey(AppThemeMenuButton.buttonKey));
      await tester.pumpAndSettle();

      for (final variant in AppThemeVariant.values) {
        expect(find.byKey(AppThemeMenuButton.itemKey(variant)), findsOneWidget);
        expect(find.text('${variant.label}主题'), findsOneWidget);
      }
      final checks = find.descendant(
        of: find.byKey(AppThemeMenuButton.itemKey(AppThemeVariant.dark)),
        matching: find.byIcon(Icons.check_rounded),
      );
      expect(checks, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(AppThemeMenuButton.itemKey(AppThemeVariant.light)),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsNothing,
      );
    });

    testWidgets('picking a theme switches the app and saves it', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.tap(find.byKey(AppThemeMenuButton.buttonKey));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(AppThemeMenuButton.itemKey(AppThemeVariant.light)),
      );
      await tester.pumpAndSettle();

      expect(controller.variant, AppThemeVariant.light);
      expect(store.saved, AppThemeVariant.light);
      expect(AppColors.palette, same(AppPalette.light));
      // The menu closed and the button now shows the light theme.
      expect(
        find.byKey(AppThemeMenuButton.itemKey(AppThemeVariant.dark)),
        findsNothing,
      );
      expect(find.byIcon(AppThemeVariant.light.icon), findsOneWidget);
      expect(
        find.byTooltip(AppThemeMenuButton.tooltipFor(AppThemeVariant.light)),
        findsOneWidget,
      );
    });

    testWidgets('a second press closes the menu', (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.byKey(AppThemeMenuButton.buttonKey));
      await tester.pumpAndSettle();
      expect(
        find.byKey(AppThemeMenuButton.itemKey(AppThemeVariant.light)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(AppThemeMenuButton.buttonKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(AppThemeMenuButton.itemKey(AppThemeVariant.light)),
        findsNothing,
      );
      expect(controller.variant, AppThemeVariant.dark);
    });

    testWidgets('the wide form shows the theme name as a label', (
      tester,
    ) async {
      await tester.pumpWidget(host(extended: true));
      expect(find.text('外观 · 深色'), findsOneWidget);

      await controller.select(AppThemeVariant.light);
      await tester.pumpAndSettle();

      expect(find.text('外观 · 浅色'), findsOneWidget);
    });

    testWidgets('the narrow form has no visible label', (tester) async {
      await tester.pumpWidget(host());
      expect(find.textContaining('外观 ·'), findsNothing);
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('meets the minimum tap size', (tester) async {
      await tester.pumpWidget(host());
      final size = tester.getSize(find.byKey(AppThemeMenuButton.buttonKey));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('the desktop rail', () {
    Widget rail({required bool withAppearance}) {
      Widget app(AppThemeVariant variant) => MaterialApp(
        theme: AppTheme.themeFor(variant.palette),
        home: Scaffold(
          body: Row(
            children: [
              AppNavigationRail(
                selected: AppDestination.projects,
                onSelect: (_) {},
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
      if (!withAppearance) return app(AppThemeVariant.dark);
      return AppAppearanceHost(
        controller: controller,
        builder: (context, variant) => app(variant),
      );
    }

    testWidgets('has no theme button without an appearance controller', (
      tester,
    ) async {
      await pumpAt(
        tester,
        rail(withAppearance: false),
        const Size(1000, 800),
      );
      expect(find.byType(AppThemeMenuButton), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('puts the theme button below the destinations', (
      tester,
    ) async {
      await pumpAt(tester, rail(withAppearance: true), const Size(1000, 800));

      final button = find.byKey(AppThemeMenuButton.buttonKey);
      expect(button, findsOneWidget);
      final lastDestination = find.text(AppDestination.values.last.label);
      expect(
        tester.getTopLeft(button).dy,
        greaterThan(tester.getBottomLeft(lastDestination).dy),
      );
      // At the foot of the window, not right under the destinations.
      expect(tester.getBottomLeft(button).dy, greaterThan(800 - 80));
    });

    testWidgets('fits the collapsed rail', (tester) async {
      await pumpAt(tester, rail(withAppearance: true), const Size(1000, 800));

      final button = tester.getRect(find.byKey(AppThemeMenuButton.buttonKey));
      expect(button.right, lessThanOrEqualTo(AppNavigationRail.collapsedWidth));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the wide rail labels the theme button', (tester) async {
      await pumpAt(tester, rail(withAppearance: true), const Size(1400, 900));

      expect(find.text('外观 · 深色'), findsOneWidget);
      final button = tester.getRect(find.byKey(AppThemeMenuButton.buttonKey));
      expect(button.right, lessThanOrEqualTo(AppNavigationRail.extendedWidth));
    });

    testWidgets('switching from the rail repaints the rail itself', (
      tester,
    ) async {
      await pumpAt(tester, rail(withAppearance: true), const Size(1000, 800));
      Color railColor() {
        final material = tester.widget<Material>(
          find
              .ancestor(
                of: find.byType(NavigationRail),
                matching: find.byType(Material),
              )
              .first,
        );
        return material.color!;
      }

      expect(railColor(), AppPalette.dark.bgElevated);

      await tester.tap(find.byKey(AppThemeMenuButton.buttonKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(AppThemeMenuButton.itemKey(AppThemeVariant.light)),
      );
      await tester.pumpAndSettle();

      expect(controller.variant, AppThemeVariant.light);
      expect(railColor(), AppPalette.light.bgElevated);
    });
  });
}
