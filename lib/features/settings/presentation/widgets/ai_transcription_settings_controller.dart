import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/services/asr_managed_storage_service.dart';
import '../../../transcription/domain/services/asr_runtime_manager.dart';
import '../../../transcription/domain/services/asr_storage_preflight_service.dart';
import '../../../transcription/domain/services/transcription_settings_store.dart';
import 'ai_transcription_settings_cards.dart';

// The flows behind 设置 → 本地识别 (audit C-03, after SE-04).
//
// The section used to be one State object of about 590 lines: it held the
// four services, eighteen fields of progress and error state, the install,
// pause, existing-model, storage-move and delete flows, the confirmation
// dialogs and the build method. The cards had already moved out
// (ai_transcription_settings_cards.dart); this file takes the flows, so the
// section keeps only what needs a BuildContext — dialogs, the folder picker,
// the snack bar — and the layout of the four cards.
//
// The controller only talks to the domain services. It does not import the
// transcription feature's presentation layer, which is why the four messages
// of the existing-model flow arrive as [AsrExistingModelTexts].

/// The messages of the "reuse an existing download" flow, supplied by the
/// section from `AsrFolderText` so they stay shared with the setup dialog.
@immutable
class AsrExistingModelTexts {
  const AsrExistingModelTexts({
    required this.scanning,
    required this.notFound,
    required this.pathNotRecognised,
    required this.checkingPath,
  });

  final String scanning;
  final String notFound;
  final String pathNotRecognised;
  final String Function(String path) checkingPath;
}

/// Measures the bytes below a folder; null when it cannot be read.
typedef AsrDirectorySizer = Future<int?> Function(String path);

/// State and flows of the local speech recognition settings.
///
/// One instance belongs to one section. Every flow checks [isDisposed]
/// after each await, so a section that closes while a download, a move or a
/// scan is still running does not notify a listener that is gone.
class AiTranscriptionSettingsController extends ChangeNotifier {
  AiTranscriptionSettingsController({
    required TranscriptionSettingsStore settingsStore,
    required AsrRuntimeManager runtimeManager,
    required AsrStoragePreflightService storagePreflightService,
    required AsrManagedStorageService managedStorageService,
    required AsrExistingModelTexts texts,
    AsrDirectorySizer? directorySize,
  }) : _settingsStore = settingsStore,
       _runtimeManager = runtimeManager,
       _storagePreflightService = storagePreflightService,
       _managedStorageService = managedStorageService,
       _texts = texts,
       _directorySize = directorySize ?? measureDirectory;

