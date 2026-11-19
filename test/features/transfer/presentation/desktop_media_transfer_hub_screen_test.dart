import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/app_error_state.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_session.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/shared_audio_track.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_share_catalog.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/screens/desktop_media_transfer_hub_screen.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/transfer_screen_dependencies.dart';

// A failed step on the desktop transfer page shows the shared error state,
// and its 重试 runs that same step again.

class _Catalog implements MediaShareCatalog {
  _Catalog({this.failures = 0});

  /// How many of the first calls throw.
  int failures;
  int calls = 0;

  @override
  Future<List<SharedAudioTrack>> build() async {
    calls++;
    if (failures > 0) {
      failures--;
      throw const FileSystemLikeException('磁盘不可读');
    }
    return const [];
  }
}

class FileSystemLikeException implements Exception {
  const FileSystemLikeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _Hub implements MediaHubService {
  _Hub({this.startFails = false});

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

  @override
  MediaHubState get currentState => const MediaHubState.stopped();

  @override
  MediaHubSession? get currentSession => null;

  @override
  bool get isRunning => false;

  Future<void> close() => _states.close();
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _Hub hub,
  required _Catalog catalog,
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
    ),
  );
  await tester.pumpAndSettle();
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
}
