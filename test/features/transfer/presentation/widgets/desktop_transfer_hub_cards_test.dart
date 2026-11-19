import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/app_empty_state.dart';
import 'package:lyric_forge_ktv/core/widgets/app_loading_state.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_session.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/shared_audio_track.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/widgets/desktop_transfer_hub_cards.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/widgets/desktop_transfer_hub_text.dart';

// The cards of the desktop transfer page and their sentences, on their own.

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

ButtonStyleButton _buttonWidget(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(_button(label));

const _track = SharedAudioTrack(
  id: 't1',
  title: '夜曲',
  artist: '  周杰伦 ',
  localPath: '/music/夜曲.flac',
  format: 'flac',
  byteLength: 25 * 1024 * 1024,
);

void main() {
  group('DesktopTransferHubText', () {
    test('file sizes read naturally at every scale', () {
      expect(DesktopTransferHubText.fileSize(0), '0 B');
      expect(DesktopTransferHubText.fileSize(512), '512 B');
      expect(DesktopTransferHubText.fileSize(2048), '2 KB');
      expect(DesktopTransferHubText.fileSize(3 * 1024 * 1024), '3.0 MB');
    });

    test('networks have names instead of enum values', () {
      expect(
        DesktopTransferHubText.endpointKind(MediaHubEndpointKind.lan),
        '局域网',
      );
      expect(
        DesktopTransferHubText.endpointKind(MediaHubEndpointKind.tailscale),
        'Tailscale（可远程连接）',
      );
      expect(
        DesktopTransferHubText.endpointKind(MediaHubEndpointKind.other),
        '其他网络',
      );
      expect(
        DesktopTransferHubText.endpoint(
          const MediaHubEndpoint(
            host: '10.0.0.2',
            port: 8443,
            kind: MediaHubEndpointKind.lan,
          ),
        ),
        '局域网：10.0.0.2:8443',
      );
    });

    test('the overview line follows the service', () {
      expect(
        DesktopTransferHubText.overviewStatus(
          initializing: true,
          running: true,
          trackCount: 3,
        ),
        DesktopTransferHubText.libraryLoading,
      );
      expect(
        DesktopTransferHubText.overviewStatus(
          initializing: false,
          running: false,
          trackCount: 3,
        ),
        DesktopTransferHubText.stoppedStatus,
      );
      expect(
        DesktopTransferHubText.overviewStatus(
          initializing: false,
          running: true,
          trackCount: 3,
        ),
        contains('3 首'),
      );
      // Running with nothing to share says what a phone can still do.
      expect(
        DesktopTransferHubText.overviewStatus(
          initializing: false,
          running: true,
          trackCount: 0,
        ),
        contains('向电脑发送音乐'),
      );
    });

    test('every sentence says 音乐库, never Library', () {
      final sentences = [
        DesktopTransferHubText.stoppedStatus,
        DesktopTransferHubText.toPhoneRunning(3),
        DesktopTransferHubText.toComputerRunning,
        DesktopTransferHubText.toPhoneStopped,
        DesktopTransferHubText.tracksCaption,
        DesktopTransferHubText.tracksEmptyTitle,
        DesktopTransferHubText.tracksEmptyMessage,
        DesktopTransferHubText.refreshedRunning,
        DesktopTransferHubText.refreshedStopped,
        DesktopTransferHubText.readFailed('x'),
      ];
      for (final sentence in sentences) {
        expect(sentence, isNot(contains('Library')), reason: sentence);
      }
      // The incoming folder is a real directory name and stays as a path.
      expect(
        DesktopTransferHubText.toComputerRunning,
        contains(DesktopTransferHubText.incomingFolder),
      );
    });

    test('a previewed song lists artist, format and size', () {
      expect(
        DesktopHubSharedTracksCard.trackDetails(_track),
        '周杰伦 · FLAC · 25.0 MB',
      );
      const noArtist = SharedAudioTrack(
        id: 't2',
        title: '无名',
        artist: ' ',
        localPath: '/music/无名.mp3',
        format: 'mp3',
        byteLength: 900,
      );
      expect(DesktopHubSharedTracksCard.trackDetails(noArtist), 'MP3 · 900 B');
    });
  });

  group('DesktopHubWaitingCard', () {
    testWidgets('says what is loading instead of a bare spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const DesktopHubWaitingCard(
            loadingMessage: DesktopTransferHubText.serviceStarting,
            onStart: null,
          ),
        ),
      );

      expect(
        find.widgetWithText(
          AppInlineLoading,
          DesktopTransferHubText.serviceStarting,
        ),
        findsOneWidget,
      );
      expect(find.text(DesktopTransferHubText.startAndPair), findsNothing);
    });

    testWidgets('offers to start when the service is off', (tester) async {
      var starts = 0;
      await tester.pumpWidget(
        _host(
          DesktopHubWaitingCard(loadingMessage: null, onStart: () => starts++),
        ),
      );

      expect(find.byType(AppInlineLoading), findsNothing);
      expect(find.text(DesktopTransferHubText.waitingMessage), findsOneWidget);
      await tester.tap(_button(DesktopTransferHubText.startAndPair));
      expect(starts, 1);
    });

    testWidgets('the start button waits while another step runs', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const DesktopHubWaitingCard(loadingMessage: null, onStart: null)),
      );

      final start = _buttonWidget(tester, DesktopTransferHubText.startAndPair);
      expect(start.onPressed, isNull);
    });
  });

  group('DesktopHubSharedTracksCard', () {
    testWidgets('an empty library offers both ways out', (tester) async {
      var refreshes = 0;
      var opens = 0;
      await tester.pumpWidget(
        _host(
          DesktopHubSharedTracksCard(
            tracks: const [],
            running: false,
            loading: false,
            onRefresh: () => refreshes++,
            onOpenLibrary: () => opens++,
          ),
        ),
      );

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(
        find.text(DesktopTransferHubText.tracksEmptyTitle),
        findsOneWidget,
      );
      expect(find.text(DesktopTransferHubText.stopped), findsOneWidget);

      await tester.tap(_button(DesktopTransferHubText.refresh));
      await tester.tap(_button(DesktopTransferHubText.openLibrary));
      expect(refreshes, 1);
      expect(opens, 1);
    });

    testWidgets('refresh waits while another step runs', (tester) async {
      await tester.pumpWidget(
        _host(
          DesktopHubSharedTracksCard(
            tracks: const [],
            running: false,
            loading: false,
            onRefresh: null,
            onOpenLibrary: () {},
          ),
        ),
      );

      expect(
        _buttonWidget(tester, DesktopTransferHubText.refresh).onPressed,
        isNull,
      );
      expect(
        _buttonWidget(tester, DesktopTransferHubText.openLibrary).onPressed,
        isNotNull,
      );
    });

    testWidgets('while loading it neither claims emptiness nor lists', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          DesktopHubSharedTracksCard(
            tracks: const [],
            running: false,
            loading: true,
            onRefresh: null,
            onOpenLibrary: () {},
          ),
        ),
      );

      expect(
        find.widgetWithText(
          AppInlineLoading,
          DesktopTransferHubText.libraryLoading,
        ),
        findsOneWidget,
      );
      expect(find.byType(AppEmptyState), findsNothing);
    });

    testWidgets('songs are listed with their details', (tester) async {
      await tester.pumpWidget(
        _host(
          DesktopHubSharedTracksCard(
            tracks: const [_track],
            running: true,
            loading: false,
            onRefresh: () {},
            onOpenLibrary: () {},
          ),
        ),
      );

      expect(find.text(DesktopTransferHubText.tracksTitle(1)), findsOneWidget);
      expect(find.text('夜曲'), findsOneWidget);
      expect(find.text('周杰伦 · FLAC · 25.0 MB'), findsOneWidget);
      expect(find.text(DesktopTransferHubText.reachable), findsOneWidget);
      expect(find.byType(AppEmptyState), findsNothing);
    });
  });

  group('DesktopHubOverviewCard', () {
    testWidgets('a stopped service can be started', (tester) async {
      var starts = 0;
      var stops = 0;
      await tester.pumpWidget(
        _host(
          DesktopHubOverviewCard(
            running: false,
            initializing: false,
            busy: false,
            trackCount: 2,
            onStart: () => starts++,
            onStop: () => stops++,
            onRefresh: () {},
          ),
        ),
      );

      expect(find.text(DesktopTransferHubText.stoppedTitle), findsOneWidget);
      await tester.tap(_button(DesktopTransferHubText.start));
      expect(starts, 1);
      expect(stops, 0);
    });

    testWidgets('a running service can be stopped', (tester) async {
      var stops = 0;
      await tester.pumpWidget(
        _host(
          DesktopHubOverviewCard(
            running: true,
            initializing: false,
            busy: false,
            trackCount: 2,
            onStart: () {},
            onStop: () => stops++,
            onRefresh: () {},
          ),
        ),
      );

      expect(find.text(DesktopTransferHubText.runningTitle), findsOneWidget);
      await tester.tap(_button(DesktopTransferHubText.stop));
      expect(stops, 1);
    });

    testWidgets('both buttons wait while a step runs', (tester) async {
      await tester.pumpWidget(
        _host(
          DesktopHubOverviewCard(
            running: false,
            initializing: false,
            busy: true,
            trackCount: 0,
            onStart: () {},
            onStop: () {},
            onRefresh: () {},
          ),
        ),
      );

      expect(
        _buttonWidget(tester, DesktopTransferHubText.start).onPressed,
        isNull,
      );
      expect(
        _buttonWidget(tester, DesktopTransferHubText.refresh).onPressed,
        isNull,
      );
    });
  });

  group('DesktopHubPairingCard', () {
    testWidgets('without addresses the address list is left out', (
      tester,
    ) async {
      var copies = 0;
      await tester.pumpWidget(
        _host(
          DesktopHubPairingCard(
            session: MediaHubSession(
              host: '127.0.0.1',
              port: 47820,
              token: 'token',
              startedAt: DateTime(2026, 11, 30),
              trackCount: 0,
            ),
            onCopy: () => copies++,
          ),
        ),
      );

      expect(find.text(DesktopTransferHubText.endpointsTitle), findsNothing);
      await tester.tap(_button(DesktopTransferHubText.copy));
      expect(copies, 1);
    });
  });
}
