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
      setState(() => _error = '检测识别环境失败：$error');
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
      final installed = await _runtimeManager.installRecommended(_config);
      if (!mounted) return;
      setState(() => _config = installed);
      await _refresh();
    } on TranscriptionException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '安装识别环境失败：$error');
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
      '${hardware.operatingSystem} / ${hardware.architecture}',
      if (hardware.cpuName != null && hardware.cpuName!.trim().isNotEmpty)
        hardware.cpuName!.trim(),
      if (hardware.gpuName != null && hardware.gpuName!.trim().isNotEmpty)
        hardware.gpuName!.trim(),
      if (hardware.gpuMemoryMb != null)
        '${(hardware.gpuMemoryMb! / 1024).toStringAsFixed(0)} GB VRAM',
      if (hardware.systemMemoryMb != null)
        '${(hardware.systemMemoryMb! / 1024).toStringAsFixed(0)} GB RAM',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final ready = status?.isReady == true;
    final progress = _installProgress?.progress.clamp(0.0, 1.0).toDouble();

    return PopScope(
      canPop: !_installing,
      child: AlertDialog(
        titlePadding: EdgeInsets.zero,
        contentPadding: EdgeInsets.zero,
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        title: _SetupHeader(
          ready: ready,
          installing: _installing,
        ),
        content: SizedBox(
          width: 720,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 650),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SectionLabel(
                    number: '1',
                    title: '选择识别方案',
                    subtitle: '大多数电脑保持推荐选项即可，模型和路径由 LyricForge 自动处理。',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<TranscriptionMode>(
                    initialValue: _config.mode,
                    decoration: const InputDecoration(
                      labelText: '质量模式',
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
                  const SizedBox(height: AppSpacing.lg),
                  _SectionLabel(
                    number: '2',
                    title: '检查这台电脑',
                    subtitle: ready
                        ? '硬件与本地识别组件已经匹配完成。'
                        : '自动检查硬件，并选择最适合这台电脑的模型组合。',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (status != null)
                    _ProfileSummary(
                      title: status.profile.label,
                      description: status.profile.description,
                      hardware: _hardwareSummary(status.profile.hardware),
                      ready: ready,
                    )
                  else if (_loading)
                    const _LoadingCard(),
                  if (status != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ComponentsCard(
                      components: status.components,
                      ready: ready,
                    ),
                  ],
                  if (_installing && _installProgress != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _InstallProgressCard(
                      progress: progress ?? 0,
                      message: _installProgress!.message,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _ErrorCard(message: _error!),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMedium),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '普通使用不需要自己寻找模型、填写路径或设置运行参数。所有文件都会保存在 LyricForge 自己的应用目录中。',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                      height: 1.4,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          if (_installing)
            TextButton.icon(
              onPressed: _cancelInstall,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('取消安装'),
            )
          else ...[
            TextButton(
              onPressed: _openAdvanced,
              child: const Text('高级设置'),
            ),
            TextButton.icon(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重新检测'),
            ),
            if (!ready)
              FilledButton.icon(
                onPressed: _loading ? null : _install,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('一键准备识别环境'),
              )
            else
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, _config),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('开始使用'),
              ),
          ],
        ],
      ),
    );
  }
}

class _SetupHeader extends StatelessWidget {
  final bool ready;
  final bool installing;

  const _SetupHeader({required this.ready, required this.installing});

  @override
  Widget build(BuildContext context) {
    final color = ready ? AppColors.success : AppColors.accent;
    final title = ready
        ? '本地歌词识别已准备好'
        : installing
            ? '正在准备本地歌词识别'
            : '首次使用，只需完成一次准备';
    final subtitle = ready
        ? '之后可以直接导入歌曲并在后台生成歌词。'
        : 'LyricForge 会自动检测电脑、下载所需组件并完成配置。';

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXLarge),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            ),
            child: Icon(
              ready
                  ? Icons.check_rounded
                  : Icons.graphic_eq_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
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

class _SectionLabel extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _SectionLabel({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
          ),
          child: Text(
            number,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ),
        ),
      ],
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
    final accent = ready ? AppColors.success : AppColors.info;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(
          color: ready
              ? AppColors.success.withAlpha(90)
              : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withAlpha(22),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            child: Icon(
              ready ? Icons.check_circle_outline_rounded : Icons.memory_rounded,
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    Text(
                      ready ? '已就绪' : '自动推荐',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hardware,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
          Expanded(child: Text('正在检测电脑配置和已有模型…')),
        ],
      ),
    );
  }
}

class _ComponentsCard extends StatelessWidget {
  final List<AsrRuntimeComponentStatus> components;
  final bool ready;

  const _ComponentsCard({
    required this.components,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ready ? '本地组件' : '首次使用需要准备',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var index = 0; index < components.length; index++) ...[
            _ComponentRow(component: components[index]),
            if (index != components.length - 1)
              const Divider(
                height: AppSpacing.md,
                color: AppColors.borderMuted,
              ),
          ],
        ],
      ),
    );
  }
}

class _InstallProgressCard extends StatelessWidget {
  final double progress;
  final String message;

  const _InstallProgressCard({
    required this.progress,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accent.withAlpha(12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.accent.withAlpha(48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '正在自动准备',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: AppColors.bgHighlight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '模型文件较大，可以让电脑继续运行；下载、存放路径和配置都会自动完成。',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: AppColors.error.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '暂时无法完成准备',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
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

class _ComponentRow extends StatelessWidget {
  final AsrRuntimeComponentStatus component;

  const _ComponentRow({required this.component});

  @override
  Widget build(BuildContext context) {
    final state = component.state;
    final ready = state == AsrRuntimeComponentState.ready;
    final unavailable = state == AsrRuntimeComponentState.unavailable;
    final icon = ready
        ? Icons.check_circle_rounded
        : unavailable
            ? Icons.tune_rounded
            : Icons.radio_button_unchecked_rounded;
    final color = ready
        ? AppColors.success
        : unavailable
            ? AppColors.warning
            : AppColors.textTertiary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                component.label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                component.detail,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          ready
              ? '已准备'
              : unavailable
                  ? '需手动配置'
                  : '待准备',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
