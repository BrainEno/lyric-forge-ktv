import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_managed_storage_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/asr_folder_text.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_runtime_setup_controller.dart';

import 'asr_setup_fakes.dart';

void main() {
  late FakeSetupStore store;
  late FakeSetupRuntime runtime;
  late FakeSetupPreflight preflight;
  late FakeSetupStorage storage;
  late AsrRuntimeSetupController controller;
  final created = <AsrRuntimeSetupController>[];

  AsrRuntimeSetupController build({TranscriptionConfig? initial}) {
    final built = AsrRuntimeSetupController(
      runtimeManager: runtime,
      storagePreflightService: preflight,
      managedStorageService: storage,
      settingsStore: store,
      initialConfig: initial,
    );
    created.add(built);
    return built;
  }

  Future<AsrRuntimeSetupController> started({
    TranscriptionConfig? initial,
  }) async {
    controller = build(initial: initial)..start();
    await settleSetup();
    return controller;
  }

  setUp(() {
    store = FakeSetupStore();
    runtime = FakeSetupRuntime();
    preflight = FakeSetupPreflight();
    storage = FakeSetupStorage();
  });

  tearDown(() async {
    for (final each in created) {
      if (!each.isDisposed) each.dispose();
    }
    created.clear();
    await runtime.progress.close();
  });

  group('inspection', () {
    test('starts loading with the default plan', () {
      controller = build();
      expect(controller.loading, isTrue);
      expect(controller.config, AsrRuntimeSetupController.defaultConfig);
      expect(controller.config.mode, TranscriptionMode.highestQuality);
      expect(controller.config.whisperExecutable, 'whisper-cli');
      expect(controller.config.qwenExecutable, 'qwen3-asr');
      expect(controller.status, isNull);
    });

    test('start repairs the plan and inspects components and space', () async {
      await started(initial: setupConfigured);

      expect(controller.loading, isFalse);
      expect(runtime.repairCalls, 1);
      expect(runtime.inspected.single, setupConfigured);
      expect(preflight.calls, 1);
      expect(controller.status?.components, hasLength(2));
      expect(controller.storage?.canInstall, isTrue);
      expect(controller.ready, isFalse);
      expect(controller.error, isNull);
    });

    test(
      'a ready computer is ready and hides the existing-model card',
      () async {
        runtime.status = setupStatus(ready: true);
        await started();

        expect(controller.ready, isTrue);
        expect(controller.showsExistingModels, isFalse);
        expect(controller.actions, [
          AsrSetupAction.advanced,
          AsrSetupAction.refresh,
          AsrSetupAction.start,
        ]);
      },
    );

    test('a recognition failure shows its own message', () async {
      runtime.inspectError = const TranscriptionException.environment(
        '缺少 FFmpeg',
      );
      await started();

      expect(controller.error, '缺少 FFmpeg');
      expect(controller.loading, isFalse);
    });

    test('any other failure is prefixed', () async {
      runtime.inspectError = StateError('boom');
      await started();

      expect(controller.error, startsWith('检测识别环境失败：'));
      expect(controller.error, contains('boom'));
    });

    test('refresh clears an earlier error', () async {
      runtime.inspectError = StateError('boom');
      await started();
      runtime.inspectError = null;

      await controller.refresh();

      expect(controller.error, isNull);
      expect(controller.status, isNotNull);
    });

    test('notifies listeners while loading and when done', () async {
      controller = build();
      final loadingStates = <bool>[];
      controller.addListener(() => loadingStates.add(controller.loading));
      controller.start();
      await settleSetup();

      expect(loadingStates.first, isTrue);
      expect(loadingStates.last, isFalse);
    });

    test('install progress from the runtime reaches the controller', () async {
      await started();
      const value = AsrRuntimeInstallProgress(
        component: AsrRuntimeComponent.whisperModel,
        progress: 0.4,
        message: '正在下载 Whisper 模型',
        phase: AsrRuntimeInstallPhase.downloading,
      );
      runtime.progress.add(value);
      await settleSetup();

      expect(controller.installProgress, same(value));
    });
  });

  group('quality mode', () {
    test('changing the mode inspects the new plan', () async {
      await started();

      await controller.changeMode(TranscriptionMode.whisperOnly);

      expect(controller.config.mode, TranscriptionMode.whisperOnly);
      expect(runtime.inspected.last.mode, TranscriptionMode.whisperOnly);
      expect(store.saved, isEmpty);
    });

    test('picking the current mode does nothing', () async {
      await started();
      final before = runtime.inspectCalls;

      await controller.changeMode(TranscriptionMode.highestQuality);

      expect(runtime.inspectCalls, before);
    });

    test('the mode is locked while downloading', () async {
      await started();
      runtime.pendingInstall = Completer<TranscriptionConfig>();
      unawaited(controller.install());
      await settleSetup();

      expect(controller.canChangeMode, isFalse);
      await controller.changeMode(TranscriptionMode.whisperOnly);
      expect(controller.config.mode, TranscriptionMode.highestQuality);

      runtime.pendingInstall!.complete(setupConfigured);
      await settleSetup();
    });
  });

  group('install', () {
    test('a finished install takes the installed plan', () async {
      runtime.statusAfterInstall = setupStatus(ready: true);
      await started();

      await controller.install();

      expect(runtime.installCalls, 1);
      expect(controller.config.modelPath, '/runtime/models/ggml.bin');
      expect(controller.installing, isFalse);
      expect(controller.installProgress, isNull);
      expect(controller.ready, isTrue);
      expect(controller.actions.last, AsrSetupAction.start);
    });

    test('starts with the checking-existing step', () async {
      await started();
      runtime.pendingInstall = Completer<TranscriptionConfig>();
      unawaited(controller.install());
      await settleSetup();

      expect(controller.installing, isTrue);
      expect(controller.canClose, isFalse);
      expect(controller.actions, [AsrSetupAction.pause]);
      expect(
        controller.installProgress?.phase,
        AsrRuntimeInstallPhase.checkingExisting,
      );
      expect(controller.installProgress?.message, contains('只有缺失或校验失败的文件才会下载'));
      expect(controller.showsProgress, isTrue);

      runtime.pendingInstall!.complete(setupConfigured);
      await settleSetup();
      expect(controller.installing, isFalse);
      expect(controller.canClose, isTrue);
    });

    test('a full disk stops before downloading and says by how much', () async {
      await started();
      preflight.state = AsrStoragePreflightState.insufficient;

      await controller.install();

      expect(runtime.installCalls, 0);
      expect(controller.storageBlocked, isTrue);
      expect(controller.error, startsWith('磁盘空间不足'));
      expect(controller.error, contains('4.00 GB'));
      expect(controller.error, contains('1.00 GB'));
      expect(controller.error, contains('还差 3.00 GB'));
      expect(controller.isEnabled(AsrSetupAction.install), isFalse);
    });

    test('pause turns the cancellation into a resumable pause', () async {
      await started();
      runtime.pendingInstall = Completer<TranscriptionConfig>();
      unawaited(controller.install());
      await settleSetup();

      await controller.pause();
      await settleSetup();

      expect(runtime.cancelCalls, 1);
      expect(controller.paused, isTrue);
      expect(controller.installing, isFalse);
      expect(controller.error, isNull);
      expect(controller.failed, isFalse);
      expect(controller.actions, [AsrSetupAction.later, AsrSetupAction.resume]);
      expect(controller.installProgress, isNotNull);
      expect(controller.showsProgress, isTrue);
    });

    test('pause does nothing when nothing downloads', () async {
      await started();

      await controller.pause();

      expect(runtime.cancelCalls, 0);
      expect(controller.paused, isFalse);
    });

    test('resume keeps the progress where it stopped', () async {
      await started();
      runtime.pendingInstall = Completer<TranscriptionConfig>();
      unawaited(controller.install());
      await settleSetup();
      const halfway = AsrRuntimeInstallProgress(
        component: AsrRuntimeComponent.whisperModel,
        progress: 0.5,
        message: '已下载一半',
        phase: AsrRuntimeInstallPhase.downloading,
      );
      runtime.progress.add(halfway);
      await settleSetup();
      await controller.pause();
      await settleSetup();

      runtime.pendingInstall = Completer<TranscriptionConfig>();
      unawaited(controller.resume());
      await settleSetup();

      expect(controller.paused, isFalse);
      expect(controller.installing, isTrue);
      expect(controller.installProgress, same(halfway));
      runtime.pendingInstall!.complete(setupConfigured);
      await settleSetup();
    });

    test('a failure names the component that was downloading', () async {
      await started();
      runtime.pendingInstall = Completer<TranscriptionConfig>();
      unawaited(controller.install());
      await settleSetup();
      runtime.progress.add(
        const AsrRuntimeInstallProgress(
          component: AsrRuntimeComponent.qwenModel,
          progress: 0.7,
          message: '正在下载 Qwen 模型',
          phase: AsrRuntimeInstallPhase.downloading,
        ),
      );
      await settleSetup();
      final inspectionsBefore = runtime.inspectCalls;

      runtime.pendingInstall!.completeError(
        const TranscriptionException.environment('网络中断'),
      );
      await settleSetup();

      expect(controller.error, '网络中断');
      expect(controller.failed, isTrue);
      expect(controller.paused, isFalse);
      expect(controller.failedComponent, AsrRuntimeComponent.qwenModel);
      expect(controller.retryLabel, '重试 Qwen 模型');
      expect(runtime.inspectCalls, greaterThan(inspectionsBefore));
      expect(controller.showsProgress, isTrue);
    });

    test('an unexpected failure is prefixed and retries generically', () async {
      runtime.installError = StateError('disk gone');
      await started();

      await controller.install();

      expect(controller.error, startsWith('安装识别环境失败：'));
      expect(controller.failedComponent, isNull);
      expect(controller.retryLabel, '重试未完成组件');
    });

    test('retry clears the failure and tries again', () async {
      runtime.installError = StateError('disk gone');
      await started();
      await controller.install();
      runtime.installError = null;

      await controller.retry();

      expect(runtime.installCalls, 2);
      expect(controller.error, isNull);
      expect(controller.failedComponent, isNull);
    });
  });

  group('existing downloads', () {
    test('nothing found says so and changes nothing', () async {
      await started();

      await controller.scanExisting();

      expect(storage.discoverCalls, 1);
      expect(controller.existingModelMessage, AsrFolderText.notFound);
      expect(controller.scanningExisting, isFalse);
    });

    test('shows the scanning message while looking', () async {
      await started();
      final messages = <String?>[];
      controller.addListener(
        () => messages.add(controller.existingModelMessage),
      );

      await controller.scanExisting();

      expect(messages, contains(AsrFolderText.scanning));
    });

    test('a found ready environment is used without downloading', () async {
      await started();
      storage.discovered = setupMoved(target: '/old/ASRRuntime');
      runtime.status = setupStatus(ready: true);

      await controller.scanExisting();

      expect(
        controller.existingModelMessage,
        '已启用已有环境：/old/ASRRuntime。组件已就绪，本次没有下载。',
      );
      expect(controller.ready, isTrue);
      expect(controller.showsExistingModels, isTrue);
      expect(runtime.installCalls, 0);
    });

    test('components lifted from a nested copy are named (D-048)', () async {
      await started();
      storage.discovered = const AsrManagedStorageMoveResult(
        sourceRoot: '/old/ASRRuntime/LyricForge/ASRRuntime',
        targetRoot: '/old/ASRRuntime',
        copiedBytes: 0,
        copiedFiles: 0,
        moved: true,
        adoptedExisting: true,
        movedUnits: [AsrRuntimeUnit.whisperModel],
        otherRoots: ['/elsewhere/ASRRuntime'],
      );
      runtime.status = setupStatus(ready: true);

      await controller.scanExisting();

      final message = controller.existingModelMessage!;
      expect(message, startsWith('已启用已有环境：/old/ASRRuntime。'));
      expect(message, contains('Whisper large-v3 模型'));
      expect(message, contains('没有复制或重新下载'));
      expect(message, contains('/elsewhere/ASRRuntime'));
    });

    test('a partial environment says how much is ready', () async {
      await started();
      storage.discovered = setupMoved(target: '/old/ASRRuntime');

      await controller.scanExisting();

      expect(controller.existingModelMessage, contains('当前 1/2 个组件就绪'));
      expect(controller.existingModelMessage, contains('/old/ASRRuntime'));
    });

    test('a failed scan shows the error', () async {
      await started();
      storage.discoverError = StateError('no access');

      await controller.scanExisting();

      expect(controller.error, startsWith('识别已有模型失败：'));
      expect(controller.scanningExisting, isFalse);
    });

    test('no scan while the runtime downloads elsewhere', () async {
      await started();
      runtime.installing = true;

      expect(controller.canUseExisting, isFalse);
      await controller.scanExisting();

      expect(storage.discoverCalls, 0);
    });

    test('no scan while still inspecting', () {
      controller = build();
      expect(controller.canUseExisting, isFalse);
    });

    test('a pasted path is adopted', () async {
      await started();

      await controller.adoptExistingPath('/Volumes/Models');

      expect(storage.adoptedPaths, ['/Volumes/Models']);
      expect(controller.existingModelMessage, contains('/Volumes/Models'));
      expect(controller.scanningExisting, isFalse);
    });

    test('a blank path is ignored', () async {
      await started();

      await controller.adoptExistingPath('   ');

      expect(storage.adoptedPaths, isEmpty);
    });

    test('an unrecognised path keeps the folder and explains', () async {
      await started();
      storage.adoptError = StateError('not a runtime');

      await controller.adoptExistingPath('/tmp');

      expect(controller.existingModelMessage, AsrFolderText.pathNotRecognised);
      expect(controller.error, startsWith('识别已有模型失败：'));
    });
  });

  group('storage location', () {
    test('a move returns its result for the snack bar', () async {
      await started();

      final result = await controller.moveStorage('/new');

      expect(storage.movedTo, ['/new']);
      expect(result?.targetRoot, '/new/LyricForge/ASRRuntime');
      expect(controller.loading, isFalse);
    });

    test('moving onto an existing environment notes it', () async {
      await started();
      storage.moveResult = setupMoved(
        target: '/disk/LyricForge/ASRRuntime',
        adoptedExisting: true,
      );

      final result = await controller.moveStorage('/disk');

      expect(result?.adoptedExisting, isTrue);
      expect(
        controller.existingModelMessage,
        '已识别并使用现有识别环境：/disk/LyricForge/ASRRuntime；没有复制或删除旧目录。',
      );
    });

    test('a move that changed nothing returns null', () async {
      await started();
      storage.moveResult = setupMoved(moved: false);

      expect(await controller.moveStorage('/same'), isNull);
      expect(controller.error, isNull);
    });

    test('a failed move shows the error and stops loading', () async {
      await started();
      storage.moveError = StateError('read only');

      expect(await controller.moveStorage('/ro'), isNull);
      expect(controller.error, startsWith('更改模型存储位置失败：'));
      expect(controller.loading, isFalse);
    });

    test('no move while downloading', () async {
      await started();
      runtime.installing = true;

      expect(controller.canMoveStorage, isFalse);
      expect(await controller.moveStorage('/new'), isNull);
      expect(storage.movedTo, isEmpty);
    });
  });

  group('advanced settings', () {
    test('a complete plan is saved before it is used', () async {
      await started();

      await controller.applyAdvanced(setupConfigured);

      expect(store.saved, [setupConfigured]);
      expect(controller.config, setupConfigured);
      expect(runtime.inspected.last, setupConfigured);
    });

    test('an incomplete plan is used without saving', () async {
      await started();
      const proxyOnly = TranscriptionConfig(
        mode: TranscriptionMode.whisperOnly,
        whisperExecutable: 'whisper-cli',
        modelPath: '',
      );

      await controller.applyAdvanced(proxyOnly);

      expect(store.saved, isEmpty);
      expect(controller.config.mode, TranscriptionMode.whisperOnly);
    });

    test('a failed save keeps the old plan and shows why', () async {
      await started();
      store.saveError = StateError('read only');
      final before = controller.config;

      await controller.applyAdvanced(setupConfigured);

      expect(controller.config, before);
      expect(controller.error, startsWith('保存本地识别设置失败：'));
    });
  });

  group('actions', () {
    test('downloading shows only pause', () {
      expect(
        AsrRuntimeSetupController.actionsFor(
          installing: true,
          paused: false,
          ready: false,
        ),
        [AsrSetupAction.pause],
      );
    });

    test('paused shows later and resume', () {
      expect(
        AsrRuntimeSetupController.actionsFor(
          installing: false,
          paused: true,
          ready: true,
        ),
        [AsrSetupAction.later, AsrSetupAction.resume],
      );
    });

    test('idle shows advanced, refresh and install or start', () {
      expect(
        AsrRuntimeSetupController.actionsFor(
          installing: false,
          paused: false,
          ready: false,
        ),
        [
          AsrSetupAction.advanced,
          AsrSetupAction.refresh,
          AsrSetupAction.install,
        ],
      );
      expect(
        AsrRuntimeSetupController.actionsFor(
          installing: false,
          paused: false,
          ready: true,
        ).last,
        AsrSetupAction.start,
      );
    });

    test('refresh and install wait for the inspection', () async {
      controller = build();
      expect(controller.isEnabled(AsrSetupAction.refresh), isFalse);
      expect(controller.isEnabled(AsrSetupAction.install), isFalse);
      expect(controller.isEnabled(AsrSetupAction.advanced), isTrue);

      controller.start();
      await settleSetup();

      expect(controller.isEnabled(AsrSetupAction.refresh), isTrue);
      expect(controller.isEnabled(AsrSetupAction.install), isTrue);
      expect(controller.isEnabled(AsrSetupAction.pause), isFalse);
      expect(controller.isEnabled(AsrSetupAction.resume), isFalse);
    });
  });

  group('dispose', () {
    test('a dialog closed during inspection is not notified', () async {
      runtime.pendingInspect = Completer<void>();
      controller = build()..start();
      await settleSetup();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.dispose();
      runtime.pendingInspect!.complete();
      await settleSetup();

      expect(controller.isDisposed, isTrue);
      expect(notified, 0);
    });

    test('progress after dispose is ignored', () async {
      await started();
      controller.dispose();

      runtime.progress.add(
        const AsrRuntimeInstallProgress(progress: 0.1, message: 'late'),
      );
      await settleSetup();

      expect(controller.installProgress, isNull);
    });
  });
}
