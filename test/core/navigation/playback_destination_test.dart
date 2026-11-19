import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/playback_destination.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';

void main() {
  group('PlaybackDestination.resolve', () {
    test('nothing playing opens the library', () {
      expect(
        PlaybackDestination.resolve(hasCurrent: false),
        PlaybackDestination.library,
      );
    });

    test('a local song opens the local player', () {
      expect(
        PlaybackDestination.resolve(hasCurrent: true),
        PlaybackDestination.localPlayer,
      );
    });

    test('a project song opens its project player', () {
      expect(
        PlaybackDestination.resolve(hasCurrent: true, projectId: 'p1'),
        PlaybackDestination.projectPlayer,
      );
    });

    test('a remote stream opens the now playing view', () {
      expect(
        PlaybackDestination.resolve(hasCurrent: true, isRemoteStream: true),
        PlaybackDestination.nowPlaying,
      );
    });

    test('a project wins over the stream flag', () {
      expect(
        PlaybackDestination.resolve(
          hasCurrent: true,
          projectId: 'p1',
          isRemoteStream: true,
        ),
        PlaybackDestination.projectPlayer,
      );
    });

    test('resuming a history entry always opens the local player', () {
      for (final hasCurrent in [false, true]) {
        expect(
          PlaybackDestination.resolve(
            hasCurrent: hasCurrent,
            projectId: hasCurrent ? 'p1' : null,
            isRemoteStream: hasCurrent,
            resumingHistory: true,
          ),
          PlaybackDestination.localPlayer,
        );
      }
    });
  });

  group('PlaybackDestination.routeName', () {
    test('each destination has its own route', () {
      expect(
        PlaybackDestination.projectPlayer.routeName(projectId: 'p1'),
        Routes.playerPath('p1'),
      );
      expect(PlaybackDestination.nowPlaying.routeName(), Routes.nowPlaying);
      expect(PlaybackDestination.localPlayer.routeName(), Routes.quickPlay);
      expect(PlaybackDestination.library.routeName(), Routes.library);
    });

    test('a project player without an id falls back to the local player', () {
      expect(PlaybackDestination.projectPlayer.routeName(), Routes.quickPlay);
    });

    test('only the local player route is the old catch-all', () {
      final routes = {
        for (final destination in PlaybackDestination.values)
          destination: destination.routeName(projectId: 'p1'),
      };
      expect(
        routes.values.toSet(),
        hasLength(PlaybackDestination.values.length),
      );
      final catchAll = [
        for (final entry in routes.entries)
          if (entry.value == Routes.quickPlay) entry.key,
      ];
      expect(catchAll, [PlaybackDestination.localPlayer]);
    });
  });
}
