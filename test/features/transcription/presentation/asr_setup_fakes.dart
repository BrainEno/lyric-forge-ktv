import 'dart:async';

import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_download_connection_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_managed_storage_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/transcription_screen_dependencies.dart';

// Fakes for the first-run setup dialog and its controller (audit I-03),
// shared by asr_runtime_setup_controller_test.dart and
// asr_runtime_setup_dialog_test.dart.

const setupConfigured = TranscriptionConfig(
  whisperExecutable: 'whisper-cli',
  modelPath: '/models/ggml-large-v3.bin',
);

const setupHardware = TranscriptionHardwareInfo(
  operatingSystem: 'macos',
  architecture: 'arm64',
  cpuName: 'Apple M2',
  systemMemoryMb: 16384,
);

const setupProfile = ResolvedTranscriptionProfile(
  profile: TranscriptionProfilePreference.automatic,
  label: 'Apple 芯片高质量',
  description: '测试方案',
  hardware: setupHardware,
  config: setupConfigured,
);

/// FFmpeg is always ready; the Whisper model is ready when [ready] is.
AsrRuntimeStatus setupStatus({required bool ready, String root = '/runtime'}) {
  return AsrRuntimeStatus(
    profile: setupProfile,
    managedRoot: root,
    components: [
      const AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.ffmpeg,
        state: AsrRuntimeComponentState.ready,
        label: 'FFmpeg',
        detail: '系统已安装',
      ),
      AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.whisperModel,
        state: ready
            ? AsrRuntimeComponentState.ready
            : AsrRuntimeComponentState.missing,
        label: 'Whisper 模型',
        detail: 'ggml-large-v3',
      ),
    ],
  );
}

AsrStoragePreflightResult setupSpace(AsrStoragePreflightState state) {
  return AsrStoragePreflightResult(
    state: state,
    managedRoot: '/runtime',
    estimatedInstalledBytes: 4 << 30,
    existingRelevantBytes: 0,
    temporaryHeadroomBytes: 0,
    safetyMarginBytes: 0,
    requiredAdditionalBytes: 4 << 30,
    availableBytes: state == AsrStoragePreflightState.insufficient
        ? 1 << 30
        : 100 << 30,
    detail: '',
  );
}

AsrManagedStorageMoveResult setupMoved({
  String target = '/new/LyricForge/ASRRuntime',
  bool moved = true,
  bool adoptedExisting = false,
  bool oldRootRetained = false,
}) {
  return AsrManagedStorageMoveResult(
    sourceRoot: '/runtime',
    targetRoot: target,
    copiedBytes: 10,
    copiedFiles: 1,
    moved: moved,
    adoptedExisting: adoptedExisting,
    oldRootRetained: oldRootRetained,
  );
}

class FakeSetupStore implements TranscriptionSettingsStore {
  TranscriptionConfig? stored;
  Object? saveError;
  final saved = <TranscriptionConfig>[];

  @override
  Future<TranscriptionConfig?> load() async => stored;

  @override
  Future<void> save(TranscriptionConfig config) async {
    final error = saveError;
    if (error != null) throw error;
    saved.add(config);
    stored = config;
  }

  @override
  Future<void> clear() async => stored = null;
}

class FakeSetupRuntime implements AsrRuntimeManager {
  final progress = StreamController<AsrRuntimeInstallProgress>.broadcast();
  AsrRuntimeStatus status = setupStatus(ready: false);

  /// What [inspect] returns once an install finished.
  AsrRuntimeStatus? statusAfterInstall;
  Object? inspectError;
  Object? installError;
  bool installing = false;
  Completer<TranscriptionConfig>? pendingInstall;
  Completer<void>? pendingInspect;
  int installCalls = 0;
  int inspectCalls = 0;
  int repairCalls = 0;
  int cancelCalls = 0;
  final inspected = <TranscriptionConfig>[];

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => progress.stream;

