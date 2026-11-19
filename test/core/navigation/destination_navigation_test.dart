import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/app_destinations.dart';
import 'package:lyric_forge_ktv/core/navigation/destination_navigation.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';

void main() {
  group('planDestinationTap', () {
    test('the first page of a destination stays put', () {
      expect(
        planDestinationTap(AppDestination.projects, Routes.home),
        DestinationTap.stay,
      );
      expect(
        planDestinationTap(AppDestination.projects, Routes.dashboard),
        DestinationTap.stay,
      );
      expect(
        planDestinationTap(AppDestination.library, Routes.library),
        DestinationTap.stay,
      );
      expect(
        planDestinationTap(AppDestination.review, Routes.review),
        DestinationTap.stay,
      );
      expect(
        planDestinationTap(AppDestination.settings, '${Routes.settings}?a=1'),
        DestinationTap.stay,
      );
    });

    test('a deeper page of the same destination goes back to its start', () {
      expect(
        planDestinationTap(AppDestination.library, Routes.collections),
        DestinationTap.open,
      );
      expect(
        planDestinationTap(AppDestination.library, Routes.libraryAlbums),
        DestinationTap.open,
      );
      expect(
        planDestinationTap(AppDestination.projects, '/project/abc'),
        DestinationTap.open,
      );
    });

    test('another destination, or an unknown route, opens', () {
      expect(
        planDestinationTap(AppDestination.review, Routes.library),
        DestinationTap.open,
      );
      expect(
        planDestinationTap(AppDestination.library, null),
        DestinationTap.open,
      );
      expect(
        planDestinationTap(AppDestination.library, ''),
        DestinationTap.open,
      );
    });
  });

  group('goToDestination', () {
    late GlobalKey<NavigatorState> navigatorKey;
    late List<String?> built;

    Future<void> pumpApp(WidgetTester tester) async {
      navigatorKey = GlobalKey<NavigatorState>();
      built = [];
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) {
              built.add(settings.name);
              return Text('页面 ${settings.name}');
            },
          ),
        ),
      );
    }

    testWidgets('pushes other destinations on top of the root', (tester) async {
      await pumpApp(tester);

      final result = goToDestination(
        navigatorKey.currentState!,
        AppDestination.review,
        Routes.home,
      );
      await tester.pumpAndSettle();

      expect(result, DestinationTap.open);
      expect(find.text('页面 ${Routes.review}'), findsOneWidget);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('页面 ${Routes.home}'), findsOneWidget);
    });

    testWidgets('does nothing on the page already open', (tester) async {
      await pumpApp(tester);
      goToDestination(
        navigatorKey.currentState!,
        AppDestination.library,
        Routes.home,
      );
      await tester.pumpAndSettle();
      final before = built.length;

      final result = goToDestination(
        navigatorKey.currentState!,
        AppDestination.library,
        Routes.library,
      );
      await tester.pumpAndSettle();

      expect(result, DestinationTap.stay);
      expect(built.length, before);
      expect(navigatorKey.currentState!.canPop(), isTrue);
    });

    testWidgets('工程 pops back to the root', (tester) async {
      await pumpApp(tester);
      navigatorKey.currentState!.pushNamed('/project/abc');
      await tester.pumpAndSettle();

      final result = goToDestination(
        navigatorKey.currentState!,
        AppDestination.projects,
        '/project/abc',
      );
      await tester.pumpAndSettle();

      expect(result, DestinationTap.open);
      expect(find.text('页面 ${Routes.home}'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isFalse);
    });
  });
}
