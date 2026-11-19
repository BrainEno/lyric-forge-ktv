import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/services/asr_managed_storage_service.dart';
import '../../../transcription/domain/services/asr_runtime_manager.dart';
import '../../../transcription/domain/services/asr_storage_preflight_service.dart';
import '../../../transcription/domain/services/transcription_settings_store.dart';
import '../../../transcription/presentation/transcription_screen_dependencies.dart';
import '../../../transcription/presentation/widgets/asr_existing_model_actions.dart';
import '../../../transcription/presentation/widgets/transcription_config_dialog.dart';
import 'ai_transcription_settings_cards.dart';

class AiTranscriptionSettingsSection extends StatefulWidget {
  final AsrRuntimeSetupDependencies dependencies;

  const AiTranscriptionSettingsSection({super.key, required this.dependencies});

  @override
  State<AiTranscriptionSettingsSection> createState() =>
      _AiTranscriptionSettingsSectionState();
}

class _AiTranscriptionSettingsSectionState
    extends State<AiTranscriptionSettingsSection> {
  late final TranscriptionSettingsStore _settingsStore;
  late final AsrRuntimeManager _runtimeManager;
  late final AsrStoragePreflightService _storagePreflightService;
  late final AsrManagedStorageService _managedStorageService;

  StreamSubscription<AsrRuntimeInstallProgress>? _progressSubscription;
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

  static const _defaultConfig = TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    profilePreference: TranscriptionProfilePreference.automatic,
    qwenExecutable: 'qwen3-asr',
    whisperExecutable: 'whisper-cli',
    modelPath: '',
  );

  bool get _busy =>
      _loading ||
      _installing ||
      _paused ||
      _deleting ||
      _movingStorage ||
      _scanningExisting;

  @override
  void initState() {
    super.initState();
    _settingsStore = widget.dependencies.transcriptionSettingsStore;
    _runtimeManager = widget.dependencies.asrRuntimeManager;
    _storagePreflightService = widget.dependencies.asrStoragePreflightService;
    _managedStorageService = widget.dependencies.asrManagedStorageService;
    _progressSubscription = _runtimeManager.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() => _progress = progress);
    });
    unawaited(_refresh(loadFromStore: true));
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool loadFromStore = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final stored = loadFromStore ? await _settingsStore.load() : _config;
      final base = stored ?? _defaultConfig;
      final repaired = await _runtimeManager.repair(base);
      final status = await _runtimeManager.inspect(repaired);
      final storage = await _storagePreflightService.inspect(
        repaired,
        runtimeStatus: status,
      );
      final location = await _managedStorageService.inspect();
      final bytes = await _directorySize(status.managedRoot);
      if (!mounted) return;
      setState(() {
        _config = repaired;
        _status = status;
        _storage = storage;
        _managedStorageLocation = location;
        _managedBytes = bytes;
      });
    } on TranscriptionException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '检测识别环境失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<int?> _directorySize(String path) async {
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

  Future<void> _saveAndRefresh(TranscriptionConfig config) async {
    if (config.isConfigured) await _settingsStore.save(config);
    if (!mounted) return;
    setState(() => _config = config);
    await _refresh();
  }

  Future<void> _changeMode(TranscriptionMode mode) async {
    final current = _config ?? _defaultConfig;
    final updated = current.copyWith(
      mode: mode,
      profilePreference:
          current.profilePreference == TranscriptionProfilePreference.custom
          ? TranscriptionProfilePreference.custom
          : TranscriptionProfilePreference.automatic,
    );
    await _saveAndRefresh(updated);
  }

  Future<bool> _ensureStorageBeforeInstall(TranscriptionConfig config) async {
    final storage = await _storagePreflightService.inspect(
      config,
      runtimeStatus: _status,
    );
    if (!mounted) return false;
    setState(() => _storage = storage);
    if (storage.canInstall) return true;

    setState(() {
      _error =
          '磁盘空间不足：本次安装建议至少可用 '
          '${AsrSettingsText.formatBytes(storage.requiredAdditionalBytes)}，'
          '当前可用 ${AsrSettingsText.formatBytes(storage.availableBytes)}，'
          '还差 ${AsrSettingsText.formatBytes(storage.shortfallBytes)}。'
          '请释放空间后重新检测。';
    });
    return false;
  }

  Future<void> _install({bool resume = false}) async {
    final current = _config ?? _defaultConfig;
    if (!await _ensureStorageBeforeInstall(current)) return;

    var completed = false;
    setState(() {
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
      if (!mounted) return;
      setState(() => _config = installed);
      await _refresh();
    } on TranscriptionException catch (error) {
      if (!mounted) return;
      if (_pauseRequested) {
        setState(() {
          _paused = true;
          _error = null;
        });
      } else {
        setState(() {
          _failedComponent = _progress?.component;
          _error = error.toString();
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (_pauseRequested) {
        setState(() {
          _paused = true;
          _error = null;
        });
      } else {
        setState(() {
          _failedComponent = _progress?.component;
          _error = '安装识别环境失败：$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
          _pauseRequested = false;
          if (completed) _progress = null;
        });
      }
    }
  }

  Future<void> _pauseInstall() async {
    if (!_installing) return;
    setState(() => _pauseRequested = true);
    await _runtimeManager.cancel();
  }

  Future<void> _resumeInstall() => _install(resume: true);

  Future<void> _scanExistingModels() async {
    if (_busy || _runtimeManager.isInstalling) return;
    setState(() {
      _scanningExisting = true;
      _error = null;
      _existingModelMessage = AsrFolderText.scanning;
    });
    try {
      final result = await _managedStorageService.discoverAndAdoptExisting();
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _existingModelMessage = AsrFolderText.notFound;
        });
        return;
      }
      await _afterExistingRootAdopted(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '识别已有模型失败：$error');
    } finally {
      if (mounted) setState(() => _scanningExisting = false);
    }
  }

  Future<void> _pasteExistingModelPath() async {
    if (_busy || _runtimeManager.isInstalling) return;
    final path = await showAsrExistingModelPathDialog(context);
    if (path == null || path.trim().isEmpty || !mounted) return;
    await _adoptExistingPath(path);
  }

  Future<void> _browseExistingModel() async {
    if (_busy || _runtimeManager.isInstalling) return;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AsrFolderText.pickExistingTitle,
    );
    if (path == null || path.trim().isEmpty || !mounted) return;
    await _adoptExistingPath(path);
  }

  Future<void> _adoptExistingPath(String path) async {
    if (_busy || _runtimeManager.isInstalling) return;
    setState(() {
      _scanningExisting = true;
      _error = null;
      _existingModelMessage = AsrFolderText.checkingPath(path);
    });
    try {
      final result = await _managedStorageService.adoptExistingAt(path);
      await _afterExistingRootAdopted(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _existingModelMessage = AsrFolderText.pathNotRecognised;
        _error = '识别已有模型失败：$error';
      });
    } finally {
      if (mounted) setState(() => _scanningExisting = false);
    }
  }

  Future<void> _afterExistingRootAdopted(
    AsrManagedStorageMoveResult result,
  ) async {
    if (!mounted) return;
    setState(() {
      _existingModelMessage = '已找到已有环境：${result.targetRoot}。正在重新检测组件；此步骤不会下载。';
    });
    final repaired = await _runtimeManager.repair(_config ?? _defaultConfig);
    if (repaired.isConfigured) {
      await _settingsStore.save(repaired);
    }
    if (!mounted) return;
    setState(() => _config = repaired);
    await _refresh();
    if (!mounted) return;
    final status = _status;
    setState(() {
      _existingModelMessage = status?.isReady == true
          ? '已启用已有环境：${result.targetRoot}。组件已就绪，本次没有下载；'
                '之后执行校验/修复时仍会核对模型 SHA-256。'
          : status == null
          ? '已找到并使用已有环境：${result.targetRoot}。请重新检测确认各组件状态。'
          : '已找到并使用已有环境：${result.targetRoot}。当前 '
                '${status.readyCount}/${status.components.length} 个组件就绪；'
                '点击“校验并补齐缺失组件”时会先校验已有文件，只有下面列出的缺失或'
                '校验失败组件才会下载。';
    });
  }

  Future<void> _changeManagedStorageLocation() async {
    final parent = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AsrFolderText.pickNewParentTitle,
    );
    if (parent == null || parent.trim().isEmpty || !mounted) return;
    await _moveManagedStorage(parent: parent);
  }

  Future<void> _restoreDefaultStorageLocation() async {
    await _moveManagedStorage(useDefault: true);
  }

  Future<void> _moveManagedStorage({
    String? parent,
    bool useDefault = false,
  }) async {
    if (_busy || _runtimeManager.isInstalling) return;
    if (!useDefault && (parent == null || parent.trim().isEmpty)) return;

    final bytes = _managedBytes ?? 0;
    if (bytes > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(useDefault ? '迁回默认位置？' : '迁移识别环境？'),
          content: Text(
            AsrFolderText.moveConfirmation(AsrSettingsText.formatBytes(bytes)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始迁移'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _movingStorage = true;
      _movingCopiedBytes = 0;
      _movingTotalBytes = bytes;
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
      final current = _config ?? _defaultConfig;
      final repaired = await _runtimeManager.repair(current);
      // Changing the storage root must work before the environment is fully
      // installed. The settings store intentionally rejects incomplete
      // configurations, so only persist repaired paths once they are usable;
      // the managed-root pointer above is already the source of truth for
      // the new location and _refresh will rediscover whatever exists there.
      if (repaired.isConfigured) {
        await _settingsStore.save(repaired);
      }
      if (!mounted) return;
      setState(() {
        _config = repaired;
        if (result.adoptedExisting) {
          _existingModelMessage =
              '已识别并使用现有识别环境：${result.targetRoot}；未复制或删除旧目录。';
        }
      });
      await _refresh();
      if (!mounted || !result.moved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.adoptedExisting
                ? '已识别并使用现有的识别环境：${result.targetRoot}；旧目录未删除。'
                : result.oldRootRetained
                ? '识别环境已切换；旧目录 ${result.sourceRoot} 未能自动删除，请手工清理。'
                : '识别环境已迁移到 ${result.targetRoot}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '迁移识别环境失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _movingStorage = false;
          _movingCopiedBytes = 0;
          _movingTotalBytes = 0;
        });
      }
    }
  }

  void _onStorageMoveProgress(int copiedBytes, int totalBytes) {
    if (!mounted) return;
    setState(() {
      _movingCopiedBytes = copiedBytes;
      _movingTotalBytes = totalBytes;
    });
  }

  Future<void> _deleteModels({required bool reinstall}) async {
    final status = _status;
    if (status == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reinstall ? '删除并重新安装模型？' : '删除本地模型？'),
        content: Text(
          reinstall
              ? '会删除 Elysium Player 托管的 Qwen / Whisper 模型，然后按当前质量方案重新下载。手工指定的外部模型不会被删除。'
              : '会删除 Elysium Player 托管的 Qwen / Whisper 模型。runtime 与手工指定的外部模型会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(reinstall ? '删除并重装' : '删除模型'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
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
      if (!mounted) return;
      await _refresh();
      if (reinstall && mounted) {
        await _install();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '删除模型失败：$error');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _openAdvanced() async {
    final updated = await showDialog<TranscriptionConfig>(
      context: context,
      builder: (context) => TranscriptionConfigDialog(
        initialConfig: _config ?? _defaultConfig,
        dependencies: widget.dependencies.configDialogDependencies,
      ),
    );
    if (updated == null || !mounted) return;
    await _saveAndRefresh(updated);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config ?? _defaultConfig;
    final status = _status;
    final ready = status?.isReady == true;
    final storageBlocked = _storage?.canInstall == false;
    VoidCallback? unlessBusy(VoidCallback action) => _busy ? null : action;

    // The four cards are stateless (ai_transcription_settings_cards.dart);
    // this state object owns the services, the install and move flows and
    // the confirmation dialogs (audit SE-04).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AsrPlanCard(
          config: config,
          status: status,
          loading: _loading,
          installing: _installing,
          managedBytes: _managedBytes,
          onModeChanged: _busy ? null : (mode) => unawaited(_changeMode(mode)),
        ),
        const SizedBox(height: AppSpacing.lg),
        AsrStorageSettingsCard(
          ready: ready,
          loading: _loading,
          storage: _storage,
          location: _managedStorageLocation,
          scanningExisting: _scanningExisting,
          existingModelMessage: _existingModelMessage,
          movingStorage: _movingStorage,
          movingCopiedBytes: _movingCopiedBytes,
          movingTotalBytes: _movingTotalBytes,
          onScan: unlessBusy(_scanExistingModels),
          onPastePath: unlessBusy(_pasteExistingModelPath),
          onBrowse: unlessBusy(_browseExistingModel),
          onChangeLocation: unlessBusy(_changeManagedStorageLocation),
          onRestoreDefault: unlessBusy(_restoreDefaultStorageLocation),
        ),
        const SizedBox(height: AppSpacing.lg),
        AsrMaintenanceCard(
          ready: ready,
          loading: _loading,
          busy: _busy,
          storageBlocked: storageBlocked,
          installing: _installing,
          paused: _paused,
          progress: _progress,
          error: _error,
          failedComponent: _failedComponent,
          onRefresh: () => _refresh(loadFromStore: true),
          onInstall: _install,
          onPause: _pauseInstall,
          onResume: _resumeInstall,
          onRetry: () => _install(resume: true),
          onDelete: (reinstall) => _deleteModels(reinstall: reinstall),
        ),
        const SizedBox(height: AppSpacing.lg),
        AsrAdvancedSettingsCard(
          config: config,
          onOpenAdvanced: unlessBusy(_openAdvanced),
        ),
      ],
    );
  }
}
