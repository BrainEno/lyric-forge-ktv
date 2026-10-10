from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, found {count}: {old[:80]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


def ensure_contains(path: str, needle: str) -> None:
    if needle not in Path(path).read_text(encoding='utf-8'):
        raise RuntimeError(f'{path}: missing expected marker {needle!r}')


# Managed runtime installer: one root resolver for runtime, FFmpeg and Whisper.
path = 'lib/features/transcription/data/services/managed_asr_runtime_manager.dart'
replace_once(
    path,
    '  final TranscriptionProfileResolver profileResolver;\n',
    '  final TranscriptionProfileResolver profileResolver;\n'
    '  final Future<Directory> Function()? managedRootResolver;\n',
)
replace_once(
    path,
    '  ManagedAsrRuntimeManager({\n    required this.profileResolver,\n  });',
    '  ManagedAsrRuntimeManager({\n'
    '    required this.profileResolver,\n'
    '    this.managedRootResolver,\n'
    '  });',
)
replace_once(
    path,
    "  Future<Directory> _managedRoot() async {\n"
    "    final support = await getApplicationSupportDirectory();\n"
    "    final root = Directory(\n"
    "      _join(support.path, ['LyricForge', 'ASRRuntime']),\n"
    "    );\n"
    "    await root.create(recursive: true);\n"
    "    return root;\n"
    "  }",
    "  Future<Directory> _managedRoot() async {\n"
    "    final injected = managedRootResolver;\n"
    "    if (injected != null) {\n"
    "      final root = await injected();\n"
    "      await root.create(recursive: true);\n"
    "      return root;\n"
    "    }\n"
    "    final support = await getApplicationSupportDirectory();\n"
    "    final root = Directory(\n"
    "      _join(support.path, ['LyricForge', 'ASRRuntime']),\n"
    "    );\n"
    "    await root.create(recursive: true);\n"
    "    return root;\n"
    "  }",
)

# Managed Qwen model installer.
path = 'lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart'
replace_once(
    path,
    '  final TranscriptionProfileResolver profileResolver;\n',
    '  final TranscriptionProfileResolver profileResolver;\n'
    '  final Future<Directory> Function()? managedRootResolver;\n',
)
replace_once(
    path,
    '  ManagedModelAsrRuntimeManager({\n'
    '    required this.delegate,\n'
    '    required this.profileResolver,\n'
    '  }) {',
    '  ManagedModelAsrRuntimeManager({\n'
    '    required this.delegate,\n'
    '    required this.profileResolver,\n'
    '    this.managedRootResolver,\n'
    '  }) {',
)
replace_once(
    path,
    "  Future<Directory> _managedRoot() async {\n"
    "    final support = await getApplicationSupportDirectory();\n"
    "    final root = Directory(\n"
    "      _join(support.path, ['LyricForge', 'ASRRuntime']),\n"
    "    );\n"
    "    await Directory(_join(root.path, ['models', 'qwen']))\n"
    "        .create(recursive: true);\n"
    "    return root;\n"
    "  }",
    "  Future<Directory> _managedRoot() async {\n"
    "    final injected = managedRootResolver;\n"
    "    final root = injected == null\n"
    "        ? Directory(\n"
    "            _join(\n"
    "              (await getApplicationSupportDirectory()).path,\n"
    "              ['LyricForge', 'ASRRuntime'],\n"
    "            ),\n"
    "          )\n"
    "        : await injected();\n"
    "    await Directory(_join(root.path, ['models', 'qwen']))\n"
    "        .create(recursive: true);\n"
    "    return root;\n"
    "  }",
)

# Standalone Whisper fallback.
path = 'lib/features/transcription/data/services/resilient_asr_runtime_manager.dart'
replace_once(
    path,
    '  final AsrRuntimeManager delegate;\n',
    '  final AsrRuntimeManager delegate;\n'
    '  final Future<Directory> Function()? managedRootResolver;\n',
)
replace_once(
    path,
    '  ResilientAsrRuntimeManager({\n'
    '    required this.delegate,\n'
    '    this.whisperRuntimeBootstrap,\n'
    '  }) {',
    '  ResilientAsrRuntimeManager({\n'
    '    required this.delegate,\n'
    '    this.managedRootResolver,\n'
    '    this.whisperRuntimeBootstrap,\n'
    '  }) {',
)
replace_once(
    path,
    "  Future<Directory> _managedRoot() async {\n"
    "    final support = await getApplicationSupportDirectory();\n"
    "    final root = Directory(\n"
    "      _join(support.path, ['LyricForge', 'ASRRuntime']),\n"
    "    );\n"
    "    await root.create(recursive: true);\n"
    "    return root;\n"
    "  }",
    "  Future<Directory> _managedRoot() async {\n"
    "    final injected = managedRootResolver;\n"
    "    if (injected != null) {\n"
    "      final root = await injected();\n"
    "      await root.create(recursive: true);\n"
    "      return root;\n"
    "    }\n"
    "    final support = await getApplicationSupportDirectory();\n"
    "    final root = Directory(\n"
    "      _join(support.path, ['LyricForge', 'ASRRuntime']),\n"
    "    );\n"
    "    await root.create(recursive: true);\n"
    "    return root;\n"
    "  }",
)

# Service locator: instantiate one root authority and inject it everywhere.
path = 'lib/core/services/service_locator.dart'
replace_once(
    path,
    "import '../../features/transcription/data/services/local_asr_end_to_end_smoke_test_service.dart';\n",
    "import '../../features/transcription/data/services/local_asr_end_to_end_smoke_test_service.dart';\n"
    "import '../../features/transcription/data/services/local_asr_managed_storage_service.dart';\n",
)
replace_once(
    path,
    '  late final AsrRuntimeManager asrRuntimeManager;\n'
    '  late final AsrStoragePreflightService asrStoragePreflightService;\n',
    '  late final AsrRuntimeManager asrRuntimeManager;\n'
    '  late final LocalAsrManagedStorageService asrManagedStorageService;\n'
    '  late final AsrStoragePreflightService asrStoragePreflightService;\n',
)
replace_once(
    path,
    '    transcriptionProfileResolver = NativeTranscriptionProfileResolver();\n'
    '    asrStoragePreflightService = LocalAsrStoragePreflightService(\n'
    '      profileResolver: transcriptionProfileResolver,\n'
    '    );\n'
    '    final runtimeInstaller = ManagedAsrRuntimeManager(\n'
    '      profileResolver: transcriptionProfileResolver,\n'
    '    );\n'
    '    final managedRuntime = ManagedModelAsrRuntimeManager(\n'
    '      delegate: runtimeInstaller,\n'
    '      profileResolver: transcriptionProfileResolver,\n'
    '    );\n'
    '    final resilientRuntime = ResilientAsrRuntimeManager(\n'
    '      delegate: managedRuntime,\n'
    '    );',
    '    transcriptionProfileResolver = NativeTranscriptionProfileResolver();\n'
    '    asrManagedStorageService = LocalAsrManagedStorageService();\n'
    '    asrStoragePreflightService = LocalAsrStoragePreflightService(\n'
    '      profileResolver: transcriptionProfileResolver,\n'
    '      managedRootResolver: asrManagedStorageService.resolveRoot,\n'
    '    );\n'
    '    final runtimeInstaller = ManagedAsrRuntimeManager(\n'
    '      profileResolver: transcriptionProfileResolver,\n'
    '      managedRootResolver: asrManagedStorageService.resolveRoot,\n'
    '    );\n'
    '    final managedRuntime = ManagedModelAsrRuntimeManager(\n'
    '      delegate: runtimeInstaller,\n'
    '      profileResolver: transcriptionProfileResolver,\n'
    '      managedRootResolver: asrManagedStorageService.resolveRoot,\n'
    '    );\n'
    '    final resilientRuntime = ResilientAsrRuntimeManager(\n'
    '      delegate: managedRuntime,\n'
    '      managedRootResolver: asrManagedStorageService.resolveRoot,\n'
    '    );',
)

# Storage card can directly route an insufficient user to another drive.
path = 'lib/features/transcription/presentation/widgets/asr_storage_preflight_card.dart'
replace_once(
    path,
    '  final AsrStoragePreflightResult? result;\n  final bool loading;\n',
    '  final AsrStoragePreflightResult? result;\n'
    '  final bool loading;\n'
    '  final VoidCallback? onChangeLocation;\n',
)
replace_once(
    path,
    '    required this.result,\n    this.loading = false,\n  });',
    '    required this.result,\n'
    '    this.loading = false,\n'
    '    this.onChangeLocation,\n'
    '  });',
)
replace_once(
    path,
    "          SelectionArea(\n"
    "            child: Text(\n"
    "              '安装目录：${value.managedRoot}',\n"
    "              style: Theme.of(context).textTheme.labelSmall?.copyWith(\n"
    "                    color: AppColors.textTertiary,\n"
    "                  ),\n"
    "            ),\n"
    "          ),",
    "          SelectionArea(\n"
    "            child: Text(\n"
    "              '安装目录：${value.managedRoot}',\n"
    "              style: Theme.of(context).textTheme.labelSmall?.copyWith(\n"
    "                    color: AppColors.textTertiary,\n"
    "                  ),\n"
    "            ),\n"
    "          ),\n"
    "          if (onChangeLocation != null) ...[\n"
    "            const SizedBox(height: AppSpacing.sm),\n"
    "            Align(\n"
    "              alignment: Alignment.centerLeft,\n"
    "              child: OutlinedButton.icon(\n"
    "                onPressed: onChangeLocation,\n"
    "                icon: const Icon(Icons.drive_file_move_outline_rounded),\n"
    "                label: Text(insufficient ? '换一个磁盘 / 文件夹' : '更改模型存储位置'),\n"
    "              ),\n"
    "            ),\n"
    "          ],",
)

# First-run setup: offer drive relocation directly from the storage preflight.
path = 'lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart'
replace_once(
    path,
    "import 'package:flutter/material.dart';\n",
    "import 'package:file_picker/file_picker.dart';\n"
    "import 'package:flutter/material.dart';\n\n"
    "import '../../data/services/local_asr_managed_storage_service.dart';\n",
)
replace_once(
    path,
    '  late final AsrRuntimeManager _runtimeManager;\n'
    '  late final AsrStoragePreflightService _storagePreflightService;\n',
    '  late final AsrRuntimeManager _runtimeManager;\n'
    '  late final AsrStoragePreflightService _storagePreflightService;\n'
    '  late final LocalAsrManagedStorageService _managedStorageService;\n',
)
replace_once(
    path,
    '    _runtimeManager = services.asrRuntimeManager;\n'
    '    _storagePreflightService = services.asrStoragePreflightService;\n',
    '    _runtimeManager = services.asrRuntimeManager;\n'
    '    _storagePreflightService = services.asrStoragePreflightService;\n'
    '    _managedStorageService = services.asrManagedStorageService;\n',
)
replace_once(
    path,
    '  Future<void> _resumeInstall() => _install(resume: true);\n\n',
    "  Future<void> _resumeInstall() => _install(resume: true);\n\n"
    "  Future<void> _changeManagedStorageLocation() async {\n"
    "    if (_installing || _runtimeManager.isInstalling) return;\n"
    "    final parent = await FilePicker.platform.getDirectoryPath(\n"
    "      dialogTitle: '选择 ASR 模型和 runtime 所在磁盘 / 文件夹',\n"
    "    );\n"
    "    if (parent == null || parent.trim().isEmpty || !mounted) return;\n\n"
    "    setState(() {\n"
    "      _loading = true;\n"
    "      _error = null;\n"
    "    });\n"
    "    try {\n"
    "      final result = await _managedStorageService.moveToParent(parent);\n"
    "      final repaired = await _runtimeManager.repair(_config);\n"
    "      if (!mounted) return;\n"
    "      setState(() => _config = repaired);\n"
    "      await _refresh();\n"
    "      if (!mounted || !result.moved) return;\n"
    "      ScaffoldMessenger.of(context).showSnackBar(\n"
    "        SnackBar(\n"
    "          content: Text(\n"
    "            result.oldRootRetained\n"
    "                ? '识别环境已切换到新位置；旧目录未能自动删除，请稍后手工清理。'\n"
    "                : '识别环境已安全迁移到新位置。',\n"
    "          ),\n"
    "        ),\n"
    "      );\n"
    "    } catch (error) {\n"
    "      if (!mounted) return;\n"
    "      setState(() => _error = '更改模型存储位置失败：$error');\n"
    "    } finally {\n"
    "      if (mounted && _loading) setState(() => _loading = false);\n"
    "    }\n"
    "  }\n\n",
)
replace_once(
    path,
    '                  AsrStoragePreflightCard(\n'
    '                    result: _storage,\n'
    '                    loading: _loading,\n'
    '                  ),',
    '                  AsrStoragePreflightCard(\n'
    '                    result: _storage,\n'
    '                    loading: _loading,\n'
    '                    onChangeLocation:\n'
    '                        _installing ? null : _changeManagedStorageLocation,\n'
    '                  ),',
)

# Settings: manage the root explicitly, migrate existing data and allow return to default.
path = 'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart'
replace_once(
    path,
    "import 'package:flutter/material.dart';\n",
    "import 'package:file_picker/file_picker.dart';\n"
    "import 'package:flutter/material.dart';\n",
)
replace_once(
    path,
    "import '../../../transcription/domain/models/transcription_models.dart';\n",
    "import '../../../transcription/data/services/local_asr_managed_storage_service.dart';\n"
    "import '../../../transcription/domain/models/transcription_models.dart';\n",
)
replace_once(
    path,
    '  late final AsrStoragePreflightService _storagePreflightService;\n',
    '  late final AsrStoragePreflightService _storagePreflightService;\n'
    '  late final LocalAsrManagedStorageService _managedStorageService;\n',
)
replace_once(
    path,
    '  AsrStoragePreflightResult? _storage;\n',
    '  AsrStoragePreflightResult? _storage;\n'
    '  AsrManagedStorageLocation? _managedStorageLocation;\n',
)
replace_once(
    path,
    '  bool _deleting = false;\n',
    '  bool _deleting = false;\n'
    '  bool _movingStorage = false;\n'
    '  int _movingCopiedBytes = 0;\n'
    '  int _movingTotalBytes = 0;\n',
)
replace_once(
    path,
    '  bool get _busy => _loading || _installing || _paused || _deleting;',
    '  bool get _busy =>\n'
    '      _loading || _installing || _paused || _deleting || _movingStorage;',
)
replace_once(
    path,
    '    _storagePreflightService = services.asrStoragePreflightService;\n',
    '    _storagePreflightService = services.asrStoragePreflightService;\n'
    '    _managedStorageService = services.asrManagedStorageService;\n',
)
replace_once(
    path,
    '      final bytes = await _directorySize(status.managedRoot);\n'
    '      if (!mounted) return;\n'
    '      setState(() {\n'
    '        _config = repaired;\n'
    '        _status = status;\n'
    '        _storage = storage;\n'
    '        _managedBytes = bytes;\n'
    '      });',
    '      final location = await _managedStorageService.inspect();\n'
    '      final bytes = await _directorySize(status.managedRoot);\n'
    '      if (!mounted) return;\n'
    '      setState(() {\n'
    '        _config = repaired;\n'
    '        _status = status;\n'
    '        _storage = storage;\n'
    '        _managedStorageLocation = location;\n'
    '        _managedBytes = bytes;\n'
    '      });',
)
replace_once(
    path,
    '  Future<void> _resumeInstall() => _install(resume: true);\n\n',
    "  Future<void> _resumeInstall() => _install(resume: true);\n\n"
    "  Future<void> _changeManagedStorageLocation() async {\n"
    "    final parent = await FilePicker.platform.getDirectoryPath(\n"
    "      dialogTitle: '选择 ASR 模型和 runtime 所在磁盘 / 文件夹',\n"
    "    );\n"
    "    if (parent == null || parent.trim().isEmpty || !mounted) return;\n"
    "    await _moveManagedStorage(parent: parent);\n"
    "  }\n\n"
    "  Future<void> _restoreDefaultStorageLocation() async {\n"
    "    await _moveManagedStorage(useDefault: true);\n"
    "  }\n\n"
    "  Future<void> _moveManagedStorage({\n"
    "    String? parent,\n"
    "    bool useDefault = false,\n"
    "  }) async {\n"
    "    if (_busy || _runtimeManager.isInstalling) return;\n"
    "    if (!useDefault && (parent == null || parent.trim().isEmpty)) return;\n\n"
    "    final bytes = _managedBytes ?? 0;\n"
    "    if (bytes > 0) {\n"
    "      final confirmed = await showDialog<bool>(\n"
    "        context: context,\n"
    "        builder: (context) => AlertDialog(\n"
    "          title: Text(useDefault ? '迁回默认位置？' : '迁移识别环境？'),\n"
    "          content: Text(\n"
    "            '当前托管环境约 ${_formatBytes(bytes)}。LyricForge 会先完整复制并核对文件数量与总大小，'\n"
    "            '确认新目录完整后才切换路径并清理旧目录；迁移期间不会启动识别任务。',\n"
    "          ),\n"
    "          actions: [\n"
    "            TextButton(\n"
    "              onPressed: () => Navigator.pop(context, false),\n"
    "              child: const Text('取消'),\n"
    "            ),\n"
    "            FilledButton(\n"
    "              onPressed: () => Navigator.pop(context, true),\n"
    "              child: const Text('开始迁移'),\n"
    "            ),\n"
    "          ],\n"
    "        ),\n"
    "      );\n"
    "      if (confirmed != true || !mounted) return;\n"
    "    }\n\n"
    "    setState(() {\n"
    "      _movingStorage = true;\n"
    "      _movingCopiedBytes = 0;\n"
    "      _movingTotalBytes = bytes;\n"
    "      _error = null;\n"
    "    });\n"
    "    try {\n"
    "      final result = useDefault\n"
    "          ? await _managedStorageService.moveToDefault(\n"
    "              onProgress: _onStorageMoveProgress,\n"
    "            )\n"
    "          : await _managedStorageService.moveToParent(\n"
    "              parent!,\n"
    "              onProgress: _onStorageMoveProgress,\n"
    "            );\n"
    "      final current = _config ?? _defaultConfig;\n"
    "      final repaired = await _runtimeManager.repair(current);\n"
    "      await _settingsStore.save(repaired);\n"
    "      if (!mounted) return;\n"
    "      setState(() => _config = repaired);\n"
    "      await _refresh();\n"
    "      if (!mounted || !result.moved) return;\n"
    "      ScaffoldMessenger.of(context).showSnackBar(\n"
    "        SnackBar(\n"
    "          content: Text(\n"
    "            result.oldRootRetained\n"
    "                ? '识别环境已切换；旧目录 ${result.sourceRoot} 未能自动删除，请手工清理。'\n"
    "                : '识别环境已迁移到 ${result.targetRoot}',\n"
    "          ),\n"
    "        ),\n"
    "      );\n"
    "    } catch (error) {\n"
    "      if (!mounted) return;\n"
    "      setState(() => _error = '迁移识别环境失败：$error');\n"
    "    } finally {\n"
    "      if (mounted) {\n"
    "        setState(() {\n"
    "          _movingStorage = false;\n"
    "          _movingCopiedBytes = 0;\n"
    "          _movingTotalBytes = 0;\n"
    "        });\n"
    "      }\n"
    "    }\n"
    "  }\n\n"
    "  void _onStorageMoveProgress(int copiedBytes, int totalBytes) {\n"
    "    if (!mounted) return;\n"
    "    setState(() {\n"
    "      _movingCopiedBytes = copiedBytes;\n"
    "      _movingTotalBytes = totalBytes;\n"
    "    });\n"
    "  }\n\n",
)
replace_once(
    path,
    '        AsrStoragePreflightCard(\n'
    '          result: _storage,\n'
    '          loading: _loading,\n'
    '        ),',
    '        AsrStoragePreflightCard(\n'
    '          result: _storage,\n'
    '          loading: _loading,\n'
    '          onChangeLocation: _busy ? null : _changeManagedStorageLocation,\n'
    '        ),\n'
    '        const SizedBox(height: AppSpacing.sm),\n'
    '        Wrap(\n'
    '          spacing: AppSpacing.sm,\n'
    '          runSpacing: AppSpacing.sm,\n'
    '          crossAxisAlignment: WrapCrossAlignment.center,\n'
    '          children: [\n'
    '            OutlinedButton.icon(\n'
    '              onPressed: _busy ? null : _changeManagedStorageLocation,\n'
    '              icon: const Icon(Icons.drive_file_move_outline_rounded),\n'
    '              label: const Text(\'更改模型存储位置\'),\n'
    '            ),\n'
    '            if (_managedStorageLocation?.isDefault == false)\n'
    '              TextButton.icon(\n'
    '                onPressed: _busy ? null : _restoreDefaultStorageLocation,\n'
    '                icon: const Icon(Icons.settings_backup_restore_rounded),\n'
    '                label: const Text(\'迁回默认位置\'),\n'
    '              ),\n'
    '            if (_movingStorage)\n'
    '              Text(\n'
    '                _movingTotalBytes > 0\n'
    '                    ? \'正在迁移 ${_formatBytes(_movingCopiedBytes)} / ${_formatBytes(_movingTotalBytes)}\'\n'
    '                    : \'正在迁移识别环境…\',\n'
    '                style: Theme.of(context).textTheme.bodySmall?.copyWith(\n'
    '                      color: AppColors.textSecondary,\n'
    '                    ),\n'
    '              ),\n'
    '          ],\n'
    '        ),',
)

# Remove now-unnecessary root duplication only from wiring, not compatibility
# fallbacks inside individual services. Verify every production writer receives
# the shared resolver.
ensure_contains('lib/core/services/service_locator.dart', 'managedRootResolver: asrManagedStorageService.resolveRoot')
