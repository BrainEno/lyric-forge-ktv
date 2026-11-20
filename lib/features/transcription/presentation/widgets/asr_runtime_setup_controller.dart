import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_managed_storage_service.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/asr_storage_preflight_service.dart';
import '../../domain/services/transcription_settings_store.dart';
import '../asr_folder_text.dart';
import 'asr_runtime_setup_text.dart';

// The flows behind the first-run speech recognition setup (audit I-03).
//
// The dialog used to be one State object of about 420 lines of flows plus a
// 200-line build method and five private cards: the services, fourteen
// fields of progress and error state, the install, pause, existing-model,
// storage-move and advanced-settings flows. This controller takes the flows,
// so the dialog keeps only what needs a BuildContext (the folder picker, the
// path dialog, the advanced settings dialog and the snack bar) and lays out
// the cards in asr_runtime_setup_cards.dart. It follows the settings page's
// controller (audit C-03); unlike that one it does not save the plan after an
// install, because the caller receives it when the user taps 开始使用.

/// The buttons of the setup dialog, in the order they appear.
enum AsrSetupAction {
  /// Stops the running download.
  pause,

  /// Closes the dialog with a paused download.
  later,

  /// Continues a paused download.
  resume,

  /// Opens the advanced settings dialog.
  advanced,

  /// Inspects the computer again.
  refresh,

  /// Checks what is there and downloads what is missing.
  install,

  /// Closes the dialog with the ready plan.
  start,
}

/// State and flows of the first-run speech recognition setup.
///
/// One instance belongs to one dialog. Every flow checks [isDisposed] after
/// each await, so a dialog that closes while an inspection, a scan or a move
/// is still running does not notify a listener that is gone.
class AsrRuntimeSetupController extends ChangeNotifier {
  AsrRuntimeSetupController({
    required AsrRuntimeManager runtimeManager,
    required AsrStoragePreflightService storagePreflightService,
    required AsrManagedStorageService managedStorageService,
    required TranscriptionSettingsStore settingsStore,
    TranscriptionConfig? initialConfig,
  }) : _runtimeManager = runtimeManager,
       _storagePreflightService = storagePreflightService,
       _managedStorageService = managedStorageService,
       _settingsStore = settingsStore,
       _config = initialConfig ?? defaultConfig;

