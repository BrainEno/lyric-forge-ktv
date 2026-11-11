import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/coordinated_asr_install_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_asr_runtime_health_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/storage_preflight_asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_resource_coordinator.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';

const config = TranscriptionConfig(
  mode: TranscriptionMode.whisperOnly,
  qwenExecutable: 'qwen',
  whisperExecutable: 'whisper',
  modelPath: 'model',
);
final status = AsrRuntimeStatus(
  profile: const ResolvedTranscriptionProfile(
    profile: TranscriptionProfilePreference.automatic,
    label: 'test',
    description: 'test',
    hardware: TranscriptionHardwareInfo(
      operatingSystem: 'test',
      architecture: 'test',
    ),
    config: config,
  ),
  managedRoot: 'test',
  components: const [],
);
final busy = isA<TranscriptionException>().having(
  (e) => e.kind,
  'kind',
  TranscriptionFailureKind.busy,
);
final cancelled = isA<TranscriptionException>().having(
  (e) => e.kind,
  'kind',
  TranscriptionFailureKind.cancelled,
);

void main() {
  test(
    'every resource use rejects installation before touching the delegate',
    () async {
      final resources = AsrResourceCoordinator();
      final delegate = _Runtime();
      final facade = CoordinatedAsrInstallManager(
        delegate: delegate,
        resources: resources,
      );
      for (final use in AsrResourceUse.values) {
        final owner = resources.tryAcquire(use)!;
        await expectLater(facade.installRecommended(config), throwsA(busy));
        await facade.cancel();
        expect(delegate.installCalls, 0);
        expect(delegate.cancelCalls, 0);
        expect(resources.activeUse, use);
        owner.release();
      }
    },
  );

  test(
    'only owner may cancel; lease lasts through install and pending cancel',
    () async {
      final resources = AsrResourceCoordinator();
      final delegate = _Runtime();
      final install = Completer<TranscriptionConfig>();
      final cancel = Completer<void>();
      delegate.onInstall = () => install.future;
      delegate.onCancel = () => cancel.future;
      final owner = CoordinatedAsrInstallManager(
        delegate: delegate,
        resources: resources,
      );
      final other = CoordinatedAsrInstallManager(
        delegate: delegate,
        resources: resources,
      );
      final running = owner.installRecommended(config);
      expect(resources.activeUse, AsrResourceUse.installation);
      expect(owner.isInstalling, isTrue);
      await expectLater(owner.installRecommended(config), throwsA(busy));
      await expectLater(other.installRecommended(config), throwsA(busy));
      delegate.installing = true;
      expect(other.isInstalling, isTrue);
      await other.cancel();
      expect(delegate.cancelCalls, 0);
      delegate.installing = false;
      final firstCancel = owner.cancel();
      final secondCancel = owner.cancel();
      expect(delegate.cancelCalls, 1);
      install.complete(config);
      await Future<void>.delayed(Duration.zero);
      expect(resources.activeUse, AsrResourceUse.installation);
      await expectLater(other.installRecommended(config), throwsA(busy));
      cancel.complete();
      await Future.wait([firstCancel, secondCancel]);
      expect(await running, config);
      expect(resources.activeUse, isNull);
      await owner.cancel();
      expect(delegate.cancelCalls, 1);
      delegate.onInstall = null;
      expect(await other.installRecommended(config), config);
    },
  );

  test(
    'delegate errors release the lease and do not acquire for repair or inspect',
    () async {
      final resources = AsrResourceCoordinator();
      final delegate = _Runtime()
        ..onInstall = () => Future.error(StateError('install failed'));
      final facade = CoordinatedAsrInstallManager(
        delegate: delegate,
        resources: resources,
      );
      await expectLater(facade.installRecommended(config), throwsStateError);
      expect(resources.activeUse, isNull);
      final owner = resources.tryAcquire(AsrResourceUse.transcription)!;
      expect(await facade.repair(config), config);
      expect(await facade.inspect(config), same(status));
      expect(resources.activeUse, AsrResourceUse.transcription);
      owner.release();
      delegate.onInstall = () => throw StateError('synchronous failure');
      await expectLater(facade.installRecommended(config), throwsStateError);
      expect(resources.activeUse, isNull);
    },
  );

  test('cancel failure is reported and still releases the lease', () async {
    final resources = AsrResourceCoordinator();
    final install = Completer<TranscriptionConfig>();
    final delegate = _Runtime();
    delegate.onInstall = () => install.future;
    delegate.onCancel = () => Future.error(StateError('cancel failed'));
    final facade = CoordinatedAsrInstallManager(
      delegate: delegate,
      resources: resources,
    );
    final running = facade.installRecommended(config);
    final result = expectLater(running, throwsStateError);
    await expectLater(facade.cancel(), throwsStateError);
    expect(resources.activeUse, AsrResourceUse.installation);
    install.complete(config);
    await result;
    expect(resources.activeUse, isNull);
  });

  test(
    'real preflight observes owner cancellation while holding the shared lease',
    () async {
      final authorization = Completer<bool>();
      final resources = AsrResourceCoordinator();
      final delegate = _Runtime();
      final preflight = StoragePreflightAsrRuntimeManager(
        delegate: delegate,
        storagePreflightService: _Storage(),
        healthChecker: _Health(),
        storageAuthorizationRequired: () => authorization.future,
      );
      final owner = CoordinatedAsrInstallManager(
        delegate: preflight,
        resources: resources,
      );
      final other = CoordinatedAsrInstallManager(
        delegate: preflight,
        resources: resources,
      );
      final running = expectLater(
        owner.installRecommended(config),
        throwsA(cancelled),
      );
      expect(preflight.isInstalling, isFalse);
      expect(owner.isInstalling, isTrue);
      await other.cancel();
      await owner.cancel();
      await expectLater(other.installRecommended(config), throwsA(busy));
      expect(resources.activeUse, AsrResourceUse.installation);
      authorization.complete(false);
      await running;
      expect(delegate.installCalls, 0);
      expect(delegate.cancelCalls, 0);
      expect(resources.activeUse, isNull);
    },
  );
}

class _Runtime implements AsrRuntimeManager {
  int installCalls = 0, cancelCalls = 0;
  bool installing = false;
  Future<TranscriptionConfig> Function()? onInstall;
  Future<void> Function()? onCancel;
  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => const Stream.empty();
  @override
  bool get isInstalling => installing;
  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async => status;
  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      config;
  @override
  Future<TranscriptionConfig> installRecommended(TranscriptionConfig config) {
    installCalls++;
    return onInstall?.call() ?? Future.value(config);
  }

  @override
  Future<void> cancel() {
    cancelCalls++;
    return onCancel?.call() ?? Future.value();
  }
}

class _Health implements AsrRuntimeHealthChecker {
  @override
  Future<AsrRuntimeStatus> verify(AsrRuntimeStatus status) async => status;
  @override
  Future<bool> invalidateManagedFailures(AsrRuntimeStatus status) async =>
      false;
  @override
  Future<void> cleanupInstallerCache(String root) async {}
  @override
  void clearCache() {}
}

class _Storage implements AsrStoragePreflightService {
  @override
  Future<AsrStoragePreflightResult> inspect(
    TranscriptionConfig config, {
    AsrRuntimeStatus? runtimeStatus,
  }) => throw StateError('cancelled preflight must not inspect storage');
}
