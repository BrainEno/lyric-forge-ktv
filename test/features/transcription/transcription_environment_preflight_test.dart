import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_environment_preflight.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

void main() {
  const baseConfig = TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
    qwenExecutable: 'qwen3-asr',
    whisperExecutable: 'whisper-cli',
    modelPath: 'whisper.bin',
  );

  test('unconfigured store returns without touching the runtime manager',
      () async {
    final store = _FakeSettingsStore();
    final runtime = _FakeRuntimeManager(
      status: _status(baseConfig, ready: true),
    );
    final preflight = TranscriptionEnvironmentPreflight(
      settingsStore: store,
      runtimeManager: runtime,
    );

    final result = await preflight.inspect();

    expect(
      result.state,
      TranscriptionEnvironmentReadinessState.unconfigured,
    );
    expect(result.config, isNull);
    expect(runtime.repairCalls, 0);
    expect(runtime.inspectCalls, 0);
    expect(store.saveCalls, 0);
  });

  test('ready runtime persists repaired paths and reports ready', () async {
    final repaired = baseConfig.copyWith(
      qwenExecutable: r'C:\LyricForge\qwen3-asr.exe',
      modelPath: r'C:\LyricForge\models\whisper.bin',
    );
    final store = _FakeSettingsStore(baseConfig);
    final runtime = _FakeRuntimeManager(
      repaired: repaired,
      status: _status(repaired, ready: true),
    );
    final preflight = TranscriptionEnvironmentPreflight(
      settingsStore: store,
      runtimeManager: runtime,
    );

    final result = await preflight.inspect();

    expect(result.state, TranscriptionEnvironmentReadinessState.ready);
    expect(result.isReady, isTrue);
    expect(result.blockingComponents, isEmpty);
    expect(store.value?.qwenExecutable, repaired.qwenExecutable);
    expect(store.value?.modelPath, repaired.modelPath);
    expect(store.saveCalls, 1);
    expect(runtime.repairCalls, 1);
    expect(runtime.inspectCalls, 1);
  });

  test('missing component reports setup required without losing config',
      () async {
    final store = _FakeSettingsStore(baseConfig);
    final runtime = _FakeRuntimeManager(
      status: _status(baseConfig, ready: false),
    );
    final preflight = TranscriptionEnvironmentPreflight(
      settingsStore: store,
      runtimeManager: runtime,
    );

    final result = await preflight.inspect();

    expect(
      result.state,
      TranscriptionEnvironmentReadinessState.needsSetup,
    );
    expect(result.isReady, isFalse);
    expect(result.config, isNotNull);
    expect(result.blockingComponents, hasLength(1));
    expect(
      result.blockingComponents.single.component,
      AsrRuntimeComponent.qwenModel,
    );
  });

  test('runtime inspection failure becomes actionable failed state', () async {
    final store = _FakeSettingsStore(baseConfig);
    final runtime = _FakeRuntimeManager(
      status: _status(baseConfig, ready: true),
      inspectError: const TranscriptionException('runtime probe failed'),
    );
    final preflight = TranscriptionEnvironmentPreflight(
      settingsStore: store,
      runtimeManager: runtime,
    );

    final result = await preflight.inspect();

    expect(result.state, TranscriptionEnvironmentReadinessState.failed);
    expect(result.config, same(baseConfig));
    expect(result.error, contains('runtime probe failed'));
  });
}

AsrRuntimeStatus _status(
  TranscriptionConfig config, {
  required bool ready,
}) {
  const hardware = TranscriptionHardwareInfo(
    operatingSystem: 'windows',
    architecture: 'x64',
    gpuName: 'NVIDIA GeForce RTX 5080',
    gpuMemoryMb: 16384,
  );
  final profile = ResolvedTranscriptionProfile(
    profile: TranscriptionProfilePreference.rtx5080HighQuality,
    label: 'RTX 5080 高质量',
    description: 'test profile',
    hardware: hardware,
    config: config,
  );

  return AsrRuntimeStatus(
    profile: profile,
    managedRoot: r'C:\LyricForge\ASRRuntime',
    components: [
      const AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.ffmpeg,
        state: AsrRuntimeComponentState.ready,
        label: 'FFmpeg',
        detail: 'ready',
      ),
      AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.qwenModel,
        state: ready
            ? AsrRuntimeComponentState.ready
            : AsrRuntimeComponentState.missing,
        label: 'Qwen3-ASR 1.7B',
        detail: ready ? 'ready' : 'missing',
      ),
    ],
  );
}

class _FakeSettingsStore implements TranscriptionSettingsStore {
  TranscriptionConfig? value;
  int saveCalls = 0;

  _FakeSettingsStore([this.value]);

  @override
  Future<TranscriptionConfig?> load() async => value;

  @override
  Future<void> save(TranscriptionConfig config) async {
    saveCalls++;
    value = config;
  }
}

class _FakeRuntimeManager implements AsrRuntimeManager {
  final TranscriptionConfig? repaired;
  final AsrRuntimeStatus status;
  final Object? inspectError;
  final StreamController<AsrRuntimeInstallProgress> _progress =
      StreamController<AsrRuntimeInstallProgress>.broadcast();

  int repairCalls = 0;
  int inspectCalls = 0;

  _FakeRuntimeManager({
    this.repaired,
    required this.status,
    this.inspectError,
  });

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => _progress.stream;

  @override
  bool get isInstalling => false;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    inspectCalls++;
    final error = inspectError;
    if (error != null) throw error;
    return status;
  }

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async => config;

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async {
    repairCalls++;
    return repaired ?? config;
  }

  @override
  Future<void> cancel() async {}
}
