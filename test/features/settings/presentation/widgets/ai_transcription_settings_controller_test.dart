import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/ai_transcription_settings_controller.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_managed_storage_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

const _configured = TranscriptionConfig(
  whisperExecutable: 'whisper-cli',
  modelPath: '/models/ggml-large-v3.bin',
);

const _profile = ResolvedTranscriptionProfile(
  profile: TranscriptionProfilePreference.intelMacHighQuality,
  label: 'Intel Mac 高质量',
  description: '测试方案',
  hardware: TranscriptionHardwareInfo(
    operatingSystem: 'macos',
    architecture: 'x86_64',
  ),
  config: _configured,
);

AsrRuntimeStatus _status({required bool ready, String root = '/runtime'}) {
  return AsrRuntimeStatus(
    profile: _profile,
    managedRoot: root,
    components: [
      const AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.ffmpeg,
        state: AsrRuntimeComponentState.ready,
        label: 'FFmpeg',
        detail: '',
      ),
      AsrRuntimeComponentStatus(
        component: AsrRuntimeComponent.whisperModel,
        state: ready
            ? AsrRuntimeComponentState.ready
            : AsrRuntimeComponentState.missing,
        label: 'Whisper 模型',
        detail: '',
      ),
    ],
  );
}

AsrStoragePreflightResult _space(AsrStoragePreflightState state) {
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

const _location = AsrManagedStorageLocation(
  activeRoot: '/runtime',
  defaultRoot: '/runtime',
  managedBytes: 0,
  isDefault: true,
);

AsrManagedStorageMoveResult _moved({
  String target = '/new/LyricForge/ASRRuntime',
  bool adoptedExisting = false,
  bool oldRootRetained = false,
}) {
  return AsrManagedStorageMoveResult(
    sourceRoot: '/runtime',
    targetRoot: target,
    copiedBytes: 10,
    copiedFiles: 1,
    moved: true,
    adoptedExisting: adoptedExisting,
    oldRootRetained: oldRootRetained,
  );
}

class _Store implements TranscriptionSettingsStore {
  TranscriptionConfig? stored;
  final saved = <TranscriptionConfig>[];

  @override
  Future<TranscriptionConfig?> load() async => stored;

  @override
  Future<void> save(TranscriptionConfig config) async {
    saved.add(config);
    stored = config;
  }

  @override
  Future<void> clear() async => stored = null;
}

class _Runtime implements AsrRuntimeManager {
  final progress = StreamController<AsrRuntimeInstallProgress>.broadcast();
  AsrRuntimeStatus status = _status(ready: false);
  Object? inspectError;
  Object? installError;
  bool installing = false;
  Completer<TranscriptionConfig>? pendingInstall;
  int installCalls = 0;
  int cancelCalls = 0;

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => progress.stream;

  @override
  bool get isInstalling => installing;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
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
    if (pending != null) return pending.future;
    return config.copyWith(modelPath: '/runtime/models/ggml.bin');
  }

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      config;

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

class _Preflight implements AsrStoragePreflightService {
  AsrStoragePreflightState state = AsrStoragePreflightState.sufficient;
  int calls = 0;

  @override
  Future<AsrStoragePreflightResult> inspect(
    TranscriptionConfig config, {
    AsrRuntimeStatus? runtimeStatus,
  }) async {
    calls++;
    return _space(state);
  }
}

class _Storage implements AsrManagedStorageService {
  AsrManagedStorageMoveResult? discovered;
  AsrManagedStorageMoveResult moveResult = _moved();
  Object? adoptError;
  Object? moveError;
  final adoptedPaths = <String>[];
  final movedTo = <String>[];
  var movedToDefault = 0;

  @override
  Future<AsrManagedStorageLocation> inspect() async => _location;

  @override
  Future<AsrManagedStorageMoveResult?> discoverAndAdoptExisting() async =>
      discovered;

  @override
  Future<AsrManagedStorageMoveResult> adoptExistingAt(
    String selectedPath,
  ) async {
    adoptedPaths.add(selectedPath);
    final error = adoptError;
    if (error != null) throw error;
    return _moved(target: selectedPath, adoptedExisting: true);
  }

  @override
  Future<AsrManagedStorageMoveResult> moveToParent(
    String selectedParent, {
    void Function(int copiedBytes, int totalBytes)? onProgress,
  }) async {
    movedTo.add(selectedParent);
    final error = moveError;
    if (error != null) throw error;
    onProgress?.call(5, 10);
    return moveResult;
  }

  @override
  Future<AsrManagedStorageMoveResult> moveToDefault({
    void Function(int copiedBytes, int totalBytes)? onProgress,
  }) async {
    movedToDefault++;
    onProgress?.call(10, 10);
    return moveResult;
  }
}

const _texts = AsrExistingModelTexts(
  scanning: 'scanning',
  notFound: 'not found',
  pathNotRecognised: 'not recognised',
  checkingPath: _checking,
);

String _checking(String path) => 'checking $path';

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Store store;
  late _Runtime runtime;
  late _Preflight preflight;
  late _Storage storage;
  late List<String> sized;

  setUp(() {
    store = _Store()..stored = _configured;
    runtime = _Runtime();
    preflight = _Preflight();
    storage = _Storage();
    sized = <String>[];
  });

  AiTranscriptionSettingsController build() {
    return AiTranscriptionSettingsController(
      settingsStore: store,
      runtimeManager: runtime,
      storagePreflightService: preflight,
      managedStorageService: storage,
      texts: _texts,
      directorySize: (path) async {
        sized.add(path);
        return 2048;
      },
    );
  }

  Future<AiTranscriptionSettingsController> started() async {
    final controller = build()..start();
    addTearDown(controller.dispose);
    await _settle();
    return controller;
  }

  group('loading', () {
    test('starts busy with the default plan before anything loads', () {
      final controller = build();
      addTearDown(controller.dispose);

      expect(controller.loading, isTrue);
      expect(controller.busy, isTrue);
      expect(
        controller.config,
        AiTranscriptionSettingsController.defaultConfig,
      );
      expect(controller.ready, isFalse);
    });

    test('start loads the saved plan and inspects the environment', () async {
      runtime.status = _status(ready: true);
      final controller = await started();

      expect(controller.loading, isFalse);
      expect(controller.busy, isFalse);
      expect(controller.config, _configured);
      expect(controller.ready, isTrue);
      expect(controller.managedBytes, 2048);
      expect(controller.managedStorageLocation, same(_location));
      expect(controller.storageBlocked, isFalse);
      expect(sized, ['/runtime']);
      expect(controller.error, isNull);
    });

    test('a recognition error is shown as it is', () async {
      runtime.inspectError = const TranscriptionException('runtime missing');
      final controller = await started();

      expect(controller.error, 'runtime missing');
      expect(controller.loading, isFalse);
    });

    test('any other error says that the check failed', () async {
      runtime.inspectError = StateError('disk');
      final controller = await started();

      expect(controller.error, startsWith('检测识别环境失败：'));
      expect(controller.loading, isFalse);
    });

    test('install progress from the runtime manager is followed', () async {
      final controller = await started();
      var notified = 0;
      controller.addListener(() => notified++);

      runtime.progress.add(
        const AsrRuntimeInstallProgress(progress: 0.5, message: 'half'),
      );
      await _settle();

      expect(controller.progress?.message, 'half');
      expect(notified, greaterThan(0));
    });

    test('a controller closed mid-check stays quiet', () async {
      final controller = build()..start();
      controller.dispose();
      await _settle();

      expect(controller.isDisposed, isTrue);
      expect(controller.loading, isTrue);
    });
  });

  group('plan', () {
    test('changing the mode saves a usable plan', () async {
      final controller = await started();

      await controller.changeMode(TranscriptionMode.whisperOnly);

      expect(controller.config.mode, TranscriptionMode.whisperOnly);
      expect(store.saved.last.mode, TranscriptionMode.whisperOnly);
      expect(
        store.saved.last.profilePreference,
        TranscriptionProfilePreference.automatic,
      );
    });

    test('a custom hardware profile stays custom', () async {
      store.stored = _configured.copyWith(
        profilePreference: TranscriptionProfilePreference.custom,
      );
      final controller = await started();

      await controller.changeMode(TranscriptionMode.whisperOnly);

      expect(
        controller.config.profilePreference,
        TranscriptionProfilePreference.custom,
      );
    });

    test('an incomplete plan is kept but not saved', () async {
      store.stored = null;
      final controller = await started();

      await controller.changeMode(TranscriptionMode.whisperOnly);

      expect(controller.config.mode, TranscriptionMode.whisperOnly);
      expect(store.saved, isEmpty);
    });
  });

  group('install', () {
    test('stops before downloading when the disk is too full', () async {
      final controller = await started();
      preflight.state = AsrStoragePreflightState.insufficient;

      await controller.install();

      expect(runtime.installCalls, 0);
      expect(controller.storageBlocked, isTrue);
      expect(controller.error, startsWith('磁盘空间不足'));
      expect(controller.error, contains('还差 3.00 GB'));
      expect(controller.installing, isFalse);
    });

    test('a finished install saves the plan and clears progress', () async {
      final controller = await started();

      await controller.install();

      expect(runtime.installCalls, 1);
      expect(store.saved.last.modelPath, '/runtime/models/ggml.bin');
      expect(controller.config.modelPath, '/runtime/models/ggml.bin');
      expect(controller.progress, isNull);
      expect(controller.installing, isFalse);
      expect(controller.error, isNull);
    });

    test('pausing is not a failure and resuming keeps progress', () async {
      final controller = await started();
      runtime.pendingInstall = Completer<TranscriptionConfig>();

      final running = controller.install();
      await _settle();
      expect(controller.installing, isTrue);
      expect(controller.busy, isTrue);
      runtime.progress.add(
        const AsrRuntimeInstallProgress(
          component: AsrRuntimeComponent.whisperModel,
          progress: 0.4,
          message: '40%',
        ),
      );
      await _settle();

      await controller.pause();
      await running;

      expect(runtime.cancelCalls, 1);
      expect(controller.paused, isTrue);
      expect(controller.installing, isFalse);
      expect(controller.error, isNull);
      expect(controller.failedComponent, isNull);
      expect(controller.progress?.message, '40%');

      await controller.resume();

      expect(runtime.installCalls, 2);
      expect(controller.paused, isFalse);
      expect(controller.progress, isNull);
    });

    test('pause does nothing while nothing is downloading', () async {
      final controller = await started();

      await controller.pause();

      expect(runtime.cancelCalls, 0);
    });

    test('a failed download names the component that failed', () async {
      final controller = await started();
      runtime.pendingInstall = Completer<TranscriptionConfig>();

      final running = controller.install();
      await _settle();
      runtime.progress.add(
        const AsrRuntimeInstallProgress(
          component: AsrRuntimeComponent.qwenModel,
          progress: 0.7,
          message: 'qwen',
        ),
      );
      await _settle();
      runtime.pendingInstall!.completeError(
        const TranscriptionException('checksum mismatch'),
      );
      await running;

      expect(controller.failedComponent, AsrRuntimeComponent.qwenModel);
      expect(controller.error, 'checksum mismatch');
      expect(controller.paused, isFalse);
    });

    test('an unexpected failure says that the install failed', () async {
      final controller = await started();
      runtime.installError = StateError('network');

      await controller.retry();

      expect(controller.error, startsWith('安装识别环境失败：'));
    });
  });

  group('existing models', () {
    test('a scan that finds nothing says so', () async {
      final controller = await started();

      await controller.scanExisting();

      expect(controller.existingModelMessage, 'not found');
      expect(controller.scanningExisting, isFalse);
    });

    test('a found environment is used and saved', () async {
      runtime.status = _status(ready: true);
      storage.discovered = _moved(target: '/old/ASRRuntime');
      final controller = await started();
      store.saved.clear();

      await controller.scanExisting();

      expect(store.saved, isNotEmpty);
      expect(controller.existingModelMessage, contains('/old/ASRRuntime'));
      expect(controller.existingModelMessage, contains('本次没有下载'));
      expect(controller.scanningExisting, isFalse);
    });

    test('nothing starts while the shared runtime is installing', () async {
      final controller = await started();
      runtime.installing = true;

      expect(controller.canStartExclusive, isFalse);
      await controller.scanExisting();
      await controller.adoptExistingPath('/somewhere');

      expect(controller.existingModelMessage, isNull);
      expect(storage.adoptedPaths, isEmpty);
    });

    test('a pasted path is checked and used', () async {
      final controller = await started();

      await controller.adoptExistingPath('/disk/LyricForge');

      expect(storage.adoptedPaths, ['/disk/LyricForge']);
      expect(controller.existingModelMessage, contains('/disk/LyricForge'));
      expect(controller.existingModelMessage, contains('1/2 个组件就绪'));
    });

    test('a path that is not an environment leaves things alone', () async {
      storage.adoptError = StateError('no runtime');
      final controller = await started();

      await controller.adoptExistingPath('/tmp');

      expect(controller.existingModelMessage, 'not recognised');
      expect(controller.error, startsWith('识别已有模型失败：'));
      expect(controller.scanningExisting, isFalse);
    });

    test('a blank path is ignored', () async {
      final controller = await started();

      await controller.adoptExistingPath('   ');

      expect(storage.adoptedPaths, isEmpty);
    });
  });

  group('storage move', () {
    test('a move reports progress and returns the result', () async {
      final controller = await started();
      final copied = <int>[];
      controller.addListener(() {
        if (controller.movingStorage) copied.add(controller.movingCopiedBytes);
      });

      final result = await controller.moveStorage(parent: '/new');

      expect(result, isNotNull);
      expect(storage.movedTo, ['/new']);
      expect(copied, contains(5));
      expect(controller.movingStorage, isFalse);
      expect(controller.movingTotalBytes, 0);
    });

    test('moving back to the default location', () async {
      final controller = await started();

      await controller.moveStorage(useDefault: true);

      expect(storage.movedToDefault, 1);
    });

    test('an incomplete plan moves without being saved', () async {
      store.stored = null;
      final controller = await started();

      await controller.moveStorage(parent: '/new');

      expect(store.saved, isEmpty);
    });

    test('taking over an existing folder says nothing was copied', () async {
      storage.moveResult = _moved(adoptedExisting: true);
      final controller = await started();

      await controller.moveStorage(parent: '/new');

      expect(controller.existingModelMessage, contains('未复制或删除旧目录'));
    });

    test('a failed move returns null and explains', () async {
      storage.moveError = StateError('read only');
      final controller = await started();

      final result = await controller.moveStorage(parent: '/new');

      expect(result, isNull);
      expect(controller.error, startsWith('迁移识别环境失败：'));
      expect(controller.movingStorage, isFalse);
    });

    test('a blank parent does not start a move', () async {
      final controller = await started();

      expect(await controller.moveStorage(parent: ' '), isNull);
      expect(storage.movedTo, isEmpty);
    });
  });

  group('delete', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('asr_settings_delete_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      Directory(_join(root.path, 'models')).createSync();
      File(_join(_join(root.path, 'models'), 'ggml.bin')).writeAsStringSync('');
      File(_join(root.path, 'runtime.txt')).writeAsStringSync('keep');
    });

    test('deleting removes only the managed models', () async {
      runtime.status = _status(ready: true, root: root.path);
      final controller = await started();

      await controller.deleteModels(reinstall: false);

      expect(Directory(_join(root.path, 'models')).existsSync(), isFalse);
      expect(File(_join(root.path, 'runtime.txt')).existsSync(), isTrue);
      expect(controller.deleting, isFalse);
      expect(runtime.installCalls, 0);
    });

    test('delete and reinstall downloads again', () async {
      runtime.status = _status(ready: true, root: root.path);
      final controller = await started();

      await controller.deleteModels(reinstall: true);

      expect(runtime.installCalls, 1);
    });

    test('nothing is deleted before the environment was inspected', () async {
      final controller = build();
      addTearDown(controller.dispose);

      await controller.deleteModels(reinstall: false);

      expect(Directory(_join(root.path, 'models')).existsSync(), isTrue);
    });
  });

  group('messages', () {
    test('an adopted environment reports how ready it is', () {
      expect(
        AiTranscriptionSettingsController.adoptedMessage('/r', null),
        contains('请重新检测'),
      );
      expect(
        AiTranscriptionSettingsController.adoptedMessage(
          '/r',
          _status(ready: true),
        ),
        contains('SHA-256'),
      );
      expect(
        AiTranscriptionSettingsController.adoptedMessage(
          '/r',
          _status(ready: false),
        ),
        contains('1/2 个组件就绪'),
      );
    });

    test('the snack bar after a move names what happened', () {
      expect(
        AiTranscriptionSettingsController.movedMessage(_moved()),
        '识别环境已迁移到 /new/LyricForge/ASRRuntime',
      );
      expect(
        AiTranscriptionSettingsController.movedMessage(
          _moved(adoptedExisting: true),
        ),
        contains('旧目录未删除'),
      );
      expect(
        AiTranscriptionSettingsController.movedMessage(
          _moved(oldRootRetained: true),
        ),
        contains('请手工清理'),
      );
    });
  });

  group('measureDirectory', () {
    const measure = AiTranscriptionSettingsController.measureDirectory;

    test('a blank path cannot be measured', () async {
      expect(await measure(' '), isNull);
    });

    test('a folder that does not exist yet holds nothing', () async {
      final root = Directory.systemTemp.createTempSync('asr_settings_none_');
      addTearDown(() => root.deleteSync(recursive: true));

      expect(await measure(_join(root.path, 'missing')), 0);
    });

    test('files in nested folders are added up', () async {
      final root = Directory.systemTemp.createTempSync('asr_settings_size_');
      addTearDown(() => root.deleteSync(recursive: true));
      final nested = Directory(_join(root.path, 'a'))..createSync();
      File(_join(root.path, 'one')).writeAsBytesSync(List.filled(10, 0));
      File(_join(nested.path, 'two')).writeAsBytesSync(List.filled(5, 0));

      expect(await measure(root.path), 15);
    });
  });
}
