import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_queue_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_download_connection_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_managed_storage_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/batch_transcription_queue.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/transcription_screen_dependencies.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/transcription_queue_panel.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1366, 768)]) {
    testWidgets('busy queue offers continue without a repair prompt at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final queue = _Queue();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TranscriptionQueuePanel(
                queue: queue,
                setupDependencies: AsrRuntimeSetupDependencies(
                  asrRuntimeManager: _Runtime(),
                  asrStoragePreflightService: _StoragePreflight(),
                  asrManagedStorageService: _Storage(),
                  transcriptionSettingsStore: _Settings(),
                  configDialogDependencies:
                      TranscriptionConfigDialogDependencies(
                        profileResolver: _Profiles(),
                        downloadConnectionChecker: _Checker(),
                        downloadProxyStore: _Proxy(),
                      ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('资源正忙'), findsOneWidget);
      expect(find.text('识别资源正忙，队列已暂停；请在其他任务结束后继续'), findsOneWidget);
      expect(find.text('修复后继续'), findsNothing);
      await tester.tap(find.text('继续'));
      await tester.pump();
      expect(queue.resumeCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Queue implements BatchTranscriptionQueue {
  int resumeCalls = 0;
  @override
  Stream<TranscriptionQueueSnapshot> get snapshots => const Stream.empty();
  @override
  TranscriptionQueueSnapshot get current => TranscriptionQueueSnapshot(
    isPaused: true,
    isProcessing: false,
    pauseReason: TranscriptionQueuePauseReason.resourceBusy,
    items: [
      TranscriptionQueueItem(
        id: '1',
        sourcePath: 'song.wav',
        projectName: 'song',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ],
  );
  @override
  Future<void> resume() async {
    resumeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runtime implements AsrRuntimeManager {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _StoragePreflight implements AsrStoragePreflightService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Storage implements AsrManagedStorageService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Settings implements TranscriptionSettingsStore {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Profiles implements TranscriptionProfileResolver {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Checker implements AsrDownloadConnectionChecker {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Proxy implements TranscriptionDownloadProxyStore {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
