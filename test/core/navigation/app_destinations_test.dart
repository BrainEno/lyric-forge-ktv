import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/core/navigation/app_destinations.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';

void main() {
  group('destinationForRoute', () {
    test('project work maps to 工程', () {
      expect(destinationForRoute(Routes.home), AppDestination.projects);
      expect(destinationForRoute(Routes.dashboard), AppDestination.projects);
      expect(destinationForRoute(Routes.import), AppDestination.projects);
      expect(destinationForRoute('/project/abc'), AppDestination.projects);
      expect(
        destinationForRoute('/project/abc/player'),
        AppDestination.projects,
      );
    });

    test('the lyric editor maps to 校对, not 工程', () {
      // Proofreading is where the user is working; the rail should say so.
      expect(destinationForRoute('/project/abc/lyrics'), AppDestination.review);
      expect(destinationForRoute(Routes.review), AppDestination.review);
    });

    test('every library sub-route maps to 音乐库', () {
      expect(destinationForRoute(Routes.library), AppDestination.library);
      expect(
        destinationForRoute(Routes.libraryArtists),
        AppDestination.library,
      );
      expect(destinationForRoute(Routes.collections), AppDestination.library);
      expect(destinationForRoute(Routes.playlists), AppDestination.library);
      expect(destinationForRoute(Routes.quickPlay), AppDestination.library);
      expect(destinationForRoute(Routes.nowPlaying), AppDestination.library);
    });

    test('settings maps to 设置', () {
      expect(destinationForRoute(Routes.settings), AppDestination.settings);
    });

    test('device transfer belongs to no destination', () {
      // Those screens hide the navigation, so an unselected rail is never shown.
      expect(destinationForRoute(Routes.mediaSharing), isNull);
      expect(destinationForRoute(Routes.remoteLibrary), isNull);
      expect(destinationForRoute(Routes.mediaHubScanner), isNull);
    });

    test('unknown and empty routes select nothing', () {
      expect(destinationForRoute(null), isNull);
      expect(destinationForRoute(''), isNull);
      expect(destinationForRoute('/no-such-place'), isNull);
    });
  });

  test('every destination has a distinct route, label and icon', () {
    expect(
      AppDestination.values.map((d) => d.route).toSet(),
      hasLength(AppDestination.values.length),
    );
    expect(
      AppDestination.values.map((d) => d.label).toSet(),
      hasLength(AppDestination.values.length),
    );
    for (final destination in AppDestination.values) {
      expect(destination.description, isNotEmpty);
      expect(destination.icon, isNot(destination.selectedIcon));
      // The mapping is symmetric: each destination's own route selects it.
      expect(destinationForRoute(destination.route), destination);
    }
  });
}
