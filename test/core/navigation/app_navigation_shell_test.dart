import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/core/navigation/app_destinations.dart';
import 'package:lyric_forge_ktv/core/navigation/app_navigation_shell.dart';
import 'package:lyric_forge_ktv/core/navigation/mobile_destinations.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_brand_mark.dart';
import 'package:lyric_forge_ktv/core/widgets/app_tap_pulse.dart';

double scaleOf(WidgetTester tester, IconData icon) {
  final pulses = find.ancestor(
    of: find.byIcon(icon),
    matching: find.byType(AppTapPulse),
  );
  final transforms = find.descendant(
    of: pulses.first,
    matching: find.byType(Transform),
  );
  final transform = tester.widget<Transform>(transforms.first);
  return transform.transform.getMaxScaleOnAxis();
}

void main() {
  late List<AppDestination> selected;

  setUp(() => selected = <AppDestination>[]);

  Widget buildShell({String? route = Routes.home, bool hidden = false}) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: AppNavigationShell(
        currentRoute: route,
        hidden: hidden,
        onSelect: selected.add,
        child: const Scaffold(body: Center(child: Text('内容'))),
      ),
    );
  }

  Future<void> pumpAt(WidgetTester tester, Widget widget, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  testWidgets('宽屏用侧边栏，四个去向都在', (tester) async {
    await pumpAt(tester, buildShell(), const Size(1400, 900));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    for (final destination in AppDestination.values) {
      expect(find.text(destination.label), findsWidgets);
    }
    expect(find.text('内容'), findsOneWidget);
  });

  testWidgets('侧边栏顶部是应用图标的品牌标记', (tester) async {
    await pumpAt(tester, buildShell(), const Size(1400, 900));

    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byType(AppBrandMark),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
    expect(find.byTooltip('Elysium Player'), findsOneWidget);
  });

  for (final width in [1400.0, 1000.0]) {
    final mode = width >= 1200 ? '展开' : '收起';
    testWidgets('$mode的侧边栏里品牌标记和导航图标在同一列', (tester) async {
      await pumpAt(tester, buildShell(), Size(width, 900));

      final mark = tester.getCenter(find.byType(AppBrandMark));
      // Routes.home selects 工程; 设置 shows its unselected icon.
      final icon = tester.getCenter(
        find.byIcon(AppDestination.settings.icon),
      );
      expect(mark.dx, moreOrLessEquals(icon.dx, epsilon: 0.5));
      expect(
        mark.dx,
        moreOrLessEquals(AppNavigationRail.collapsedWidth / 2, epsilon: 0.5),
      );
      // Above the destinations, not beside them.
      expect(
        tester.getBottomLeft(find.byType(AppBrandMark)).dy,
        lessThan(
          tester
              .getTopLeft(find.byIcon(AppDestination.projects.selectedIcon))
              .dy,
        ),
      );
    });
  }

  testWidgets('侧边栏品牌标记只在有侧边栏的窗口里算可见', (tester) async {
    final answers = <bool>[];
    Widget probe() => MaterialApp(
      home: Builder(
        builder: (context) {
          answers.add(AppNavigationRailBrand.visibleIn(context));
          return const SizedBox();
        },
      ),
    );
    await pumpAt(tester, probe(), const Size(1400, 900));
    await pumpAt(tester, probe(), const Size(390, 844));
    expect(answers.first, isTrue);
    expect(answers.last, isFalse);
  });

  testWidgets('窄屏底部导航不带品牌标记', (tester) async {
    await pumpAt(tester, buildShell(), const Size(390, 844));

    expect(find.byType(AppBrandMark), findsNothing);
  });

  testWidgets('窄屏用底部导航，四个去向都在', (tester) async {
    await pumpAt(tester, buildShell(), const Size(390, 844));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    for (final destination in AppDestination.values) {
      expect(find.text(destination.label), findsWidgets);
    }
  });

  testWidgets('点击底部导航回到主线', (tester) async {
    await pumpAt(tester, buildShell(), const Size(390, 844));

    await tester.tap(find.text('校对'));
    await tester.pumpAndSettle();

    expect(selected, [AppDestination.review]);
  });

  testWidgets('当前路由决定高亮项', (tester) async {
    await pumpAt(
      tester,
      buildShell(route: '/project/abc/lyrics'),
      const Size(390, 844),
    );

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      bar.selectedIndex,
      AppDestination.values.indexOf(AppDestination.review),
    );
  });

  testWidgets('隐藏时不渲染任何导航', (tester) async {
    await pumpAt(tester, buildShell(hidden: true), const Size(1400, 900));

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('内容'), findsOneWidget);
  });

  testWidgets('不属于四个去向的页面不显示导航', (tester) async {
    // Device transfer is something you do from inside the library, not a place
    // you live; a rail with nothing highlighted would only add noise.
    await pumpAt(
      tester,
      buildShell(route: Routes.mediaSharing),
      const Size(1400, 900),
    );

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('内容'), findsOneWidget);
  });

  group('press feedback', () {
    testWidgets('pressing the open destination pulses its icon', (
      tester,
    ) async {
      await pumpAt(
        tester,
        buildShell(route: Routes.library),
        const Size(390, 844),
      );
      const icon = Icons.library_music_rounded;
      expect(scaleOf(tester, icon), 1);

      await tester.tap(find.text('音乐库'));
      // The press rebuilds on this frame; the pulse starts ticking after it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(selected, [AppDestination.library]);
      expect(scaleOf(tester, icon), greaterThan(1.05));
      await tester.pumpAndSettle();
      expect(scaleOf(tester, icon), closeTo(1, 1e-9));
    });

    testWidgets('the rail pulses too', (tester) async {
      await pumpAt(
        tester,
        buildShell(route: Routes.settings),
        const Size(1400, 900),
      );

      await tester.tap(find.byIcon(Icons.settings_rounded));
      // The press rebuilds on this frame; the pulse starts ticking after it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(selected, [AppDestination.settings]);
      expect(scaleOf(tester, Icons.settings_rounded), greaterThan(1.05));
      await tester.pumpAndSettle();
    });

    testWidgets('every press gives a selection click', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpAt(tester, buildShell(), const Size(390, 844));

      await tester.tap(find.text('校对'));
      await tester.pumpAndSettle();

      expect(
        calls.where(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        isNotEmpty,
      );
    });
  });

  group('themed navigation', () {
    Color? colourOf(WidgetTester tester, Finder finder) {
      final texts = find.descendant(
        of: finder,
        matching: find.byType(RichText),
      );
      return tester.widget<RichText>(texts.first).text.style?.color;
    }

    testWidgets('the bottom bar marks its destination in lavender', (
      tester,
    ) async {
      await pumpAt(
        tester,
        buildShell(route: Routes.review),
        const Size(390, 844),
      );

      final theme = AppTheme.darkTheme.navigationBarTheme;
      expect(theme.indicatorColor, AppColors.accentContainer);
      expect(
        colourOf(tester, find.byIcon(AppDestination.review.selectedIcon)),
        AppColors.onAccentContainer,
      );
      expect(
        colourOf(tester, find.byIcon(AppDestination.library.icon)),
        AppColors.textSecondary,
      );
    });

    testWidgets('the chosen label is bold and white', (tester) async {
      await pumpAt(
        tester,
        buildShell(route: Routes.review),
        const Size(390, 844),
      );

      TextStyle? styleOf(String label) {
        final labels = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is RichText && widget.text.toPlainText() == label,
          ),
        );
        return tester.widget<RichText>(labels.first).text.style;
      }

      expect(styleOf('校对')?.fontWeight, FontWeight.w700);
      expect(styleOf('校对')?.color, AppColors.textPrimary);
      expect(styleOf('音乐库')?.fontWeight, FontWeight.w500);
      expect(styleOf('音乐库')?.color, AppColors.textSecondary);
    });

    testWidgets('the rail uses the same indicator', (tester) async {
      await pumpAt(
        tester,
        buildShell(route: Routes.settings),
        const Size(1000, 900),
      );

      final theme = AppTheme.darkTheme.navigationRailTheme;
      expect(theme.indicatorColor, AppColors.accentContainer);
      expect(theme.useIndicator, isTrue);
      expect(
        colourOf(tester, find.byIcon(AppDestination.settings.selectedIcon)),
        AppColors.onAccentContainer,
      );
    });
  });

  group('AppMobileBottomNavigation', () {
    late List<MobileDestination> chosen;

    setUp(() => chosen = <MobileDestination>[]);

    Widget phoneBar(MobileDestination selected) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        bottomNavigationBar: AppMobileBottomNavigation(
          selected: selected,
          onSelect: chosen.add,
        ),
      ),
    );

    testWidgets('shows the four phone places, listening first', (tester) async {
      await pumpAt(
        tester,
        phoneBar(MobileDestination.listen),
        const Size(390, 844),
      );

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 0);
      for (final destination in MobileDestination.values) {
        expect(find.text(destination.label), findsOneWidget);
      }
      expect(find.byIcon(MobileDestination.listen.selectedIcon), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a press reports its destination', (tester) async {
      await pumpAt(
        tester,
        phoneBar(MobileDestination.listen),
        const Size(390, 844),
      );

      await tester.tap(find.text('歌词'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      expect(chosen, [MobileDestination.lyrics, MobileDestination.settings]);
    });

    testWidgets('pressing the open place pulses it like the desktop bar', (
      tester,
    ) async {
      await pumpAt(
        tester,
        phoneBar(MobileDestination.library),
        const Size(390, 844),
      );
      const icon = Icons.library_music_rounded;

      await tester.tap(find.text('音乐库'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(chosen, [MobileDestination.library]);
      expect(scaleOf(tester, icon), greaterThan(1.05));
      await tester.pumpAndSettle();
      expect(scaleOf(tester, icon), closeTo(1, 1e-9));
    });

    testWidgets('fits a 320-wide phone', (tester) async {
      await pumpAt(
        tester,
        phoneBar(MobileDestination.settings),
        const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
