import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/services/asr_end_to_end_smoke_test_service.dart';
import 'settings_section_card.dart';

/// Picks the audio file for a trial run; null when the user cancels.
typedef SmokeTestAudioPicker = Future<String?> Function();

/// 试识别一首歌: runs one real song through the production recognition path
/// and opens the result in the lyric editor.
///
/// It used to be a developer smoke test placed between the recognition
/// settings and diagnostics, titled 真实音频端到端自检 and explained in terms
/// of runtime, production ASR and pipelines (audit SE-05). It now sits under
/// 故障排查 and says in plain words what it does and does not prove.
class AsrEndToEndSmokeTestCard extends StatefulWidget {
  final AsrEndToEndSmokeTestService smokeTestService;

  /// Replaces the system file dialog; tests pass a fixed path.
  final SmokeTestAudioPicker? pickAudio;

  /// Overrides the platform check (Windows and macOS only).
  final bool? desktopSupported;

  const AsrEndToEndSmokeTestCard({
    super.key,
    required this.smokeTestService,
    this.pickAudio,
    this.desktopSupported,
  });

  static const List<String> audioExtensions = [
    'mp3',
    'flac',
    'wav',
    'm4a',
    'aac',
    'ogg',
  ];

  @override
  State<AsrEndToEndSmokeTestCard> createState() =>
      _AsrEndToEndSmokeTestCardState();
}

class _AsrEndToEndSmokeTestCardState extends State<AsrEndToEndSmokeTestCard> {
  late final AsrEndToEndSmokeTestService _smokeTestService;
  StreamSubscription<AsrEndToEndSmokeProgress>? _progressSubscription;

  AsrEndToEndSmokeProgress? _progress;
  AsrEndToEndSmokeResult? _lastResult;
  bool _running = false;
  String? _error;

  bool get _desktopSupported =>
      widget.desktopSupported ?? (Platform.isWindows || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _smokeTestService = widget.smokeTestService;
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

  Future<String?> _pickWithSystemDialog() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AsrEndToEndSmokeTestCard.audioExtensions,
      allowMultiple: false,
      dialogTitle: '选择一首歌试识别',
    );
    if (picked == null || picked.files.isEmpty) return null;
    return picked.files.single.path ?? '';
  }

  Future<void> _runSmokeTest() async {
    if (!_desktopSupported || _running) return;

    final path = await (widget.pickAudio ?? _pickWithSystemDialog)();
    if (path == null) return;
    if (path.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _error = '没有取得所选歌曲的文件路径');
      return;
    }
    if (!mounted) return;

    setState(() {
      _running = true;
      _error = null;
      _lastResult = null;
      _progress = const AsrEndToEndSmokeProgress(
        stage: AsrEndToEndSmokeStage.validatingAudio,
        progress: 0,
        message: '正在准备试识别',
      );
    });

    try {
      final result = await _smokeTestService.run(path);
      if (!mounted) return;
      setState(() => _lastResult = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '试识别完成，生成了 ${result.lyricLineCount} 行歌词。请在校对页检查内容是否准确。',
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
      setState(() => _error = '试识别失败：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _cancel() async {
    await _smokeTestService.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final progress = _progress;
    final result = _lastResult;
    final error = _error;

    return SettingsSectionCard(
      icon: Icons.fact_check_outlined,
      title: '试识别一首歌',
      subtitle:
          '选一首本机歌曲完整跑一遍识别：需要时自动准备识别环境，生成歌词后打开校对页。'
          '它只确认识别能正常工作，不代表歌词准确。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _desktopSupported
                ? '第一次可能需要下载几 GB 的识别模型。试识别生成的工程会保留在工程列表里，可以直接检查或删除。'
                : '试识别目前只能在 Windows 和 macOS 电脑上使用。',
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          if (_running && progress != null) ...[
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(
              value: progress.progress.clamp(0.0, 1.0).toDouble(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              progress.message,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Notice(message: error, color: AppColors.error),
          ],
          if (result != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Notice(message: lastRunSummary(result), color: AppColors.success),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: !_desktopSupported || _running
                    ? null
                    : _runSmokeTest,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('选择歌曲开始试识别'),
              ),
              if (_running)
                OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('取消试识别'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One line about the last finished trial run.
String lastRunSummary(AsrEndToEndSmokeResult result) {
  final environment = result.environmentInstalled
      ? '本次自动准备了识别环境'
      : '使用了已有的识别环境';
  return '上次试识别：${result.projectName} · '
      '${result.lyricLineCount} 行歌词 · $environment';
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(message),
    );
  }
}
