import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/services/asr_end_to_end_smoke_test_service.dart';

class AsrEndToEndSmokeTestCard extends StatefulWidget {
  const AsrEndToEndSmokeTestCard({super.key});

  @override
  State<AsrEndToEndSmokeTestCard> createState() =>
      _AsrEndToEndSmokeTestCardState();
}

class _AsrEndToEndSmokeTestCardState
    extends State<AsrEndToEndSmokeTestCard> {
  late final AsrEndToEndSmokeTestService _smokeTestService;
  StreamSubscription<AsrEndToEndSmokeProgress>? _progressSubscription;

  AsrEndToEndSmokeProgress? _progress;
  AsrEndToEndSmokeResult? _lastResult;
  bool _running = false;
  String? _error;

  bool get _desktopSupported => Platform.isWindows || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _smokeTestService = ServiceLocatorGlobal.I.asrEndToEndSmokeTestService;
    _progressSubscription = _smokeTestService.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() => _progress = progress);
    });
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _runSmokeTest() async {
    if (!_desktopSupported || _running) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'flac', 'wav', 'm4a', 'aac', 'ogg'],
      allowMultiple: false,
      dialogTitle: '选择一首真实音频进行 ASR 端到端自检',
    );
    if (picked == null || picked.files.isEmpty) return;

    final path = picked.files.single.path;
    if (path == null || path.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _error = '没有取得所选音频的本地路径');
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _lastResult = null;
      _progress = const AsrEndToEndSmokeProgress(
        stage: AsrEndToEndSmokeStage.validatingAudio,
        progress: 0,
        message: '准备开始端到端自检',
      );
    });

    try {
      final result = await _smokeTestService.run(path);
      if (!mounted) return;
      setState(() => _lastResult = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ASR 端到端自检通过：生成 ${result.lyricLineCount} 行歌词',
          ),
        ),
      );
      await Navigator.pushNamed(
        context,
        Routes.lyricEditorPath(result.projectId),
      );
    } on TranscriptionException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'ASR 端到端自检失败：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _cancel() async {
    await _smokeTestService.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress?.progress.clamp(0.0, 1.0).toDouble() ?? 0;
    final result = _lastResult;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
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
                child: const Icon(Icons.fact_check_outlined),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '真实音频端到端自检',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '选择一首本机真实音频。应用会检查并自动准备 runtime / 模型，创建工程，执行生产 ASR，验证非空歌词与转写元数据，然后自动打开歌词校对页。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.bgBase,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              border: Border.all(color: AppColors.borderMuted),
            ),
            child: Text(
              _desktopSupported
                  ? '首次运行可能需要下载数 GB 的识别 runtime 与模型。自检会保留生成的“· ASR 自检”工程，便于你直接检查真实歌词和时间轴。'
                  : '真实 ASR 自检目前只在 Windows / macOS 桌面端开放。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
          ),
          if (_running && _progress != null) ...[
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _progress!.message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(18),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                border: Border.all(color: AppColors.error.withAlpha(90)),
              ),
              child: Text(_error!),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(18),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                border: Border.all(color: AppColors.success.withAlpha(90)),
              ),
              child: Text(
                '上次自检通过：${result.projectName} · ${result.lyricLineCount} 行歌词'
                '${result.environmentInstalled ? ' · 本次自动准备了识别环境' : ' · 使用已有识别环境'}',
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: !_desktopSupported || _running ? null : _runSmokeTest,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('选择真实音频并开始自检'),
              ),
              if (_running)
                OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('取消自检'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