  /// The plan shown before anything was saved: both engines, automatic
  /// hardware profile, the bundled executables and no model yet.
  static const defaultConfig = TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    profilePreference: TranscriptionProfilePreference.automatic,
    qwenExecutable: 'qwen3-asr',
    whisperExecutable: 'whisper-cli',
    modelPath: '',
  );

  final TranscriptionSettingsStore _settingsStore;
  final AsrRuntimeManager _runtimeManager;
  final AsrStoragePreflightService _storagePreflightService;
  final AsrManagedStorageService _managedStorageService;
  final AsrExistingModelTexts _texts;
  final AsrDirectorySizer _directorySize;

  StreamSubscription<AsrRuntimeInstallProgress>? _progressSubscription;
  bool _disposed = false;

  TranscriptionConfig? _config;
  AsrRuntimeStatus? _status;
  AsrStoragePreflightResult? _storage;
  AsrManagedStorageLocation? _managedStorageLocation;
  AsrRuntimeInstallProgress? _progress;
  int? _managedBytes;
  bool _loading = true;
  bool _installing = false;
  bool _paused = false;
  bool _pauseRequested = false;
  bool _deleting = false;
  bool _movingStorage = false;
  bool _scanningExisting = false;
  String? _existingModelMessage;
  int _movingCopiedBytes = 0;
  int _movingTotalBytes = 0;
  AsrRuntimeComponent? _failedComponent;
  String? _error;

  /// The saved plan, or [defaultConfig] before one was loaded.
  TranscriptionConfig get config => _config ?? defaultConfig;
  AsrRuntimeStatus? get status => _status;
  AsrStoragePreflightResult? get storage => _storage;
  AsrManagedStorageLocation? get managedStorageLocation =>
      _managedStorageLocation;
  AsrRuntimeInstallProgress? get progress => _progress;
  int? get managedBytes => _managedBytes;
  bool get loading => _loading;
  bool get installing => _installing;
  bool get paused => _paused;
  bool get deleting => _deleting;
  bool get movingStorage => _movingStorage;
  bool get scanningExisting => _scanningExisting;
  String? get existingModelMessage => _existingModelMessage;
  int get movingCopiedBytes => _movingCopiedBytes;
  int get movingTotalBytes => _movingTotalBytes;
  AsrRuntimeComponent? get failedComponent => _failedComponent;
  String? get error => _error;
  bool get isDisposed => _disposed;

  /// Every component the plan needs is installed.
  bool get ready => _status?.isReady == true;

  /// The last space check says the install would not fit.
  bool get storageBlocked => _storage?.canInstall == false;

  /// A flow is running; the cards disable their buttons.
  bool get busy =>
      _loading ||
      _installing ||
      _paused ||
      _deleting ||
      _movingStorage ||
      _scanningExisting;

  /// Nothing here or in the shared runtime manager is running, so a flow
  /// that changes the environment may start.
  bool get canStartExclusive => !busy && !_runtimeManager.isInstalling;

  /// Follows install progress and loads the saved plan.
  void start() {
    _progressSubscription ??= _runtimeManager.progressStream.listen((value) {
      _set(() => _progress = value);
    });
    unawaited(refresh(loadFromStore: true));
  }

  @override
  void dispose() {
    _disposed = true;
    _progressSubscription?.cancel();
    super.dispose();
  }

  void _set(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  /// Repairs the plan's paths and inspects components, space and storage.
  Future<void> refresh({bool loadFromStore = false}) async {
    if (_disposed) return;
    _set(() {
      _loading = true;
      _error = null;
    });

    try {
      final stored = loadFromStore ? await _settingsStore.load() : _config;
      final base = stored ?? defaultConfig;
      final repaired = await _runtimeManager.repair(base);
      final status = await _runtimeManager.inspect(repaired);
      final storage = await _storagePreflightService.inspect(
        repaired,
        runtimeStatus: status,
      );
      final location = await _managedStorageService.inspect();
      final bytes = await _directorySize(status.managedRoot);
      _set(() {
        _config = repaired;
        _status = status;
        _storage = storage;
        _managedStorageLocation = location;
        _managedBytes = bytes;
      });
    } on TranscriptionException catch (error) {
      _set(() => _error = error.toString());
    } catch (error) {
      _set(() => _error = '检测识别环境失败：$error');
    } finally {
      _set(() => _loading = false);
    }
  }

  /// Saves [config] when it is usable and inspects again.
  Future<void> save(TranscriptionConfig config) async {
    if (config.isConfigured) await _settingsStore.save(config);
    if (_disposed) return;
    _set(() => _config = config);
    await refresh();
  }

  /// Switches the quality plan; a custom hardware profile stays custom.
  Future<void> changeMode(TranscriptionMode mode) async {
    final current = config;
    final updated = current.copyWith(
      mode: mode,
      profilePreference:
          current.profilePreference == TranscriptionProfilePreference.custom
          ? TranscriptionProfilePreference.custom
          : TranscriptionProfilePreference.automatic,
    );
    await save(updated);
  }

  Future<bool> _ensureStorageBeforeInstall(TranscriptionConfig config) async {
    final storage = await _storagePreflightService.inspect(
      config,
      runtimeStatus: _status,
    );
    if (_disposed) return false;
    _set(() => _storage = storage);
    if (storage.canInstall) return true;

    _set(() {
      _error =
          '磁盘空间不足：本次安装建议至少可用 '
          '${AsrSettingsText.formatBytes(storage.requiredAdditionalBytes)}，'
          '当前可用 ${AsrSettingsText.formatBytes(storage.availableBytes)}，'
          '还差 ${AsrSettingsText.formatBytes(storage.shortfallBytes)}。'
          '请释放空间后重新检测。';
    });
    return false;
  }

  /// Checks what is already there and downloads only what is missing.
  Future<void> install() => _install();

  /// Continues a paused download where it stopped.
  Future<void> resume() => _install(resume: true);

  /// Tries the components that failed again, keeping the finished ones.
  Future<void> retry() => _install(resume: true);

  Future<void> _install({bool resume = false}) async {
    final current = config;
    if (!await _ensureStorageBeforeInstall(current)) return;

    var completed = false;
    _set(() {
      _installing = true;
      _paused = false;
      _pauseRequested = false;
      _failedComponent = null;
      _error = null;
      if (!resume || _progress == null) {
        _progress = const AsrRuntimeInstallProgress(
          progress: 0,
          message: '正在检查已有组件并校验本地文件；只有缺失或校验失败的文件才会下载',
          phase: AsrRuntimeInstallPhase.checkingExisting,
        );
      }
    });

    try {
      final installed = await _runtimeManager.installRecommended(current);
      await _settingsStore.save(installed);
      completed = true;
      if (_disposed) return;
      _set(() => _config = installed);
      await refresh();
    } on TranscriptionException catch (error) {
      _installFailed(error.toString());
    } catch (error) {
      _installFailed('安装识别环境失败：$error');
    } finally {
      _set(() {
        _installing = false;
        _pauseRequested = false;
        if (completed) _progress = null;
      });
    }
  }

  /// A cancelled download is a pause the user asked for, not a failure.
  void _installFailed(String message) {
    if (_pauseRequested) {
      _set(() {
        _paused = true;
        _error = null;
      });
    } else {
      _set(() {
        _failedComponent = _progress?.component;
        _error = message;
      });
    }
  }

  /// Stops the running download; [resume] continues it later.
  Future<void> pause() async {
    if (!_installing) return;
    _set(() => _pauseRequested = true);
    await _runtimeManager.cancel();
  }

  /// Looks for an earlier download in the usual places and uses it.
  Future<void> scanExisting() async {
    if (!canStartExclusive) return;
    _set(() {
      _scanningExisting = true;
      _error = null;
      _existingModelMessage = _texts.scanning;
    });
    try {
      final result = await _managedStorageService.discoverAndAdoptExisting();
      if (_disposed) return;
      if (result == null) {
        _set(() => _existingModelMessage = _texts.notFound);
        return;
      }
      await _afterExistingRootAdopted(result);
    } catch (error) {
      _set(() => _error = '识别已有模型失败：$error');
    } finally {
      _set(() => _scanningExisting = false);
    }
  }

  /// Uses the environment found at a pasted or picked [path].
  Future<void> adoptExistingPath(String path) async {
    if (!canStartExclusive || path.trim().isEmpty) return;
    _set(() {
      _scanningExisting = true;
      _error = null;
      _existingModelMessage = _texts.checkingPath(path);
    });
    try {
      final result = await _managedStorageService.adoptExistingAt(path);
      await _afterExistingRootAdopted(result);
    } catch (error) {
      _set(() {
        _existingModelMessage = _texts.pathNotRecognised;
        _error = '识别已有模型失败：$error';
      });
    } finally {
      _set(() => _scanningExisting = false);
    }
  }

  Future<void> _afterExistingRootAdopted(
    AsrManagedStorageMoveResult result,
  ) async {
    if (_disposed) return;
    _set(() {
      _existingModelMessage = '已找到已有环境：${result.targetRoot}。正在重新检测组件；此步骤不会下载。';
    });
    final repaired = await _runtimeManager.repair(config);
    if (repaired.isConfigured) {
      await _settingsStore.save(repaired);
    }
    if (_disposed) return;
    _set(() => _config = repaired);
    await refresh();
    if (_disposed) return;
    _set(() {
      _existingModelMessage = adoptedMessage(result.targetRoot, _status);
    });
  }

  /// What the existing-model card says after an environment at [root] was
  /// taken over, given the [status] inspected afterwards.
  static String adoptedMessage(String root, AsrRuntimeStatus? status) {
    if (status == null) {
      return '已找到并使用已有环境：$root。请重新检测确认各组件状态。';
    }
    if (status.isReady) {
      return '已启用已有环境：$root。组件已就绪，本次没有下载；'
          '之后执行校验/修复时仍会核对模型 SHA-256。';
    }
    return '已找到并使用已有环境：$root。当前 '
        '${status.readyCount}/${status.components.length} 个组件就绪；'
        '点击“校验并补齐缺失组件”时会先校验已有文件，只有下面列出的缺失或'
        '校验失败组件才会下载。';
  }

  /// The snack bar text after a move of the managed environment finished.
  static String movedMessage(AsrManagedStorageMoveResult result) {
    if (result.adoptedExisting) {
      return '已识别并使用现有的识别环境：${result.targetRoot}；旧目录未删除。';
    }
    if (result.oldRootRetained) {
      return '识别环境已切换；旧目录 ${result.sourceRoot} 未能自动删除，请手工清理。';
    }
    return '识别环境已迁移到 ${result.targetRoot}';
  }

  /// Moves the managed environment below [parent], or back to the default
  /// location when [useDefault] is set. The section asks for confirmation
  /// first. Returns the result when the move finished, null when it did not
  /// start or failed (the failure is in [error]).
  Future<AsrManagedStorageMoveResult?> moveStorage({
    String? parent,
    bool useDefault = false,
  }) async {
    if (!canStartExclusive) return null;
    if (!useDefault && (parent == null || parent.trim().isEmpty)) return null;

    _set(() {
      _movingStorage = true;
      _movingCopiedBytes = 0;
      _movingTotalBytes = _managedBytes ?? 0;
      _error = null;
    });
    try {
      final result = useDefault
          ? await _managedStorageService.moveToDefault(
              onProgress: _onStorageMoveProgress,
            )
          : await _managedStorageService.moveToParent(
              parent!,
              onProgress: _onStorageMoveProgress,
            );
      final repaired = await _runtimeManager.repair(config);
      // Changing the storage root must work before the environment is fully
      // installed. The settings store intentionally rejects incomplete
      // configurations, so only persist repaired paths once they are usable;
      // the managed-root pointer above is already the source of truth for
      // the new location and refresh will rediscover whatever exists there.
      if (repaired.isConfigured) {
        await _settingsStore.save(repaired);
      }
      if (_disposed) return null;
      _set(() {
        _config = repaired;
        if (result.adoptedExisting) {
          _existingModelMessage =
              '已识别并使用现有识别环境：${result.targetRoot}；未复制或删除旧目录。';
        }
      });
      await refresh();
      return _disposed ? null : result;
    } catch (error) {
      _set(() => _error = '迁移识别环境失败：$error');
      return null;
    } finally {
      _set(() {
        _movingStorage = false;
        _movingCopiedBytes = 0;
        _movingTotalBytes = 0;
      });
    }
  }

  void _onStorageMoveProgress(int copiedBytes, int totalBytes) {
    _set(() {
      _movingCopiedBytes = copiedBytes;
      _movingTotalBytes = totalBytes;
    });
  }

  /// Deletes the managed Qwen and Whisper models, keeping the runtimes and
  /// any model the user pointed at by hand; with [reinstall], downloads the
  /// current plan's models again. The section asks for confirmation first.
  Future<void> deleteModels({required bool reinstall}) async {
    final status = _status;
    if (status == null || _disposed) return;

    _set(() {
      _deleting = true;
      _error = null;
    });

    try {
      final models = Directory(
        '${status.managedRoot}${Platform.pathSeparator}models',
      );
      if (await models.exists()) {
        await models.delete(recursive: true);
      }
      if (_disposed) return;
      await refresh();
      if (reinstall && !_disposed) {
        await install();
      }
    } catch (error) {
      _set(() => _error = '删除模型失败：$error');
    } finally {
      _set(() => _deleting = false);
    }
  }

  /// Total bytes of the files below [path]: null for an empty path or an
  /// unreadable folder, 0 for a folder that does not exist yet.
  static Future<int?> measureDirectory(String path) async {
    if (path.trim().isEmpty) return null;
    final root = Directory(path);
    if (!await root.exists()) return 0;

    var total = 0;
    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return null;
    }
  }
}
