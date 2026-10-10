import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_asr_storage_preflight_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/storage_preflight_asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';

void main() {
  const gib = 1024 * 1024 * 1024;

  test('parses Windows DriveInfo and POSIX df free-space output', () {
    expect(
      LocalAsrStoragePreflightService.parseWindowsAvailableBytes(
        'AvailableFreeSpace\r\n123456789\r\n',
      ),
      123456789,
    );
    expect(
      LocalAsrStoragePreflightService.parseDfAvailableBytes(
        'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
        '/dev/disk1 1000000 400000 600000 40% /\n',
      ),
      600000 * 1024,
    );
  });

  test('blocks a fresh RTX highest-quality install when free space is low',
      () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-storage-low-');
    addTearDown(() => root.delete(recursive: true));
    final service = LocalAsrStoragePreflightService(
      profileResolver: _FakeProfileResolver(
        TranscriptionProfilePreference.rtx5080HighQuality,
      ),
      managedRootResolver: () async => root,
      freeSpaceReader: (_) async => 2 * gib,
    );

    final result = await service.inspect(_highestQualityConfig());

    expect(result.state, AsrStoragePreflightState.insufficient);
    expect(result.canInstall, isFalse);
    expect(result.estimatedInstalledBytes, 11 * gib);
    expect(result.requiredAdditionalBytes, greaterThan(2 * gib));
    expect(result.shortfallBytes, greaterThan(0));
  });

  test('existing target .part bytes reduce additional space requirement',
      () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-storage-part-');
    addTearDown(() => root.delete(recursive: true));
    final service = LocalAsrStoragePreflightService(
      profileResolver: _FakeProfileResolver(
        TranscriptionProfilePreference.rtx5080HighQuality,
      ),
      managedRootResolver: () async => root,
      freeSpaceReader: (_) async => 30 * gib,
    );

    final before = await service.inspect(_highestQualityConfig());
    final downloads = Directory('${root.path}${Platform.pathSeparator}downloads');
    await downloads.create(recursive: true);
    final part = File('${downloads.path}${Platform.pathSeparator}model.bin.part');
    await part.writeAsBytes(List<int>.filled(4 * 1024 * 1024, 0));
    final after = await service.inspect(_highestQualityConfig());

    expect(after.existingRelevantBytes, before.existingRelevantBytes + 4 * 1024 * 1024);
    expect(
      after.requiredAdditionalBytes,
      before.requiredAdditionalBytes - 4 * 1024 * 1024,
    );
  });

  test('custom profile is never blocked by managed-root free-space budget',
      () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-storage-custom-');
    addTearDown(() => root.delete(recursive: true));
    final service = LocalAsrStoragePreflightService(
      profileResolver: _FakeProfileResolver(
        TranscriptionProfilePreference.custom,
      ),
      managedRootResolver: () async => root,
      freeSpaceReader: (_) async => 0,
    );

    final result = await service.inspect(
      _highestQualityConfig().copyWith(
        profilePreference: TranscriptionProfilePreference.custom,
      ),
    );

    expect(result.state, AsrStoragePreflightState.notApplicable);
    expect(result.canInstall, isTrue);
    expect(result.requiredAdditionalBytes, 0);
  });

  test('runtime guard refuses install before delegate starts when storage is low',
      () async {
    final delegate = _FakeRuntimeManager();
    final manager = StoragePreflightAsrRuntimeManager(
      delegate: delegate,
      storagePreflightService: _FakeStoragePreflightService(
        _storageResult(
          state: AsrStoragePreflightState.insufficient,
          availableBytes: 2 * gib,
          requiredBytes: 8 * gib,
        ),
      ),
    );

    await expectLater(
      manager.installRecommended(_highestQualityConfig()),
      throwsA(
        isA<TranscriptionException>().having(
          (error) => error.message,
          'message',
          contains('磁盘空间不足'),
        ),
      ),
    );
    expect(delegate.installCalls, 0);
  });

  test('runtime guard delegates when free space is sufficient', () async {
    final delegate = _FakeRuntimeManager();
    final manager = StoragePreflightAsrRuntimeManager(
      delegate: delegate,
      storagePreflightService: _FakeStoragePreflightService(
        _storageResult(
          state: AsrStoragePreflightState.sufficient,
          availableBytes: 20 * gib,
          requiredBytes: 8 * gib,
        ),
      ),
    );

    final result = await manager.installRecommended(_highestQualityConfig());

    expect(delegate.installCalls, 1);
    expect(result.mode, TranscriptionMode.highestQuality);
  });
}

TranscriptionConfig _highestQualityConfig() {
  return const TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
    qwenExecutable: 'qwen3-asr',
    whisperExecutable: 'whisper-cli',
    modelPath: '',
  );
}

AsrStoragePreflightResult _storageResult({
  required AsrStoragePreflightState state,
  required int availableBytes,
  required int requiredBytes,
}) {
  return AsrStoragePreflightResult(
    state: state,
    managedRoot: r'C:\LyricForge\ASRRuntime',
    estimatedInstalledBytes: requiredBytes,
    existingRelevantBytes: 0,
    temporaryHeadroomBytes: 0,
    safetyMarginBytes: 0,
    requiredAdditionalBytes: requiredBytes,
    availableBytes: availableBytes,
    detail: 'fake',
  );
}

class _FakeProfileResolver implements TranscriptionProfileResolver {
  final TranscriptionProfilePreference profile;

  const _FakeProfileResolver(this.profile);

  @override
  Future<TranscriptionHardwareInfo> detectHardware() async =>
      const TranscriptionHardwareInfo(
        operatingSystem: 'windows',
        architecture: 'x86_64',
        gpuName: 'NVIDIA GeForce RTX 5080',
      );

  @override
  Future<ResolvedTranscriptionProfile> resolve(TranscriptionConfig config) async {
    return ResolvedTranscriptionProfile(
      profile: profile,
      label: profile.name,
      description: 'fake profile',
      hardware: await detectHardware(),
      config: config.copyWith(profilePreference: profile),
    );
  }
}

class _FakeStoragePreflightService implements AsrStoragePreflightService {
  final AsrStoragePreflightResult result;

  const _FakeStoragePreflightService(this.result);

  @override
  Future<AsrStoragePreflightResult> inspect(
    TranscriptionConfig config, {
    AsrRuntimeStatus? runtimeStatus,
  }) async {
    return result;
  }
}

class _FakeRuntimeManager implements AsrRuntimeManager {
  final StreamController<AsrRuntimeInstallProgress> _progress =
      StreamController<AsrRuntimeInstallProgress>.broadcast();
  int installCalls = 0;

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => _progress.stream;

  @override
  bool get isInstalling => false;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    throw const TranscriptionException('fake inspect unavailable');
  }

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
