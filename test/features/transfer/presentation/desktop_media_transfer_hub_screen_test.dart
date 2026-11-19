import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/core/widgets/app_empty_state.dart';
import 'package:lyric_forge_ktv/core/widgets/app_error_state.dart';
import 'package:lyric_forge_ktv/core/widgets/app_loading_state.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_session.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/shared_audio_track.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_share_catalog.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/screens/desktop_media_transfer_hub_screen.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/transfer_screen_dependencies.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/widgets/desktop_transfer_hub_cards.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/widgets/desktop_transfer_hub_text.dart';

// A failed step on the desktop transfer page shows the shared error state,
// and its 重试 runs that same step again. The page also says what it is
// loading, offers a way out of an empty library and stays out of the way on
// devices that cannot start the service.

class _Catalog implements MediaShareCatalog {
  _Catalog({this.failures = 0, this.tracks = const []});

  /// How many of the first calls throw.
  int failures;
  int calls = 0;
  List<SharedAudioTrack> tracks;

  /// Holds the first read open while set.
  Completer<void>? gate;

  @override
  Future<List<SharedAudioTrack>> build() async {
    calls++;
    await gate?.future;
    if (failures > 0) {
      failures--;
      throw const FileSystemLikeException('磁盘不可读');
    }
    return tracks;
  }
}

class FileSystemLikeException implements Exception {
  const FileSystemLikeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _Hub implements MediaHubService {
  _Hub({this.startFails = false, this.state = const MediaHubState.stopped()});

  final bool startFails;
  int startCalls = 0;
  final _states = StreamController<MediaHubState>.broadcast();

  @override
  Future<MediaHubSession> startSharing(List<SharedAudioTrack> tracks) async {
    startCalls++;
    if (startFails) throw StateError('端口被占用');
    throw UnimplementedError('only failures are exercised here');
  }

  @override
  Future<void> stopSharing() async {}

  @override
  Stream<MediaHubState> get stateStream => _states.stream;

  /// The state the page starts from.
  final MediaHubState state;

  @override
  MediaHubState get currentState => state;

  @override
  MediaHubSession? get currentSession => state.session;

  @override
  bool get isRunning => state.isRunning;

  Future<void> close() => _states.close();
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _Hub hub,
  required _Catalog catalog,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: DesktopMediaTransferHubScreen(
        dependencies: DesktopMediaHubDependencies(hub: hub, catalog: catalog),
      ),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (context) => Scaffold(body: Text('页面 ${settings.name}')),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

SharedAudioTrack _track(int index) => SharedAudioTrack(
  id: 't$index',
  title: '歌曲 $index',
  artist: '歌手',
  localPath: '/music/$index.mp3',
  format: 'mp3',
  byteLength: 3 * 1024 * 1024,
);

MediaHubSession _session() => MediaHubSession(
  host: '192.168.1.20',
  port: 47820,
  token: 'token',
  startedAt: DateTime(2026, 11, 30),
  trackCount: 14,
  tlsFingerprint: 'ab:cd',
  endpoints: const [
    MediaHubEndpoint(
      host: '192.168.1.20',
      port: 47820,
      kind: MediaHubEndpointKind.lan,
    ),
    MediaHubEndpoint(
      host: '100.64.0.7',
      port: 47820,
      kind: MediaHubEndpointKind.tailscale,
    ),
  ],
);

/// Runs [body] as if on a Linux desktop.
Future<void> _onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Finder get _failureTitle =>
    find.text(DesktopMediaTransferHubScreen.failureTitle);

void main() {
  testWidgets('a failed library read can be retried in place', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final hub = _Hub();
      final catalog = _Catalog(failures: 1);
      await _pumpScreen(tester, hub: hub, catalog: catalog);

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(_failureTitle, findsOneWidget);
      expect(find.text('读取电脑音乐库失败：磁盘不可读'), findsOneWidget);
      expect(catalog.calls, 1);

      await tester.tap(find.text(AppErrorState.defaultRetryLabel));
      await tester.pumpAndSettle();

      expect(catalog.calls, 2);
      expect(_failureTitle, findsNothing);
      await hub.close();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a failed start retries the start and asks for consent again', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final hub = _Hub(startFails: true);
      final catalog = _Catalog();
      await _pumpScreen(tester, hub: hub, catalog: catalog);
      expect(_failureTitle, findsNothing);

      await tester.tap(find.text('启动传输服务').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('我了解共享范围，继续'));
      await tester.pumpAndSettle();

      expect(hub.startCalls, 1);
      expect(_failureTitle, findsOneWidget);
      expect(find.text('启动传输服务失败：Bad state: 端口被占用'), findsOneWidget);

      await tester.tap(find.text(AppErrorState.defaultRetryLabel));
      await tester.pumpAndSettle();

      // Retrying a start is a new start: the sharing scope is confirmed again.
      expect(find.text('开启加密的网络共享？'), findsOneWidget);
      await tester.tap(find.text('暂不启用'));
      await tester.pumpAndSettle();

      expect(hub.startCalls, 1);
      // Declining leaves the failure visible, with its retry.
      expect(_failureTitle, findsOneWidget);
      await hub.close();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('without a failure there is no error state', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final hub = _Hub();
      await _pumpScreen(tester, hub: hub, catalog: _Catalog());

      expect(find.byType(AppErrorState), findsNothing);
      expect(find.text('跨设备传输尚未启动'), findsOneWidget);
      await hub.close();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the first read says what is loading, then shows the songs', (
    tester,
  ) async {
    await _onDesktop(() async {
      final hub = _Hub();
      final catalog = _Catalog(tracks: List.generate(14, _track));
      catalog.gate = Completer<void>();
      await _pumpScreen(tester, hub: hub, catalog: catalog, settle: false);
      await tester.pump();

      // The waiting card and the song list both say what is happening.
      expect(
        find.widgetWithText(
          AppInlineLoading,
          DesktopTransferHubText.libraryLoading,
        ),
        findsNWidgets(2),
      );
      expect(find.text(DesktopTransferHubText.tracksEmptyTitle), findsNothing);

      catalog.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(AppInlineLoading), findsNothing);
      expect(find.text(DesktopTransferHubText.tracksTitle(14)), findsOneWidget);
      expect(find.text('歌曲 11'), findsOneWidget);
      expect(find.text('歌曲 12'), findsNothing);
      expect(find.text(DesktopTransferHubText.moreTracks(2)), findsOneWidget);
      expect(find.text('歌手 · MP3 · 3.0 MB'), findsNWidgets(12));
      await hub.close();
    });
  });

  testWidgets('an empty library offers to refresh it or open it', (
    tester,
  ) async {
    await _onDesktop(() async {
      final hub = _Hub();
      final catalog = _Catalog();
      await _pumpScreen(tester, hub: hub, catalog: catalog);

      final empty = find.byKey(DesktopHubSharedTracksCard.emptyKey);
      expect(empty, findsOneWidget);
      expect(
        find.text(DesktopTransferHubText.tracksEmptyTitle),
        findsOneWidget,
      );
      // The page no longer mixes "Library" into its Chinese sentences.
      expect(find.textContaining('Library'), findsNothing);

      final refresh = find.descendant(
        of: empty,
        matching: find.text(DesktopTransferHubText.refresh),
      );
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(catalog.calls, 2);
      expect(
        find.text(DesktopTransferHubText.refreshedStopped),
        findsOneWidget,
      );

      final open = find.descendant(
        of: empty,
        matching: find.text(DesktopTransferHubText.openLibrary),
      );
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.text('页面 ${Routes.library}'), findsOneWidget);
      await hub.close();
    });
  });

