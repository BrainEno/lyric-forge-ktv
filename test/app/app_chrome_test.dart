import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/app/app_chrome.dart';
import 'package:lyric_forge_ktv/core/navigation/app_chrome_scope.dart';
import 'package:lyric_forge_ktv/core/navigation/app_navigation_shell.dart';
import 'package:lyric_forge_ktv/core/navigation/app_destinations.dart';
import 'package:lyric_forge_ktv/core/navigation/current_route_observer.dart';
import 'package:lyric_forge_ktv/core/navigation/destination_navigation.dart';
import 'package:lyric_forge_ktv/core/navigation/mobile_destinations.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';

/// A player bar stand-in: chrome that pushes a route and opens a dialog, the
/// two things the real bars could not do from outside the navigator.
class _FakeBar extends StatelessWidget {
  const _FakeBar();

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Row(
        children: [
          TextButton(
            onPressed: () =>
                AppChromeScope.pushNamed<void>(context, Routes.collections),
            child: const Text('去收藏'),
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: AppChromeScope.contextOf(context),
              builder: (_) => const AlertDialog(content: Text('对话框')),
            ),
            child: const Text('开对话框'),
          ),
        ],
      ),
    );
  }
}

/// The production arrangement: chrome built in `MaterialApp.builder`, beside
/// the navigator rather than under it.
Widget _app({required bool desktop}) {
  final navigatorKey = GlobalKey<NavigatorState>();
  final observer = CurrentRouteObserver();
  return MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: [observer],
    initialRoute: Routes.home,
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => Scaffold(body: Text('页面 ${settings.name}')),
    ),
    builder: (context, child) => AppChrome(
      desktop: desktop,
      navigatorKey: navigatorKey,
      currentRoute: observer.routeName,
      onSelectDestination: (destination) => goToDestination(
        navigatorKey.currentState!,
        destination,
        observer.routeName.value,
      ),
      onSelectMobileDestination: (destination) => goToMobileDestination(
        navigatorKey.currentState!,
        destination,
        observer.routeName.value,
      ),
      playerBar: const _FakeBar(),
      child: child!,
    ),
  );
}

