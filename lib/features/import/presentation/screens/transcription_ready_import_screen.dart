import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/services/transcription_environment_preflight.dart';
import '../../../transcription/presentation/widgets/asr_runtime_setup_dialog.dart';
import 'import_audio_screen.dart';

/// Desktop-first onboarding gate for batch transcription.
///
/// Mobile keeps the existing import surface unchanged. Desktop users are asked
/// to prepare the local ASR runtime before they can enter the batch-import
/// screen, which prevents a first-use selection from turning into a paused or
/// failed queue after the work has already been submitted.
class TranscriptionReadyImportScreen extends StatefulWidget {
  final bool? desktopOverride;

  const TranscriptionReadyImportScreen({
    super.key,
    this.desktopOverride,
  });

  @override
  State<TranscriptionReadyImportScreen> createState() =>
      _TranscriptionReadyImportScreenState();
}

class _TranscriptionReadyImportScreenState
    extends State<TranscriptionReadyImportScreen> {
  TranscriptionEnvironmentPreflight? _preflight;
  TranscriptionEnvironmentReadiness? _readiness;
  bool _checking = false;
  bool _openingSetup = false;
  String? _actionError;

  bool get _isDesktop =>
      widget.desktopOverride ?? AppResponsive.isDesktopTarget();

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      final services = ServiceLocatorGlobal.I;
      _preflight = TranscriptionEnvironmentPreflight(
        settingsStore: services.transcriptionSettingsStore,
        runtimeManager: services.asrRuntimeManager,
      );
      unawaited(_refresh());
    }
  }

  @override
  void didUpdateWidget(covariant TranscriptionReadyImportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasDesktop =
        oldWidget.desktopOverride ?? AppResponsive.isDesktopTarget();
    if (!wasDesktop && _isDesktop && _preflight == null) {
      final services = ServiceLocatorGlobal.I;
      _preflight = TranscriptionEnvironmentPreflight(
        settingsStore: services.transcriptionSettingsStore,
        runtimeManager: services.asrRuntimeManager,
      );
      unawaited(_refresh());
    }
  }

  Future<TranscriptionEnvironmentReadiness?> _refresh() async {
    final preflight = _preflight;
    if (preflight == null || !mounted) return null;
    setState(() {
      _checking = true;
      _actionError = null;
    });

    final result = await preflight.inspect();
    if (!mounted) return result;
    setState(() {
      _readiness = result;
      _checking = false;
    });
    return result;
  }

  Future<void> _openSettings() async {
    if (!mounted) return;
    await Navigator.pushNamed(context, Routes.settings);
    final readiness = await _refresh();
    if (readiness?.isReady == true) {
      await _resumeEnvironmentBlockedQueueIfNeeded();
    }
  }

  Future<void> _prepareEnvironment() async {
    if (_openingSetup || !mounted) return;
    setState(() {
      _openingSetup = true;
      _actionError = null;
    });

    try {
      final services = ServiceLocatorGlobal.I;
      final current =
          _readiness?.config ?? await services.transcriptionSettingsStore.load();
      if (!mounted) return;

      final updated = await showDialog<TranscriptionConfig>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AsrRuntimeSetupDialog(
          initialConfig: current,
        ),
      );
      if (updated != null) {
        await services.transcriptionSettingsStore.save(updated);
      }

      final readiness = await _refresh();
      if (readiness?.isReady == true) {
        await _resumeEnvironmentBlockedQueueIfNeeded();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('本地歌词识别环境已准备好')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = '准备识别环境失败：$error');
      }
    } finally {
      if (mounted) setState(() => _openingSetup = false);
    }
  }

  Future<void> _resumeEnvironmentBlockedQueueIfNeeded() async {
    final queue = ServiceLocatorGlobal.I.transcriptionQueue;
    final snapshot = queue.current;
    if (!snapshot.isEnvironmentBlocked || snapshot.isProcessing) return;
    await queue.resume();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return const ImportAudioScreen();

    final readiness = _readiness;
    if (readiness?.isReady == true) {
      return const ImportAudioScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('批量导入'),
        backgroundColor: AppColors.bgBase,
      ),
      body: SafeArea(
        child: _ReadinessOnboarding(
          readiness: readiness,
          checking: _checking,
          openingSetup: _openingSetup,
          actionError: _actionError,
          onRefresh: _refresh,
          onPrepare: _prepareEnvironment,
          onOpenSettings: _openSettings,
        ),
      ),
    );
  }
}

class _ReadinessOnboarding extends StatelessWidget {
  final TranscriptionEnvironmentReadiness? readiness;
  final bool checking;
  final bool openingSetup;
  final String? actionError;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onPrepare;
  final Future<void> Function() onOpenSettings;

