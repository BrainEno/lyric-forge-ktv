import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_asr_runtime_health_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/storage_preflight_asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';

const config = TranscriptionConfig(
  mode: TranscriptionMode.highestQuality,
  profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
  qwenExecutable: '', whisperExecutable: '', modelPath: '',
);
final status = AsrRuntimeStatus(
  profile: const ResolvedTranscriptionProfile(
    profile: TranscriptionProfilePreference.rtx5080HighQuality,
    label: 'test', description: 'test',
    hardware: TranscriptionHardwareInfo(operatingSystem: 'test', architecture: 'test'),
    config: config,
  ),
  managedRoot: 'test', components: const [],
);
const storage = AsrStoragePreflightResult(
  state: AsrStoragePreflightState.sufficient, managedRoot: 'test',
  estimatedInstalledBytes: 0, existingRelevantBytes: 0,
  temporaryHeadroomBytes: 0, safetyMarginBytes: 0,
  requiredAdditionalBytes: 0, availableBytes: 100, detail: '',
);
final cancelled = isA<TranscriptionException>().having(
  (e) => e.kind, 'kind', TranscriptionFailureKind.cancelled,
);
final busy = isA<TranscriptionException>().having(
  (e) => e.kind, 'kind', TranscriptionFailureKind.busy,
);

void main() {
  test('cancel during authorization prevents inspection and install; retry works', () async {
    final authorization = Completer<bool>();
    final delegate = _Runtime();
    final health = _Health();
    var calls = 0;
    final manager = StoragePreflightAsrRuntimeManager(
      delegate: delegate, storagePreflightService: _Storage(), healthChecker: health,
      storageAuthorizationRequired: () => ++calls == 1 ? authorization.future : Future.value(false),
    );
    final first = manager.installRecommended(config);
    final firstResult = expectLater(first, throwsA(cancelled));
    await expectLater(manager.installRecommended(config), throwsA(busy));
    await manager.cancel();
    authorization.complete(false);
    await firstResult;
    expect(delegate.inspectCalls, 0);
    expect(delegate.installCalls, 0);
    expect(delegate.cancelCalls, 0);
    expect(await manager.installRecommended(config), config);
  });

  test('cancel while verifying prevents invalidation even if verification fails', () async {
    final verify = Completer<AsrRuntimeStatus>();
    final entered = Completer<void>();
    final delegate = _Runtime();
    final health = _Health()..onVerify = () { entered.complete(); return verify.future; };
    final manager = _manager(delegate, health, _Storage());
    final result = expectLater(manager.installRecommended(config), throwsA(cancelled));
    await entered.future;
    await manager.cancel();
    verify.completeError(StateError('probe failed'));
    await result;
    expect(health.invalidations, 0);
    expect(delegate.installCalls, 0);
  });

  test('cancel during invalidation waits for it and skips storage and download', () async {
    final gate = Completer<bool>();
    final entered = Completer<void>();
    final delegate = _Runtime();
    final health = _Health()..onInvalidate = () { entered.complete(); return gate.future; };
    final disk = _Storage();
    final manager = _manager(delegate, health, disk);
    final result = expectLater(manager.installRecommended(config), throwsA(cancelled));
    await entered.future;
    await manager.cancel();
    await expectLater(manager.installRecommended(config), throwsA(busy));
    gate.complete(false);
    await result;
    expect(disk.calls, 0);
    expect(delegate.installCalls, 0);
  });

  test('cancel during disk check prevents download', () async {
    final gate = Completer<AsrStoragePreflightResult>();
    final entered = Completer<void>();
    final delegate = _Runtime();
    final disk = _Storage()..onInspect = () { entered.complete(); return gate.future; };
    final manager = _manager(delegate, _Health(), disk);
    final result = expectLater(manager.installRecommended(config), throwsA(cancelled));
    await entered.future;
    await manager.cancel();
    gate.complete(storage);
    await result;
    expect(delegate.installCalls, 0);
  });

  test('delegate cancel is single-flight; no retry until both futures settle', () async {
    final install = Completer<TranscriptionConfig>();
    final cancel = Completer<void>();
    final entered = Completer<void>();
    final delegate = _Runtime()
      ..onInstall = () { entered.complete(); return install.future; }
      ..onCancel = () => cancel.future;
    final manager = _manager(delegate, _Health(), _Storage());
    final result = expectLater(manager.installRecommended(config), throwsA(cancelled));
    await entered.future;
    final c1 = manager.cancel();
    final c2 = manager.cancel();
    expect(delegate.cancelCalls, 1);
    install.complete(config);
    await Future<void>.delayed(Duration.zero);
    await expectLater(manager.installRecommended(config), throwsA(busy));
    cancel.complete();
    await Future.wait([c1, c2, result]);
    delegate.onInstall = null;
    expect(await manager.installRecommended(config), config);
    await manager.cancel();
    expect(delegate.cancelCalls, 1);
  });
}

StoragePreflightAsrRuntimeManager _manager(_Runtime runtime, _Health health, _Storage disk) =>
    StoragePreflightAsrRuntimeManager(delegate: runtime, healthChecker: health,
      storagePreflightService: disk, storageAuthorizationRequired: () async => false);

class _Runtime implements AsrRuntimeManager {
  int inspectCalls = 0, installCalls = 0, cancelCalls = 0;
  Future<TranscriptionConfig> Function()? onInstall;
  Future<void> Function()? onCancel;
  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => const Stream.empty();
  @override
  bool get isInstalling => false;
  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async { inspectCalls++; return status; }
  @override
  Future<TranscriptionConfig> installRecommended(TranscriptionConfig config) { installCalls++; return onInstall?.call() ?? Future.value(config); }
  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async => config;
  @override
  Future<void> cancel() { cancelCalls++; return onCancel?.call() ?? Future.value(); }
}

class _Health implements AsrRuntimeHealthChecker {
  int invalidations = 0;
  Future<AsrRuntimeStatus> Function()? onVerify;
  Future<bool> Function()? onInvalidate;
  @override
  Future<AsrRuntimeStatus> verify(AsrRuntimeStatus status) => onVerify?.call() ?? Future.value(status);
  @override
  Future<bool> invalidateManagedFailures(AsrRuntimeStatus status) { invalidations++; return onInvalidate?.call() ?? Future.value(false); }
  @override
  Future<void> cleanupInstallerCache(String root) async {}
  @override
  void clearCache() {}
}

class _Storage implements AsrStoragePreflightService {
  int calls = 0;
  Future<AsrStoragePreflightResult> Function()? onInspect;
  @override
  Future<AsrStoragePreflightResult> inspect(TranscriptionConfig config, {AsrRuntimeStatus? runtimeStatus}) {
    calls++; return onInspect?.call() ?? Future.value(storage);
  }
}
