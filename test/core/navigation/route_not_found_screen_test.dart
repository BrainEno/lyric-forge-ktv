import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/app/app_router.dart';
import 'package:lyric_forge_ktv/app/app_services.dart';
import 'package:lyric_forge_ktv/core/navigation/route_not_found_screen.dart';

/// A start page that pushes [route] through the production routing table.
///
/// Unknown routes never touch the services, so the uninitialised registry is
/// enough here.
Widget _appPushing(String route) {
  final router = AppRouter(AppServices.instance);
  return MaterialApp(
    onGenerateRoute: router.onGenerateRoute,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).pushNamed(route),
          child: const Text('打开'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('an unknown route opens the not-found page, not the dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(_appPushing('/no-such-page'));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(RouteNotFoundScreen), findsOneWidget);
    expect(find.text('找不到这个页面'), findsOneWidget);
    expect(find.textContaining('/no-such-page'), findsOneWidget);
  });

  testWidgets('an unknown project page is not found either', (tester) async {
    await tester.pumpWidget(_appPushing('/project/abc/karaoke'));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final screen = tester.widget<RouteNotFoundScreen>(
      find.byType(RouteNotFoundScreen),
    );
    expect(screen.routeName, '/project/abc/karaoke');
  });

  testWidgets('back returns to the previous page', (tester) async {
    await tester.pumpWidget(_appPushing('/old-link'));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('返回上一页'));
    await tester.pumpAndSettle();
    expect(find.byType(RouteNotFoundScreen), findsNothing);
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets('home clears the stack and opens the start page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/': (context) => const Text('首页')},
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => const RouteNotFoundScreen(routeName: '/x'),
        ),
        initialRoute: '/x',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('返回上一页'), findsOneWidget);

    await tester.tap(find.text('回到首页'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(find.byType(RouteNotFoundScreen), findsNothing);
  });
}
