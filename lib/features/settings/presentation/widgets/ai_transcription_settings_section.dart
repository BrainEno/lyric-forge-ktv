import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/services/asr_managed_storage_service.dart';
import '../../../transcription/domain/services/asr_runtime_manager.dart';
import '../../../transcription/domain/services/asr_storage_preflight_service.dart';
import '../../../transcription/domain/services/transcription_settings_store.dart';
import '../../../transcription/presentation/widgets/asr_existing_model_actions.dart';
import '../../../transcription/presentation/widgets/asr_install_error_card.dart';
import '../../../transcription/presentation/widgets/asr_install_progress_card.dart';
import '../../../transcription/presentation/widgets/asr_storage_preflight_card.dart';
import '../../../transcription/presentation/widgets/transcription_config_dialog.dart';

class AiTranscriptionSettingsSection extends StatefulWidget {
  const AiTranscriptionSettingsSection({super.key});

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
    final services = ServiceLocatorGlobal.I;
    _settingsStore = services.transcriptionSettingsStore;
    _runtimeManager = services.asrRuntimeManager;
    _storagePreflightService = services.asrStoragePreflightService;
    _managedStorageService = services.asrManagedStorageService;
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
          '${_formatBytes(storage.requiredAdditionalBytes)}，'
          '当前可用 ${_formatBytes(storage.availableBytes)}，'
          '还差 ${_formatBytes(storage.shortfallBytes)}。'
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
      _existingModelMessage = '正在常见磁盘位置查找已有 ASRRuntime…此步骤不会下载。';
    });
    try {
      final result = await _managedStorageService.discoverAndAdoptExisting();
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _existingModelMessage =
              '没有在常见位置找到已有 ASRRuntime。可以粘贴包含已有模型的磁盘或文件夹路径，'
              '也可以继续在当前目录校验并补齐缺失组件。';
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
      dialogTitle: '选择磁盘、Models、LyricForge 或已有的 ASRRuntime',
    );
    if (path == null || path.trim().isEmpty || !mounted) return;
    await _adoptExistingPath(path);
  }

  Future<void> _adoptExistingPath(String path) async {
    if (_busy || _runtimeManager.isInstalling) return;
    setState(() {
      _scanningExisting = true;
      _error = null;
      _existingModelMessage = '正在从 $path 识别已有 ASRRuntime…此步骤不会下载。';
    });
    try {
      final result = await _managedStorageService.adoptExistingAt(path);
      await _afterExistingRootAdopted(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _existingModelMessage = '没有从该路径识别到已有 ASRRuntime，当前目录未改变。';
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
      dialogTitle: '选择磁盘 / 父文件夹、LyricForge 文件夹或已有的 ASRRuntime',
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
            '当前托管环境约 ${_formatBytes(bytes)}。如果所选位置已有 LyricForge ASRRuntime，'
            '会直接识别并使用其中的模型，不复制、不删除当前目录；否则会先完整复制并核对文件数量与总大小，'
            '确认新目录完整后才切换路径并清理旧目录。操作期间不会启动识别任务。',
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
      builder: (context) =>
          TranscriptionConfigDialog(initialConfig: _config ?? _defaultConfig),
    );
    if (updated == null || !mounted) return;
    await _saveAndRefresh(updated);
  }

  String _componentLabel(AsrRuntimeComponent component) {
    return switch (component) {
      AsrRuntimeComponent.ffmpeg => 'FFmpeg',
      AsrRuntimeComponent.whisperRuntime => 'Whisper runtime',
      AsrRuntimeComponent.whisperModel => 'Whisper 模型',
      AsrRuntimeComponent.qwenRuntime => 'Qwen runtime',
      AsrRuntimeComponent.qwenModel => 'Qwen 模型',
      AsrRuntimeComponent.qwenAligner => 'ForcedAligner',
    };
  }

  String _modeLabel(TranscriptionMode mode) {
    return switch (mode) {
      TranscriptionMode.highestQuality => '最高质量 · Qwen + 对齐 + Whisper fallback',
      TranscriptionMode.whisperOnly => 'Whisper 单模型 · 更省空间',
    };
  }

  String _modelSummary(TranscriptionConfig config) {
    if (config.mode == TranscriptionMode.whisperOnly) {
      final model = config.modelPath.trim().isEmpty
          ? 'Whisper large-v3（待安装）'
          : _basename(config.modelPath);
      return '$model · Whisper runtime';
    }

    final qwen = _modelDisplay(config.qwenModelPath, 'Qwen3-ASR 1.7B');
    final aligner = _modelDisplay(
      config.qwenAlignerModelPath,
      'ForcedAligner 0.6B',
    );
    final whisper = config.modelPath.trim().isEmpty
        ? 'Whisper fallback'
        : '${_basename(config.modelPath)} fallback';
    return '$qwen + $aligner + $whisper';
  }

  String _modelDisplay(String pathOrId, String fallback) {
    final value = pathOrId.trim();
    if (value.isEmpty) return fallback;
    if (value.contains('Qwen3-ASR-1.7B')) return 'Qwen3-ASR 1.7B';
    if (value.contains('Qwen3-ASR-0.6B')) return 'Qwen3-ASR 0.6B';
    if (value.contains('ForcedAligner-0.6B')) return 'ForcedAligner 0.6B';
    return _basename(value);
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? path : parts.last;
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return '无法读取';
    if (bytes == 0) return '0 MB';
    final gib = bytes / (1024 * 1024 * 1024);
    if (gib >= 1) return '${gib.toStringAsFixed(gib >= 10 ? 1 : 2)} GB';
    final mib = bytes / (1024 * 1024);
    return '${mib.toStringAsFixed(mib >= 10 ? 0 : 1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final config = _config ?? _defaultConfig;
    final status = _status;
    final ready = status?.isReady == true;
    final storageBlocked = _storage?.canInstall == false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha(24),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
              ),
              child: const Icon(Icons.auto_awesome_rounded),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI / 歌词识别',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '这里是桌面端统一的模型与 runtime 管理入口。保存后，工程详情和下一次歌词识别会读取同一份配置。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _InfoGrid(
          children: [
            _InfoTile(
              label: '当前推荐方案',
              value: status?.profile.label ?? (_loading ? '正在检测…' : '尚未检测'),
              detail: status?.profile.description,
            ),
            _InfoTile(label: '当前实际模型', value: _modelSummary(config)),
            _InfoTile(
              label: '安装状态',
              value: ready
                  ? '已就绪'
                  : _installing
                  ? '正在安装'
                  : status == null
                  ? '未检测'
                  : '${status.readyCount}/${status.components.length} 个组件已就绪',
              valueColor: ready ? AppColors.success : null,
            ),
            _InfoTile(
              label: '托管环境占用空间',
              value: _formatBytes(_managedBytes),
              detail: '仅统计 Elysium Player 托管目录；外部手工模型不计入',
            ),
            _InfoTile(
              label: '安装目录',
              value: status?.managedRoot ?? '检测后显示',
              selectable: true,
            ),
            _InfoTile(label: '当前质量方案', value: _modeLabel(config.mode)),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        DropdownButtonFormField<TranscriptionMode>(
          initialValue: config.mode,
          decoration: const InputDecoration(
            labelText: '质量方案',
            helperText: '切换后立即保存，并作用于下一次识别。',
          ),
          items: const [
            DropdownMenuItem(
              value: TranscriptionMode.highestQuality,
              child: Text('最高质量 · Qwen + ForcedAligner + Whisper fallback'),
            ),
            DropdownMenuItem(
              value: TranscriptionMode.whisperOnly,
              child: Text('Whisper 单模型 · 更省空间'),
            ),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value != null && value != config.mode) {
                    unawaited(_changeMode(value));
                  }
                },
        ),
        if (status != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ComponentList(components: status.components),
        ],
        if (!ready || _existingModelMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          AsrExistingModelCard(
            scanning: _scanningExisting,
            message: _existingModelMessage,
            onScan: _busy ? null : _scanExistingModels,
            onPastePath: _busy ? null : _pasteExistingModelPath,
            onBrowse: _busy ? null : _browseExistingModel,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        AsrStoragePreflightCard(
          result: _storage,
          loading: _loading,
          onChangeLocation: _busy ? null : _changeManagedStorageLocation,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _changeManagedStorageLocation,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('迁移当前环境到其他文件夹'),
            ),
            if (_managedStorageLocation?.isDefault == false)
              TextButton.icon(
                onPressed: _busy ? null : _restoreDefaultStorageLocation,
                icon: const Icon(Icons.settings_backup_restore_rounded),
                label: const Text('迁回默认位置'),
              ),
            if (_movingStorage)
              Text(
                _movingTotalBytes > 0
                    ? '正在迁移 ${_formatBytes(_movingCopiedBytes)} / ${_formatBytes(_movingTotalBytes)}'
                    : '正在迁移识别环境…',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
        if (_progress != null &&
            (_installing || _paused || _error != null)) ...[
          const SizedBox(height: AppSpacing.md),
          AsrInstallProgressCard(
            progress: _progress!,
            paused: _paused,
            failed: _error != null && !_paused,
            onPause: _installing ? _pauseInstall : null,
            onResume: _paused ? _resumeInstall : null,
            onRetry: _error != null && !_paused
                ? () => _install(resume: true)
                : null,
            retryLabel: _failedComponent == null
                ? '重试未完成组件'
                : '重试 ${_componentLabel(_failedComponent!)}',
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          AsrInstallErrorCard(message: _error!),
        ],
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _refresh(loadFromStore: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新检测'),
            ),
            if (_installing)
              OutlinedButton.icon(
                onPressed: _pauseInstall,
                icon: const Icon(Icons.pause_rounded),
                label: const Text('暂停下载'),
              )
            else if (_paused)
              FilledButton.icon(
                onPressed: _resumeInstall,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('继续下载'),
              )
            else
              FilledButton.icon(
                onPressed: _loading || storageBlocked ? null : _install,
                icon: Icon(
                  storageBlocked
                      ? Icons.sd_storage_rounded
                      : _error != null
                      ? Icons.refresh_rounded
                      : Icons.fact_check_outlined,
                ),
                label: Text(
                  storageBlocked
                      ? '空间不足'
                      : _error != null
                      ? (_failedComponent == null
                            ? '重试未完成组件'
                            : '重试 ${_componentLabel(_failedComponent!)}')
                      : ready
                      ? '校验并修复'
                      : '校验并补齐缺失组件',
                ),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _deleteModels(reinstall: false),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('删除模型'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _deleteModels(reinstall: true),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('删除并重装模型'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
          title: const Text('高级设置'),
          subtitle: const Text('手工选择模型路径、runtime、FFmpeg、设备和精度'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Qwen runtime：${config.qwenExecutable.isEmpty ? '未指定' : config.qwenExecutable}\n'
                'Qwen 模型：${config.qwenModelPath}\n'
                'ForcedAligner：${config.qwenAlignerModelPath}\n'
                'Whisper runtime：${config.whisperExecutable.isEmpty ? '未指定' : config.whisperExecutable}\n'
                'Whisper 模型：${config.modelPath.isEmpty ? '未指定' : config.modelPath}\n'
                'FFmpeg：${config.ffmpegExecutable}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _openAdvanced,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('手工选择模型路径和 runtime'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final List<Widget> children;

  const _InfoGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 980
            ? 3
            : width >= 640
            ? 2
            : 1;
        final gap = AppSpacing.sm;
        final tileWidth = columns == 1
            ? width
            : (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: tileWidth, child: child),
          ],
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final Color? valueColor;
  final bool selectable;

  const _InfoTile({
    required this.label,
    required this.value,
    this.detail,
    this.valueColor,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueWidget = Text(
      value,
      maxLines: selectable ? null : 3,
      overflow: selectable ? null : TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: valueColor,
        fontWeight: FontWeight.w700,
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (selectable) SelectionArea(child: valueWidget) else valueWidget,
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              detail!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComponentList extends StatelessWidget {
  final List<AsrRuntimeComponentStatus> components;

  const _ComponentList({required this.components});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        children: [
          for (var index = 0; index < components.length; index++) ...[
            _ComponentRow(component: components[index]),
            if (index != components.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _ComponentRow extends StatelessWidget {
  final AsrRuntimeComponentStatus component;

  const _ComponentRow({required this.component});

  @override
  Widget build(BuildContext context) {
    final ready = component.state == AsrRuntimeComponentState.ready;
    return ListTile(
      dense: true,
      leading: Icon(
        ready
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        color: ready ? AppColors.success : AppColors.textTertiary,
      ),
      title: Text(component.label),
      subtitle: Text(component.detail),
      trailing: Text(
        ready ? '已安装' : component.state.name,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: ready ? AppColors.success : AppColors.textTertiary,
        ),
      ),
    );
  }
}