  const _ReadinessOnboarding({
    required this.readiness,
    required this.checking,
    required this.openingSetup,
    required this.actionError,
    required this.onRefresh,
    required this.onPrepare,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final state = readiness?.state;
    final missing = readiness?.blockingComponents ?? const <dynamic>[];
    final status = readiness?.status;
    final config = readiness?.config;

    final title = switch (state) {
      TranscriptionEnvironmentReadinessState.needsSetup =>
        '本地识别环境还没有准备完整',
      TranscriptionEnvironmentReadinessState.failed => '暂时无法确认识别环境',
      _ => '第一次识别前，先准备本地 AI 环境',
    };
    final description = switch (state) {
      TranscriptionEnvironmentReadinessState.needsSetup =>
        '检测到当前方案仍缺少 ${missing.length} 个组件。准备完成后，批量导入会自动进入后台队列。',
      TranscriptionEnvironmentReadinessState.failed =>
        '检测过程中出现问题。可以重新检测，或进入 AI 设置检查模型与运行时路径。',
      _ => '这一步只需要完成一次。Elysium Player 会检测电脑并准备模型与运行时，之后导入歌曲时不会再重复询问。',
    };

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          spec.pageGutter,
          spec.isShort ? AppSpacing.md : AppSpacing.xl,
          spec.pageGutter,
          spec.isShort ? AppSpacing.xl : AppSpacing.xxxl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.all(
                  spec.isCompact ? AppSpacing.md : AppSpacing.xl,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusXLarge),
                  border: Border.all(color: AppColors.borderMuted),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(24),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusLarge),
                      ),
                      child: Icon(
                        state == TranscriptionEnvironmentReadinessState.failed
                            ? Icons.warning_amber_rounded
                            : Icons.auto_awesome_rounded,
                        color: state ==
                                TranscriptionEnvironmentReadinessState.failed
                            ? AppColors.warning
                            : AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                    ),
                    if (checking) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusLarge),
                  border: Border.all(color: AppColors.borderMuted),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前检测结果',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ReadinessRow(
                      icon: Icons.tune_rounded,
                      label: '质量方案',
                      value: _modeLabel(config),
                    ),
                    _ReadinessRow(
                      icon: Icons.memory_rounded,
                      label: '推荐配置',
                      value: status?.profile.label ??
                          (config == null ? '尚未配置' : '等待检测'),
                    ),
                    _ReadinessRow(
                      icon: Icons.extension_rounded,
                      label: '组件状态',
                      value: status == null
                          ? '尚未完成检测'
                          : '${status.readyCount} / ${status.components.length} 已就绪',
                    ),
                    if (missing.isNotEmpty)
                      _ReadinessRow(
                        icon: Icons.download_for_offline_outlined,
                        label: '仍需准备',
                        value: missing
                            .take(3)
                            .map((item) => item.label.toString())
                            .join('、'),
                      ),
                    if (status != null)
                      _ReadinessRow(
                        icon: Icons.folder_outlined,
                        label: '安装目录',
                        value: status.managedRoot,
                        monospace: true,
                      ),
                  ],
                ),
              ),
              if (readiness?.error != null || actionError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(16),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMedium),
                    border: Border.all(color: AppColors.error.withAlpha(70)),
                  ),
                  child: Text(
                    actionError ?? readiness!.error!,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 560 || spec.isShort;
                  final prepare = FilledButton.icon(
                    onPressed: openingSetup ? null : onPrepare,
                    icon: openingSetup
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.pureWhite,
                            ),
                          )
                        : const Icon(Icons.download_for_offline_rounded),
                    label: Text(
                      openingSetup ? '正在准备...' : '一键准备识别环境',
                    ),
                  );
                  final settings = OutlinedButton.icon(
                    onPressed: openingSetup ? null : onOpenSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('打开 AI 设置'),
                  );
                  final refresh = TextButton.icon(
                    onPressed: checking || openingSetup ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新检测'),
                  );

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: spec.minimumInteractiveExtent,
                          child: prepare,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          height: spec.minimumInteractiveExtent,
                          child: settings,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        refresh,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: spec.minimumInteractiveExtent,
                          child: prepare,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: SizedBox(
                          height: spec.minimumInteractiveExtent,
                          child: settings,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      refresh,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '已有后台任务不会丢失。如果队列之前因为缺少模型而自动暂停，环境准备完成后会自动继续；用户手动暂停的队列不会被擅自恢复。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                      height: 1.45,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _modeLabel(TranscriptionConfig? config) {
    if (config == null) return '最高质量 · 自动推荐';
    return switch (config.mode) {
      TranscriptionMode.highestQuality =>
        '最高质量 · Qwen + ForcedAligner + Whisper',
      TranscriptionMode.whisperOnly => 'Whisper 单模型',
    };
  }
}

class _ReadinessRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool monospace;

  const _ReadinessRow({
    required this.icon,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: monospace ? 'monospace' : null,
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
