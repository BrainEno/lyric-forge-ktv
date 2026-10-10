import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_asr_runtime_health_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/storage_preflight_asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';

void main() {
  test('healthy executable probe is cached until managed dependency tree changes',
      () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-health-cache-');
    addTearDown(() => root.delete(recursive: true));
    final bin = Directory('${root.path}${Platform.pathSeparator}bundle${Platform.pathSeparator}bin');
    await bin.create(recursive: true);
    final executable = File('${bin.path}${Platform.pathSeparator}qwen3-asr.exe');
    final dependency = File('${bin.path}${Platform.pathSeparator}cudart64.dll');
    await executable.writeAsString('runtime');
    await dependency.writeAsString('dependency-v1');

    var probes = 0;
    final checker = LocalAsrRuntimeHealthChecker(
      probe: (path, component) async {
        probes += 1;
        return const RuntimeExecutableHealth(
          healthy: true,
          detail: 'ok',
        );
      },
    );
    final status = _status(
      root: root.path,
      qwenPath: executable.path,
    );

    expect((await checker.verify(status)).isReady, isTrue);
    expect((await checker.verify(status)).isReady, isTrue);
    expect(probes, 1);

    await dependency.writeAsString('dependency-v2-with-a-different-size');
    expect((await checker.verify(status)).isReady, isTrue);
    expect(probes, 2);
  });

  test('failed managed runtime is marked failed and invalidation removes bundle',
      () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-health-broken-');
    addTearDown(() => root.delete(recursive: true));
    final bin = Directory('${root.path}${Platform.pathSeparator}bundle${Platform.pathSeparator}bin');
    await bin.create(recursive: true);
    final executable = File('${bin.path}${Platform.pathSeparator}qwen3-asr.exe');
    await executable.writeAsString('broken-runtime');

    final checker = LocalAsrRuntimeHealthChecker(
      probe: (path, component) async => const RuntimeExecutableHealth(
        healthy: false,
        detail: 'missing CUDA DLL',
      ),
    );
    final checked = await checker.verify(
      _status(root: root.path, qwenPath: executable.path),
    );

    final qwen = checked.components.singleWhere(
      (component) => component.component == AsrRuntimeComponent.qwenRuntime,
    );
    expect(qwen.state, AsrRuntimeComponentState.failed);
    expect(qwen.detail, contains('missing CUDA DLL'));

    expect(await checker.invalidateManagedFailures(checked), isTrue);
    expect(await Directory('${root.path}${Platform.pathSeparator}bundle').exists(), isFalse);
  });

  test('health invalidation never deletes an external manual runtime', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-health-managed-');
    final external = await Directory.systemTemp.createTemp('lyricforge-health-external-');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => external.delete(recursive: true));
    final executable = File('${external.path}${Platform.pathSeparator}qwen3-asr.exe');
    await executable.writeAsString('manual-runtime');

    final checker = LocalAsrRuntimeHealthChecker();
    final failed = _status(
      root: root.path,
      qwenPath: executable.path,
      qwenState: AsrRuntimeComponentState.failed,
    );

    expect(await checker.invalidateManagedFailures(failed), isFalse);
    expect(await executable.exists(), isTrue);
  });

  test('successful install cleanup removes disposable zips but preserves partials',
      () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-health-cleanup-');
    addTearDown(() => root.delete(recursive: true));
    final downloads = Directory('${root.path}${Platform.pathSeparator}downloads');
    await downloads.create(recursive: true);

    final disposable = [
      'asr-runtime.zip',
      'ffmpeg.zip',
      'whisper-b5130-x64.zip',
    ];
    for (final name in disposable) {
      await File('${downloads.path}${Platform.pathSeparator}$name').writeAsString('cache');
    }
    final partial = File('${downloads.path}${Platform.pathSeparator}asr-runtime.zip.part');
    final unrelated = File('${downloads.path}${Platform.pathSeparator}keep-me.zip');
    await partial.writeAsString('resume');
    await unrelated.writeAsString('keep');

    final checker = LocalAsrRuntimeHealthChecker();
    await checker.cleanupInstallerCache(root.path);

    for (final name in disposable) {
      expect(
        await File('${downloads.path}${Platform.pathSeparator}$name').exists(),
        isFalse,
      );
    }
    expect(await partial.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });

  test('outer install guard downgrades to Whisper when only Qwen health fails',
      () async {
    final delegate = _InspectableRuntimeManager(_readyStatus());
    final checker = _FakeHealthChecker(
      transform: (status) => _withQwenFailure(status),
    );
    final manager = StoragePreflightAsrRuntimeManager(
      delegate: delegate,
      storagePreflightService: const _EnoughStorage(),
      healthChecker: checker,
    );

    final result = await manager.installRecommended(_highestQualityConfig());

    expect(delegate.installCalls, 1);
    expect(result.mode, TranscriptionMode.whisperOnly);
    expect(checker.cleanupCalls, 1);
  });

  test('outer install guard rejects health failure in required Whisper baseline',
      () async {
    final delegate = _InspectableRuntimeManager(_readyStatus());
    final checker = _FakeHealthChecker(
      transform: (status) => _withWhisperFailure(status),
    );
    final manager = StoragePreflightAsrRuntimeManager(
      delegate: delegate,
      storagePreflightService: const _EnoughStorage(),
      healthChecker: checker,
    );

    await expectLater(
      manager.installRecommended(_highestQualityConfig()),
      throwsA(
        isA<TranscriptionException>().having(
          (error) => error.message,
          'message',
          contains('运行健康检查失败'),
        ),
      ),
    );
  });
}

