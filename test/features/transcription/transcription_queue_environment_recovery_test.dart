import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_queue_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/batch_transcription_queue.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_queue_environment_recovery.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

void main() {
  const config = TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
    qwenExecutable: 'qwen3-asr',
    whisperExecutable: 'whisper-cli',
    modelPath: 'whisper.bin',
  );

  test('ready environment resumes an environment-protective pause', () async {
    final store = _FakeSettingsStore();
    final runtime = _FakeRuntimeManager(ready: true);
    final queue = _FakeQueue(reason: TranscriptionQueuePauseReason.environment);
    final recovery = TranscriptionQueueEnvironmentRecovery(
      settingsStore: store,
      runtimeManager: runtime,
      queue: queue,
    );

    final result = await recovery.recover(config);

    expect(result.ready, isTrue);
    expect(result.resumed, isTrue);
    expect(queue.resumeCalls, 1);
    expect(runtime.repairCalls, 1);
    expect(runtime.inspectCalls, 1);
    expect(store.saved, hasLength(2));
  });

  test('not-ready environment stays protectively paused', () async {
    final store = _FakeSettingsStore();
    final runtime = _FakeRuntimeManager(ready: false);
    final queue = _FakeQueue(reason: TranscriptionQueuePauseReason.environment);
    final recovery = TranscriptionQueueEnvironmentRecovery(
      settingsStore: store,
      runtimeManager: runtime,
      queue: queue,
    );

    final result = await recovery.recover(config);

    expect(result.ready, isFalse);
    expect(result.resumed, isFalse);
    expect(queue.resumeCalls, 0);
    expect(queue.current.isEnvironmentBlocked, isTrue);
  });

  test('manual pause that replaces environment pause is never overridden',
      () async {
    final store = _FakeSettingsStore();
    final runtime = _FakeRuntimeManager(ready: true);
    final queue = _FakeQueue(reason: TranscriptionQueuePauseReason.manual);
    final recovery = TranscriptionQueueEnvironmentRecovery(
      settingsStore: store,
      runtimeManager: runtime,
      queue: queue,
    );

    final result = await recovery.recover(config);

    expect(result.ready, isTrue);
    expect(result.resumed, isFalse);
    expect(queue.resumeCalls, 0);
    expect(queue.current.pauseReason, TranscriptionQueuePauseReason.manual);
  });
}

class _FakeSettingsStore implements TranscriptionSettingsStore {
  final List<TranscriptionConfig> saved = [];

  @override
  Future<void> clear() async {}

  @override
  Future<TranscriptionConfig?> load() async => saved.isEmpty ? null : saved.last;

  @override
  Future<void> save(TranscriptionConfig config) async => saved.add(config);
}

class _FakeRuntimeManager implements AsrRuntimeManager {
  final bool ready;
  int repairCalls = 0;
  int inspectCalls = 0;

  _FakeRuntimeManager({required this.ready});

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => const Stream.empty();

  @override
  bool get isInstalling => false;

  @override
  Future<void> cancel() async {}

  @override
  Future<TranscriptionConfig> installRecommended(TranscriptionConfig config) async =>
      config;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    inspectCalls += 1;
    return AsrRuntimeStatus(
      profile: ResolvedTranscriptionProfile(
        profile: TranscriptionProfilePreference.rtx5080HighQuality,
        label: 'RTX 5080',
        description: 'fake',
        hardware: const TranscriptionHardwareInfo(
          operatingSystem: 'windows',
          architecture: 'x86_64',
          gpuName: 'NVIDIA GeForce RTX 5080',
        ),
        config: config,
      ),
      components: [
        AsrRuntimeComponentStatus(
          component: AsrRuntimeComponent.qwenRuntime,
          state: ready
              ? AsrRuntimeComponentState.ready
              : AsrRuntimeComponentState.failed,
          label: 'Qwen runtime',
          detail: ready ? 'ready' : 'failed',
        ),
      ],
      managedRoot: r'C:\LyricForge\ASRRuntime',
    );
  }

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async {
    repairCalls += 1;
    return config;
  }
}

class _FakeQueue implements BatchTranscriptionQueue {
  TranscriptionQueuePauseReason? reason;
  int resumeCalls = 0;

  _FakeQueue({required this.reason});

  @override
  TranscriptionQueueSnapshot get current => TranscriptionQueueSnapshot(
        items: const [],
        isPaused: reason != null,
        isProcessing: false,
        pauseReason: reason,
        pauseMessage: reason == TranscriptionQueuePauseReason.environment
            ? 'runtime unavailable'
            : null,
      );

  @override
  Stream<TranscriptionQueueSnapshot> get snapshots => const Stream.empty();

  @override
  Future<void> clearCompleted() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<int> enqueuePaths(Iterable<String> paths) async => 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> pause() async => reason = TranscriptionQueuePauseReason.manual;

  @override
  Future<void> remove(String itemId) async {}

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    reason = null;
  }

  @override
  Future<void> retryFailed() async {}
}
