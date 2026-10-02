import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import 'transcription_config_dialog.dart';

class AsrRuntimeSetupDialog extends StatefulWidget {
  final TranscriptionConfig? initialConfig;

  const AsrRuntimeSetupDialog({
    super.key,
    this.initialConfig,
  });

  @override
  State<AsrRuntimeSetupDialog> createState() =>
      _AsrRuntimeSetupDialogState();
}

class _AsrRuntimeSetupDialogState extends State<AsrRuntimeSetupDialog> {
  late final AsrRuntimeManager _runtimeManager;
  late TranscriptionConfig _config;

  StreamSubscription<AsrRuntimeInstallProgress>? _progressSubscription;
  AsrRuntimeStatus? _status;
  AsrRuntimeInstallProgress? _installProgress;
  bool _loading = true;
  bool _installing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runtimeManager = ServiceLocatorGlobal.I.asrRuntimeManager;
    _config = widget.initialConfig ??
        const TranscriptionConfig(
          mode: TranscriptionMode.highestQuality,
          profilePreference: TranscriptionProfilePreference.automatic,
          qwenExecutable: 'qwen3-asr',
          whisperExecutable: 'whisper-cli',
          modelPath: '',
        );

    _progressSubscription =
        _runtimeManager.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() => _installProgress = progress);
    });

    unawaited(_refresh());
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repaired = await _runtimeManager.repair(_config);
      final status = await _runtimeManager.inspect(repaired);
      if (!mounted) return;
      setState(() {
        _config = repaired;
        _status = status;
      });
    } on TranscriptionException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '检测识别环境失败：' + error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _error = null;
      _installProgress = const AsrRuntimeInstallProgress(
        progress: 0,
        message: '准备自动安装本地识别环境',
      );
    });

    try {
      final installed =
          await _runtimeManager.installRecommended(_config);
      if (!mounted) return;
      setState(() => _config = installed);
      await _refresh();
    } on TranscriptionException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '安装识别环境失败：' + error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
          _installProgress = null;
        });
      }
    }
  }

  Future<void> _cancelInstall() async {
    await _runtimeManager.cancel();
  }

  Future<void> _openAdvanced() async {
    final updated = await showDialog<TranscriptionConfig>(
      context: context,
      builder: (context) => TranscriptionConfigDialog(
        initialConfig: _config,
      ),
    );
    if (updated == null || !mounted) return;

    setState(() => _config = updated);
    await _refresh();
  }

  String _hardwareSummary(TranscriptionHardwareInfo hardware) {
    final parts = <String>[
      hardware.operatingSystem + ' / ' + hardware.architecture,
      if (hardware.cpuName != null && hardware.cpuName!.trim().isNotEmpty)
        hardware.cpuName!.trim(),
      if (hardware.gpuName != null && hardware.gpuName!.trim().isNotEmpty)
        hardware.gpuName!.trim(),
      if (hardware.gpuMemoryMb != null)
        (hardware.gpuMemoryMb! / 1024).toStringAsFixed(0) + ' GB VRAM',
      if (hardware.systemMemoryMb != null)
        (hardware.systemMemoryMb! / 1024).toStringAsFixed(0) + ' GB RAM',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final ready = status?.isReady == true;

    return PopScope(
      canPop: !_installing,
      child: AlertDialog(
        title: const Text('本地歌词识别环境'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<TranscriptionMode>(
                  initialValue: _config.mode,
                  decoration: const InputDecoration(
                    labelText: '识别方案',
                    helperText: '不需要选择模型文件，LyricForge 会自动匹配',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: TranscriptionMode.highestQuality,
                      child: Text('最高质量 · 双引擎校对（推荐）'),
                    ),
                    DropdownMenuItem(
                      value: TranscriptionMode.whisperOnly,
                      child: Text('Whisper 单模型 · 更省空间'),
                    ),
                  ],
                  onChanged: _installing
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _config = _config.copyWith(mode: value);
                          });
                          unawaited(_refresh());
                        },
                ),
                const SizedBox(height: AppSpacing.md),
                if (status != null)
                  _ProfileSummary(
                    title: status.profile.label,
                    description: status.profile.description,
                    hardware:
                        _hardwareSummary(status.profile.hardware),
                    ready: ready,
                  )
                else if (_loading)
                  const _LoadingCard(),
                const SizedBox(height: AppSpacing.md),
                if (status != null) ...[
                  Text(
                    ready
                        ? '识别环境已就绪'
                        : '首次使用需要准备以下组件',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...status.components.map(
                    (component) =>
                        _ComponentRow(component: component),
                  ),
                ],
                if (_installing && _installProgress != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  LinearProgressIndicator(
                    value: _installProgress!.progress,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _installProgress!.message,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '模型文件较大。可以离开电脑等待，LyricForge 会自动完成路径和模型配置。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(24),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMedium),
                      border: Border.all(
                        color: AppColors.error.withAlpha(80),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.error,
                          ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(
                  '普通使用不需要填写任何路径。LyricForge 会把运行时和模型放到应用自己的目录并自动记录。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_installing)
            TextButton(
              onPressed: _cancelInstall,
              child: const Text('取消安装'),
            )
          else ...[
            if (!ready)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('稍后'),
              ),
            TextButton(
              onPressed: _openAdvanced,
              child: const Text('高级设置'),
            ),
            TextButton(
              onPressed: _loading ? null : _refresh,
              child: const Text('重新检测'),
            ),
            if (!ready)
              FilledButton.icon(
                onPressed: _loading ? null : _install,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('自动安装识别环境'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.pop(context, _config),
                child: const Text('完成'),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  final String title;
  final String description;
  final String hardware;
  final bool ready;

  const _ProfileSummary({
    required this.title,
    required this.description,
    required this.hardware,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(
          color: ready
              ? AppColors.success.withAlpha(100)
              : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready
                ? Icons.check_circle
                : Icons.computer_outlined,
            color: ready ? AppColors.success : AppColors.info,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hardware,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.sm),
          Text('正在检测电脑配置和已有模型…'),
        ],
      ),
    );
  }
}

class _ComponentRow extends StatelessWidget {
  final AsrRuntimeComponentStatus component;

  const _ComponentRow({
    required this.component,
  });

  @override
  Widget build(BuildContext context) {
    final state = component.state;
    final ready = state == AsrRuntimeComponentState.ready;
    final unavailable = state == AsrRuntimeComponentState.unavailable;

    final icon = ready
        ? Icons.check_circle
        : unavailable
            ? Icons.tune
            : Icons.radio_button_unchecked;
    final color = ready
        ? AppColors.success
        : unavailable
            ? AppColors.warning
            : AppColors.textTertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  component.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  component.detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
          Text(
            ready
                ? '已安装'
                : unavailable
                    ? '高级'
                    : '待安装',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}
