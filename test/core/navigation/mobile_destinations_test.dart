import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/destination_navigation.dart';
import 'package:lyric_forge_ktv/core/navigation/mobile_destinations.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';

void main() {
  group('mobileDestinationForRoute', () {
    test('the root route is the listening home', () {
      expect(mobileDestinationForRoute(Routes.home), MobileDestination.listen);
      expect(
        mobileDestinationForRoute('${Routes.home}?from=launch'),
        MobileDestination.listen,
      );
    });

    test('project work and proofreading are both 歌词', () {
      for (final route in [
        Routes.dashboard,
        Routes.import,
        Routes.review,
        '/project/abc',
        '/project/abc/lyrics',
        '/project/abc/player',
      ]) {
        expect(
          mobileDestinationForRoute(route),
          MobileDestination.lyrics,
          reason: route,
        );
      }
    });

    test('every library route is 音乐库', () {
      for (final route in [
        Routes.library,
        Routes.libraryArtists,
        Routes.libraryAlbums,
        Routes.libraryAutoPaired,
        Routes.collections,
        Routes.playlists,
        Routes.quickPlay,
      ]) {
        expect(
          mobileDestinationForRoute(route),
          MobileDestination.library,
          reason: route,
        );
      }
    });

    test('settings is 设置', () {
      expect(
        mobileDestinationForRoute(Routes.settings),
        MobileDestination.settings,
      );
    });

    test('transfer, unknown and empty routes select nothing', () {
      expect(mobileDestinationForRoute(Routes.mediaSharing), isNull);
      expect(mobileDestinationForRoute(Routes.remoteLibrary), isNull);
      expect(mobileDestinationForRoute(Routes.mediaHubScanner), isNull);
      expect(mobileDestinationForRoute('/no-such-place'), isNull);
      expect(mobileDestinationForRoute(''), isNull);
      expect(mobileDestinationForRoute(null), isNull);
    });
  });

  test('listening comes first and every destination is distinct', () {
    expect(MobileDestination.values.first, MobileDestination.listen);
    expect(MobileDestination.values.map((d) => d.label), [
      '听歌',
      '音乐库',
      '歌词',
      '设置',
    ]);
    expect(
      MobileDestination.values.map((d) => d.route).toSet(),
      hasLength(MobileDestination.values.length),
    );
    for (final destination in MobileDestination.values) {
      expect(destination.description, isNotEmpty);
      expect(destination.icon, isNot(destination.selectedIcon));
      // Symmetric: each destination's own route selects it.
      expect(mobileDestinationForRoute(destination.route), destination);
    }
  });

  group('planMobileDestinationTap', () {
    test('the first page of a destination stays put', () {
      for (final destination in MobileDestination.values) {
        expect(
          planMobileDestinationTap(destination, destination.route),
          DestinationTap.stay,
          reason: destination.label,
        );
      }
    });

    test('a deeper page of the same destination goes back to its start', () {
      expect(
        planMobileDestinationTap(
          MobileDestination.library,
          Routes.libraryAlbums,
        ),
        DestinationTap.open,
      );
      expect(
        planMobileDestinationTap(MobileDestination.lyrics, Routes.dashboard),
        DestinationTap.open,
      );
    });

    test('another destination, or no route, opens', () {
      expect(
        planMobileDestinationTap(MobileDestination.listen, Routes.library),
        DestinationTap.open,
      );
      expect(
        planMobileDestinationTap(MobileDestination.settings, null),
        DestinationTap.open,
      );
      expect(
        planMobileDestinationTap(MobileDestination.settings, ''),
        DestinationTap.open,
      );
    });
  });

  group('goToMobileDestination', () {
    late GlobalKey<NavigatorState> navigatorKey;
    late List<String> opened;

    Widget app() => MaterialApp(
      navigatorKey: navigatorKey,
      initialRoute: Routes.home,
      onGenerateRoute: (settings) {
        opened.add(settings.name ?? '');
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('页面 ${settings.name}')),
        );
      },
    );

    setUp(() {
      navigatorKey = GlobalKey<NavigatorState>();
      opened = [];
    });

    testWidgets('pushes other destinations on top of listening', (
      tester,
    ) async {
      await tester.pumpWidget(app());

      final plan = goToMobileDestination(
        navigatorKey.currentState!,
        MobileDestination.lyrics,
        Routes.home,
      );
      await tester.pumpAndSettle();

      expect(plan, DestinationTap.open);
      expect(find.text('页面 ${Routes.review}'), findsOneWidget);
      // One back press returns to listening rather than leaving the app.
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('页面 ${Routes.home}'), findsOneWidget);
    });

    testWidgets('replaces one destination with another', (tester) async {
      await tester.pumpWidget(app());
      final navigator = navigatorKey.currentState!;

      goToMobileDestination(navigator, MobileDestination.library, Routes.home);
      await tester.pumpAndSettle();
      goToMobileDestination(
        navigator,
        MobileDestination.settings,
        Routes.library,
      );
      await tester.pumpAndSettle();

      navigator.pop();
      await tester.pumpAndSettle();
      // The library was removed, not stacked under settings.
      expect(find.text('页面 ${Routes.home}'), findsOneWidget);
    });

    testWidgets('听歌 pops back to the root', (tester) async {
      await tester.pumpWidget(app());
      final navigator = navigatorKey.currentState!;
      goToMobileDestination(navigator, MobileDestination.library, Routes.home);
      await tester.pumpAndSettle();
      opened.clear();

      final plan = goToMobileDestination(
        navigator,
        MobileDestination.listen,
        Routes.library,
      );
      await tester.pumpAndSettle();

      expect(plan, DestinationTap.open);
      expect(find.text('页面 ${Routes.home}'), findsOneWidget);
      expect(opened, isEmpty, reason: 'no second copy of the home');
    });

    testWidgets('does nothing on the page already open', (tester) async {
      await tester.pumpWidget(app());
      opened.clear();

      final plan = goToMobileDestination(
        navigatorKey.currentState!,
        MobileDestination.listen,
        Routes.home,
      );
      await tester.pumpAndSettle();

      expect(plan, DestinationTap.stay);
      expect(opened, isEmpty);
    });
  });
}