  testWidgets('a running service shows readable network names', (tester) async {
    await _onDesktop(() async {
      final hub = _Hub(
        state: MediaHubState(
          status: MediaHubStatus.running,
          session: _session(),
        ),
      );
      final catalog = _Catalog(tracks: [_track(1)]);
      await _pumpScreen(tester, hub: hub, catalog: catalog);

      expect(find.text(DesktopTransferHubText.runningTitle), findsOneWidget);
      expect(find.text('局域网：192.168.1.20:47820'), findsOneWidget);
      expect(find.text('Tailscale（可远程连接）：100.64.0.7:47820'), findsOneWidget);
      expect(find.textContaining('lan:'), findsNothing);
      expect(
        find.text(DesktopTransferHubText.toComputerRunning),
        findsOneWidget,
      );
      expect(
        find.text(DesktopTransferHubText.toPhoneRunning(14)),
        findsOneWidget,
      );
      expect(find.text(DesktopTransferHubText.reachable), findsOneWidget);
      await hub.close();
    });
  });

  testWidgets('a phone is pointed at its own way in', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final hub = _Hub();
      final catalog = _Catalog();
      await _pumpScreen(tester, hub: hub, catalog: catalog);

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(
        find.text(DesktopTransferHubText.desktopOnlyTitle),
        findsOneWidget,
      );
      expect(catalog.calls, 0);

      await tester.tap(find.text(DesktopTransferHubText.connectFromPhone));
      await tester.pumpAndSettle();
      expect(find.text('页面 ${Routes.remoteLibrary}'), findsOneWidget);
      await hub.close();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
