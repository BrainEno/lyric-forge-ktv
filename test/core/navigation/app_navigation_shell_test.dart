import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/core/navigation/app_destinations.dart';
import 'package:lyric_forge_ktv/core/navigation/app_navigation_shell.dart';
import 'package:lyric_forge_ktv/core/navigation/app_router.dart';

void main() {
  late List<AppDestination> selected;

  setUp(() => selected = <AppDestination>[]);

  Widget buildShell({String? route = Routes.home, bool hidden = false}) {
    return MaterialApp(
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

  testWidgets('设备互传页面不高亮任何一项', (tester) async {
    await pumpAt(
      tester,
      buildShell(route: Routes.mediaSharing),
      const Size(1400, 900),
    );

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, isNull);
  });
}