Future<void> _pumpAt(WidgetTester tester, Widget app, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

int _index(AppDestination destination) =>
    AppDestination.values.indexOf(destination);

int _mobileIndex(MobileDestination destination) =>
    MobileDestination.values.indexOf(destination);

void main() {
  group('desktop chrome', () {
    const wide = Size(1400, 900);

    testWidgets('the rail follows the route after the first frame', (
      tester,
    ) async {
      await _pumpAt(tester, _app(desktop: true), wide);

      NavigationRail rail() =>
          tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail().selectedIndex, _index(AppDestination.projects));

      await tester.tap(find.text('音乐库').first);
      await tester.pumpAndSettle();

      expect(find.text('页面 ${Routes.library}'), findsOneWidget);
      expect(rail().selectedIndex, _index(AppDestination.library));

      await tester.tap(find.text('设置').first);
      await tester.pumpAndSettle();

      expect(rail().selectedIndex, _index(AppDestination.settings));
    });

    testWidgets('the player bar pushes routes from outside the navigator', (
      tester,
    ) async {
      await _pumpAt(tester, _app(desktop: true), wide);

      await tester.tap(find.text('去收藏'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('页面 ${Routes.collections}'), findsOneWidget);
    });

    testWidgets('the player bar opens dialogs', (tester) async {
      await _pumpAt(tester, _app(desktop: true), wide);

      await tester.tap(find.text('开对话框'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('对话框'), findsOneWidget);
    });

    testWidgets('the player bar steps aside on the full player', (
      tester,
    ) async {
      await _pumpAt(tester, _app(desktop: true), wide);
      expect(find.byType(_FakeBar), findsOneWidget);

      final context = tester.element(find.byType(Navigator).last);
      Navigator.of(context).pushNamed(Routes.nowPlaying);
      await tester.pumpAndSettle();

      expect(find.byType(_FakeBar), findsNothing);
    });
  });

  group('mobile chrome', () {
    const phone = Size(390, 844);

    testWidgets('the bottom navigation follows the route', (tester) async {
      await _pumpAt(tester, _app(desktop: false), phone);

      NavigationBar bar() =>
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar().selectedIndex, _mobileIndex(MobileDestination.listen));

      await tester.tap(find.text('歌词'));
      await tester.pumpAndSettle();

      expect(find.text('页面 ${Routes.review}'), findsOneWidget);
      expect(bar().selectedIndex, _mobileIndex(MobileDestination.lyrics));

      await tester.tap(find.text('听歌'));
      await tester.pumpAndSettle();

      expect(find.text('页面 ${Routes.home}'), findsOneWidget);
      expect(bar().selectedIndex, _mobileIndex(MobileDestination.listen));
    });

    testWidgets('the phone bar is listen, library, lyrics and settings', (
      tester,
    ) async {
      await _pumpAt(tester, _app(desktop: false), phone);

      final labels = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((destination) => destination.label);
      expect(labels, ['听歌', '音乐库', '歌词', '设置']);
      // The desktop's 工程 and 校对 are folded into 歌词.
      expect(find.text('工程'), findsNothing);
      expect(find.text('校对'), findsNothing);
    });

    testWidgets('the mini player steps aside on the listening home', (
      tester,
    ) async {
      await _pumpAt(tester, _app(desktop: false), phone);
      expect(find.byType(_FakeBar), findsNothing);

      await tester.tap(find.text('音乐库'));
      await tester.pumpAndSettle();
      expect(find.byType(_FakeBar), findsOneWidget);

      await tester.tap(find.text('听歌'));
      await tester.pumpAndSettle();
      expect(find.byType(_FakeBar), findsNothing);
    });

    testWidgets('only the tab bar pads for the iPhone home indicator', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPadding);
      await _pumpAt(tester, _app(desktop: false), phone);
      await tester.tap(find.text('音乐库'));
      await tester.pumpAndSettle();

      EdgeInsets paddingOf(Finder finder) =>
          MediaQuery.paddingOf(tester.element(finder));
      // The page and the mini player sit above the tab bar: padding for the
      // home indicator there left an empty band and cut the page off.
      final page = paddingOf(find.text('页面 ${Routes.library}'));
      expect(page.bottom, 0);
      expect(page.top, 47);
      expect(paddingOf(find.text('去收藏')).bottom, 0);
      expect(
        paddingOf(find.byKey(const ValueKey('app-bottom-navigation'))).bottom,
        34,
      );
    });

    testWidgets('the tab bar is 64 high plus the home indicator, no more', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPadding);
      await _pumpAt(tester, _app(desktop: false), phone);
      await tester.tap(find.text('音乐库'));
      await tester.pumpAndSettle();

      final bar = find.byKey(const ValueKey('app-bottom-navigation'));
      final padding = MediaQuery.paddingOf(tester.element(bar));
      // The status bar used to reach the bar and grow it by 47 (D-058).
      expect(padding.top, 0);
      expect(MediaQuery.paddingOf(tester.element(find.text('去收藏'))).top, 0);
      expect(
        tester.getSize(bar).height,
        AppMobileBottomNavigation.barHeight + padding.bottom,
      );
    });

    testWidgets('the mini player pushes routes too', (tester) async {
      await _pumpAt(tester, _app(desktop: false), phone);
      await tester.tap(find.text('音乐库'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('去收藏'));
      await tester.pumpAndSettle();

      expect(find.text('页面 ${Routes.collections}'), findsOneWidget);
    });

    testWidgets('pressing the current destination keeps the page', (
      tester,
    ) async {
      await _pumpAt(tester, _app(desktop: false), phone);
      await tester.tap(find.text('音乐库'));
      await tester.pumpAndSettle();
      final page = tester.element(find.text('页面 ${Routes.library}'));

      await tester.tap(find.text('音乐库'));
      await tester.pumpAndSettle();

      // Same element: the page was not pushed again.
      expect(tester.element(find.text('页面 ${Routes.library}')), same(page));
    });

    testWidgets('the bottom bar has an overlay for its tooltips', (
      tester,
    ) async {
      await _pumpAt(tester, _app(desktop: false), phone);

      // The navigator's own overlay is beside the bar, not above it.
      final host = find.ancestor(
        of: find.byType(NavigationBar),
        matching: find.byType(Overlay),
      );
      expect(host, findsOneWidget);
    });

    testWidgets('long-pressing a destination shows its tooltip', (
      tester,
    ) async {
      await _pumpAt(tester, _app(desktop: false), phone);

      await tester.longPress(find.text('歌词'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(MobileDestination.lyrics.description), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });
  });

  group('AppChromeScope outside the app shell', () {
    testWidgets('falls back to the nearest navigator', (tester) async {
      late BuildContext inner;
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (context) {
              inner = context;
              return Text('页面 ${settings.name}');
            },
          ),
        ),
      );

      expect(AppChromeScope.navigatorOf(inner), isNotNull);
      expect(AppChromeScope.contextOf(inner), same(inner));
      expect(AppChromeScope.routeOf(inner), isNull);
    });
  });
}