  /// The plan before the user picked anything: both engines, automatic
  /// hardware profile, the bundled executables and no model yet.
  static const defaultConfig = TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    profilePreference: TranscriptionProfilePreference.automatic,
    qwenExecutable: 'qwen3-asr',
    whisperExecutable: 'whisper-cli',
    modelPath: '',
  );

  final AsrRuntimeManager _runtimeManager;
  final AsrStoragePreflightService _storagePreflightService;
  final AsrManagedStorageService _managedStorageService;
  final TranscriptionSettingsStore _settingsStore;

  StreamSubscription<AsrRuntimeInstallProgress>? _progressSubscription;
  bool _disposed = false;

  TranscriptionConfig _config;
  AsrRuntimeStatus? _status;
  AsrStoragePreflightResult? _storage;
  AsrRuntimeInstallProgress? _installProgress;
  bool _loading = true;
  bool _installing = false;
  bool _paused = false;
  bool _pauseRequested = false;
  bool _scanningExisting = false;
  String? _existingModelMessage;
  AsrRuntimeComponent? _failedComponent;
  String? _error;

  TranscriptionConfig get config => _config;
  AsrRuntimeStatus? get status => _status;
  AsrStoragePreflightResult? get storage => _storage;
  AsrRuntimeInstallProgress? get installProgress => _installProgress;
  bool get loading => _loading;
  bool get installing => _installing;
  bool get paused => _paused;
  bool get scanningExisting => _scanningExisting;
  String? get existingModelMessage => _existingModelMessage;
  AsrRuntimeComponent? get failedComponent => _failedComponent;
  String? get error => _error;
  bool get isDisposed => _disposed;

  /// Every component the plan needs is installed.
  bool get ready => _status?.isReady == true;

  /// The last space check says the install would not fit.
  bool get storageBlocked => _storage?.canInstall == false;

  /// The download stopped with an error rather than a pause.
  bool get failed => _error != null && !_paused;

  /// The progress card is worth showing: something is or was downloading.
  bool get showsProgress =>
      _installProgress != null && (_installing || _paused || _error != null);

  /// The existing-model card: until the plan is ready, or while it still has
  /// something to say about an environment it took over.
  bool get showsExistingModels => !ready || _existingModelMessage != null;

  /// The existing-model buttons may start a scan or open a picker.
  bool get canUseExisting =>
      !_loading &&
      !_installing &&
      !_scanningExisting &&
      !_runtimeManager.isInstalling;

  /// The managed environment may move to another folder.
  bool get canMoveStorage => !_installing && !_runtimeManager.isInstalling;

  /// The quality plan may change; not while downloading.
  bool get canChangeMode => !_installing;

  /// The dialog may close; a running download has to be paused first.
  bool get canClose => !_installing;

  /// The buttons the dialog shows now; see [actionsFor].
  List<AsrSetupAction> get actions =>
      actionsFor(installing: _installing, paused: _paused, ready: ready);

  /// While downloading only 暂停; once paused 以后继续 and 继续; otherwise
  /// 高级设置 and 重新检测, then 校验并准备 until the plan is ready and
  /// 开始使用 after.
  static List<AsrSetupAction> actionsFor({
    required bool installing,
    required bool paused,
    required bool ready,
  }) {
    if (installing) return const [AsrSetupAction.pause];
    if (paused) return const [AsrSetupAction.later, AsrSetupAction.resume];
    return [
      AsrSetupAction.advanced,
      AsrSetupAction.refresh,
      ready ? AsrSetupAction.start : AsrSetupAction.install,
    ];
  }

  /// Whether [action] does anything now. A button that is shown but not
  /// enabled is greyed out.
  bool isEnabled(AsrSetupAction action) => switch (action) {
    AsrSetupAction.pause => _installing,
    AsrSetupAction.later || AsrSetupAction.resume => _paused,
    AsrSetupAction.advanced || AsrSetupAction.start => true,
    AsrSetupAction.refresh => !_loading,
    AsrSetupAction.install => !_loading && !storageBlocked,
  };

  /// The retry button's label, naming the component that failed.
  String get retryLabel => AsrSetupText.retryLabel(_failedComponent);

  /// Follows install progress and inspects the computer.
  void start() {
    _progressSubscription ??= _runtimeManager.progressStream.listen((value) {
      _set(() => _installProgress = value);
    });
    unawaited(_refresh());
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

  /// Repairs the plan's paths and inspects components and space.
  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    if (_disposed) return;
    _set(() {
      _loading = true;
      _error = null;
    });

    try {
      final repaired = await _runtimeManager.repair(_config);
      final status = await _runtimeManager.inspect(repaired);
      final storage = await _storagePreflightService.inspect(
        repaired,
        runtimeStatus: status,
      );
      _set(() {
        _config = repaired;
        _status = status;
        _storage = storage;
      });
    } on TranscriptionException catch (error) {
      _set(() => _error = error.toString());
    } catch (error) {
      _set(() => _error = AsrSetupText.inspectFailed(error));
    } finally {
      _set(() => _loading = false);
    }
  }

  /// Switches the quality plan and inspects again; nothing is saved yet.
  Future<void> changeMode(TranscriptionMode mode) async {
    if (!canChangeMode || mode == _config.mode) return;
    _set(() => _config = _config.copyWith(mode: mode));
    await _refresh();
  }

  Future<bool> _ensureStorageBeforeInstall() async {
    final storage = await _storagePreflightService.inspect(
      _config,
      runtimeStatus: _status,
    );
    if (_disposed) return false;
    _set(() => _storage = storage);
    if (storage.canInstall) return true;

    _set(() => _error = AsrSetupText.storageShortfall(storage));
    return false;
  }

  /// Checks what is already there and downloads only what is missing.
  Future<void> install() => _install();

  /// Continues a paused download where it stopped.
  Future<void> resume() => _install(resume: true);

  /// Tries the components that failed again, keeping the finished ones.
  Future<void> retry() => _install(resume: true);

  Future<void> _install({bool resume = false}) async {
    if (!await _ensureStorageBeforeInstall()) return;

    var completed = false;
    _set(() {
      _installing = true;
      _paused = false;
      _pauseRequested = false;
      _failedComponent = null;
      _error = null;
      if (!resume || _installProgress == null) {
        _installProgress = const AsrRuntimeInstallProgress(
          progress: 0,
          message: AsrSetupText.checkingExisting,
          phase: AsrRuntimeInstallPhase.checkingExisting,
        );
      }
    });

    try {
      final installed = await _runtimeManager.installRecommended(_config);
      completed = true;
      if (_disposed) return;
      _set(() => _config = installed);
      await _refresh();
    } on TranscriptionException catch (error) {
      await _installFailed(error.toString());
    } catch (error) {
      await _installFailed(AsrSetupText.installFailed(error));
    } finally {
      _set(() {
        _installing = false;
        _pauseRequested = false;
        if (completed) _installProgress = null;
      });
    }
  }

  /// A cancelled download is a pause the user asked for, not a failure. A
  /// real failure inspects again first, so the component list shows what is
  /// left, and then names the component that was downloading.
  Future<void> _installFailed(String message) async {
    if (_disposed) return;
    if (_pauseRequested) {
      _set(() {
        _paused = true;
        _error = null;
      });
      return;
    }
    final failedComponent = _installProgress?.component;
    await _refresh();
    _set(() {
      _failedComponent = failedComponent;
      _error = message;
    });
  }

  /// Stops the running download; [resume] continues it later.
  Future<void> pause() async {
    if (!_installing) return;
    _set(() => _pauseRequested = true);
    await _runtimeManager.cancel();
  }

  /// Looks for an earlier download in the usual places and uses it.
  Future<void> scanExisting() async {
    if (!canUseExisting) return;
    _set(() {
      _scanningExisting = true;
      _error = null;
      _existingModelMessage = AsrFolderText.scanning;
    });
    try {
      final result = await _managedStorageService.discoverAndAdoptExisting();
      if (_disposed) return;
      if (result == null) {
        _set(() => _existingModelMessage = AsrFolderText.notFound);
        return;
      }
      await _afterExistingRootAdopted(result);
    } catch (error) {
      _set(() => _error = AsrSetupText.existingFailed(error));
    } finally {
      _set(() => _scanningExisting = false);
    }
  }

  /// Uses the environment found at a pasted or picked [path].
  Future<void> adoptExistingPath(String path) async {
    if (path.trim().isEmpty ||
        _installing ||
        _scanningExisting ||
        _runtimeManager.isInstalling) {
      return;
    }
    _set(() {
      _scanningExisting = true;
      _error = null;
      _existingModelMessage = AsrFolderText.checkingPath(path);
    });
    try {
      final result = await _managedStorageService.adoptExistingAt(path);
      await _afterExistingRootAdopted(result);
    } catch (error) {
      _set(() {
        _existingModelMessage = AsrFolderText.pathNotRecognised;
        _error = AsrSetupText.existingFailed(error);
      });
    } finally {
      _set(() => _scanningExisting = false);
    }
  }

  Future<void> _afterExistingRootAdopted(
    AsrManagedStorageMoveResult result,
  ) async {
    if (_disposed) return;
    // 此步骤不会下载: only the components below the found root are inspected.
    _set(() => _existingModelMessage = AsrSetupText.adopting(result.targetRoot));
    final repaired = await _runtimeManager.repair(_config);
    if (_disposed) return;
    _set(() => _config = repaired);
    await _refresh();
    if (_disposed) return;
    _set(() {
      _existingModelMessage = AsrSetupText.adopted(result.targetRoot, _status);
    });
  }

  /// Moves the managed environment below [parent]. Returns the result when
  /// the environment moved, so the dialog can say so; null when the move did
  /// not start, failed (the failure is in [error]) or changed nothing.
  Future<AsrManagedStorageMoveResult?> moveStorage(String parent) async {
    if (!canMoveStorage || parent.trim().isEmpty) return null;
    _set(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _managedStorageService.moveToParent(parent);
      final repaired = await _runtimeManager.repair(_config);
      if (_disposed) return null;
      _set(() {
        _config = repaired;
        if (result.adoptedExisting) {
          _existingModelMessage = AsrSetupText.movedOntoExisting(
            result.targetRoot,
          );
        }
      });
      await _refresh();
      if (_disposed || !result.moved) return null;
      return result;
    } catch (error) {
      _set(() => _error = AsrSetupText.moveFailed(error));
      return null;
    } finally {
      if (_loading) _set(() => _loading = false);
    }
  }

  /// Takes the plan from the advanced settings dialog. A complete plan is
  /// saved first; if saving fails the old plan stays and the error shows.
  Future<void> applyAdvanced(TranscriptionConfig updated) async {
    if (updated.isConfigured) {
      try {
        await _settingsStore.save(updated);
      } catch (error) {
        _set(() => _error = AsrSetupText.saveFailed(error));
        return;
      }
    }

    if (_disposed) return;
    _set(() => _config = updated);
    await _refresh();
  }
}