  @override
  bool get isInstalling => installing;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    inspectCalls++;
    inspected.add(config);
    final pending = pendingInspect;
    if (pending != null) await pending.future;
    final error = inspectError;
    if (error != null) throw error;
    return status;
  }

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async {
    installCalls++;
    final error = installError;
    if (error != null) throw error;
    final pending = pendingInstall;
    final installed = pending != null
        ? await pending.future
        : config.copyWith(modelPath: '/runtime/models/ggml.bin');
    final after = statusAfterInstall;
    if (after != null) status = after;
    return installed;
  }

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async {
    repairCalls++;
    return config;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    final pending = pendingInstall;
    pendingInstall = null;
    pending?.completeError(
      const TranscriptionException.cancelled('download cancelled'),
    );
  }
}

class FakeSetupPreflight implements AsrStoragePreflightService {
  AsrStoragePreflightState state = AsrStoragePreflightState.sufficient;
  int calls = 0;

  @override
  Future<AsrStoragePreflightResult> inspect(
    TranscriptionConfig config, {
    AsrRuntimeStatus? runtimeStatus,
  }) async {
    calls++;
    return setupSpace(state);
  }
}

class FakeSetupStorage implements AsrManagedStorageService {
  AsrManagedStorageMoveResult? discovered;
  AsrManagedStorageMoveResult moveResult = setupMoved();
  Object? discoverError;
  Object? adoptError;
  Object? moveError;
  int discoverCalls = 0;
  final adoptedPaths = <String>[];
  final movedTo = <String>[];

  @override
  Future<AsrManagedStorageLocation> inspect() async =>
      const AsrManagedStorageLocation(
        activeRoot: '/runtime',
        defaultRoot: '/runtime',
        managedBytes: 0,
        isDefault: true,
      );

  @override
  Future<AsrManagedStorageMoveResult?> discoverAndAdoptExisting() async {
    discoverCalls++;
    final error = discoverError;
    if (error != null) throw error;
    return discovered;
  }

  @override
  Future<AsrManagedStorageMoveResult> adoptExistingAt(
    String selectedPath,
  ) async {
    adoptedPaths.add(selectedPath);
    final error = adoptError;
    if (error != null) throw error;
    return setupMoved(target: selectedPath, adoptedExisting: true);
  }

  @override
  Future<AsrManagedStorageMoveResult> moveToParent(
    String selectedParent, {
    void Function(int copiedBytes, int totalBytes)? onProgress,
  }) async {
    movedTo.add(selectedParent);
    final error = moveError;
    if (error != null) throw error;
    return moveResult;
  }

  @override
  Future<AsrManagedStorageMoveResult> moveToDefault({
    void Function(int copiedBytes, int totalBytes)? onProgress,
  }) async => moveResult;
}

class _Profiles implements TranscriptionProfileResolver {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _Checker implements AsrDownloadConnectionChecker {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _Proxy implements TranscriptionDownloadProxyStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// The dialog's dependencies around the given fakes; the advanced settings
/// dialog's services are never called by these tests.
AsrRuntimeSetupDependencies setupDependencies({
  required FakeSetupRuntime runtime,
  FakeSetupPreflight? preflight,
  FakeSetupStorage? storage,
  FakeSetupStore? store,
}) {
  return AsrRuntimeSetupDependencies(
    asrRuntimeManager: runtime,
    asrStoragePreflightService: preflight ?? FakeSetupPreflight(),
    asrManagedStorageService: storage ?? FakeSetupStorage(),
    transcriptionSettingsStore: store ?? FakeSetupStore(),
    configDialogDependencies: TranscriptionConfigDialogDependencies(
      profileResolver: _Profiles(),
      downloadConnectionChecker: _Checker(),
      downloadProxyStore: _Proxy(),
    ),
  );
}

/// Lets the fakes' futures and the controller's follow-ups finish.
Future<void> settleSetup() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