TranscriptionConfig _highestQualityConfig() {
  return const TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
    qwenExecutable: 'qwen3-asr.exe',
    qwenModelPath: 'Qwen/Qwen3-ASR-1.7B',
    qwenAlignerModelPath: 'Qwen/Qwen3-ForcedAligner-0.6B',
    whisperExecutable: 'whisper-cli.exe',
    modelPath: 'ggml-large-v3.bin',
  );
}

AsrRuntimeStatus _status({
  required String root,
  required String qwenPath,
  AsrRuntimeComponentState qwenState = AsrRuntimeComponentState.ready,
}) {
  return AsrRuntimeStatus(
    profile: _profile(),
    managedRoot: root,
    components: [
      const AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.ffmpeg,
        state: AsrRuntimeComponentState.ready,
        label: 'FFmpeg',
        detail: 'ready',
        resolvedPath: 'ffmpeg',
      ),
      const AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.whisperRuntime,
        state: AsrRuntimeComponentState.ready,
        label: 'Whisper runtime',
        detail: 'ready',
        resolvedPath: 'whisper-cli',
      ),
      const AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.whisperModel,
        state: AsrRuntimeComponentState.ready,
        label: 'Whisper model',
        detail: 'ready',
      ),
      AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.qwenRuntime,
        state: qwenState,
        label: 'Qwen runtime',
        detail: qwenState == AsrRuntimeComponentState.ready ? 'ready' : 'failed',
        resolvedPath: qwenPath,
      ),
      const AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.qwenModel,
        state: AsrRuntimeComponentState.ready,
        label: 'Qwen model',
        detail: 'ready',
      ),
      const AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.qwenAligner,
        state: AsrRuntimeComponentState.ready,
        label: 'Aligner',
        detail: 'ready',
      ),
    ],
  );
}

AsrRuntimeStatus _readyStatus() {
  return _status(root: r'C:\LyricForge\ASRRuntime', qwenPath: r'C:\LyricForge\ASRRuntime\bundle\bin\qwen3-asr.exe');
}

AsrRuntimeStatus _withQwenFailure(AsrRuntimeStatus status) {
  return AsrRuntimeStatus(
    profile: status.profile,
    managedRoot: status.managedRoot,
    components: [
      for (final component in status.components)
        if (component.component == AsrRuntimeComponent.qwenRuntime)
          AsrRuntimeComponentStatus(
            component: component.component,
            state: AsrRuntimeComponentState.failed,
            label: component.label,
            detail: 'CUDA runtime failed health check',
            resolvedPath: component.resolvedPath,
          )
        else
          component,
    ],
  );
}

AsrRuntimeStatus _withWhisperFailure(AsrRuntimeStatus status) {
  return AsrRuntimeStatus(
    profile: status.profile,
    managedRoot: status.managedRoot,
    components: [
      for (final component in status.components)
        if (component.component == AsrRuntimeComponent.whisperRuntime)
          AsrRuntimeComponentStatus(
            component: component.component,
            state: AsrRuntimeComponentState.failed,
            label: component.label,
            detail: 'Whisper runtime failed health check',
            resolvedPath: component.resolvedPath,
          )
        else
          component,
    ],
  );
}

ResolvedTranscriptionProfile _profile() {
  return ResolvedTranscriptionProfile(
    profile: TranscriptionProfilePreference.rtx5080HighQuality,
    label: 'RTX 5080',
    description: 'test profile',
    hardware: const TranscriptionHardwareInfo(
      operatingSystem: 'windows',
      architecture: 'x86_64',
      gpuName: 'NVIDIA GeForce RTX 5080',
    ),
    config: _highestQualityConfig(),
  );
}

class _InspectableRuntimeManager implements AsrRuntimeManager {
  final StreamController<AsrRuntimeInstallProgress> _progress =
      StreamController<AsrRuntimeInstallProgress>.broadcast();
  AsrRuntimeStatus status;
  int installCalls = 0;

  _InspectableRuntimeManager(this.status);

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => _progress.stream;

  @override
  bool get isInstalling => false;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async => status;

  @override
  Future<TranscriptionConfig> installRecommended(TranscriptionConfig config) async {
    installCalls += 1;
    return config;
  }

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async => config;

  @override
  Future<void> cancel() async {}
}

class _FakeHealthChecker implements AsrRuntimeHealthChecker {
  final AsrRuntimeStatus Function(AsrRuntimeStatus status) transform;
  int cleanupCalls = 0;

  _FakeHealthChecker({required this.transform});

  @override
  Future<AsrRuntimeStatus> verify(AsrRuntimeStatus status) async => transform(status);

  @override
  Future<bool> invalidateManagedFailures(AsrRuntimeStatus status) async => false;

  @override
  Future<void> cleanupInstallerCache(String managedRoot) async {
    cleanupCalls += 1;
  }

  @override
  void clearCache() {}
}

class _EnoughStorage implements AsrStoragePreflightService {
  const _EnoughStorage();

  @override
  Future<AsrStoragePreflightResult> inspect(
    TranscriptionConfig config, {
    AsrRuntimeStatus? runtimeStatus,
  }) async {
    return const AsrStoragePreflightResult(
      state: AsrStoragePreflightState.sufficient,
      managedRoot: r'C:\LyricForge\ASRRuntime',
      estimatedInstalledBytes: 10,
      existingRelevantBytes: 0,
      temporaryHeadroomBytes: 0,
      safetyMarginBytes: 0,
      requiredAdditionalBytes: 10,
      availableBytes: 100,
      detail: 'enough',
    );
  }
}
