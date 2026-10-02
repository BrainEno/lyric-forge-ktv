import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/transcription_models.dart';

class TranscriptionConfigDialog extends StatefulWidget {
  final TranscriptionConfig? initialConfig;

  const TranscriptionConfigDialog({
    super.key,
    this.initialConfig,
  });

  @override
  State<TranscriptionConfigDialog> createState() =>
      _TranscriptionConfigDialogState();
}

class _TranscriptionConfigDialogState
    extends State<TranscriptionConfigDialog> {
  late final TextEditingController _qwenExecutableController;
  late final TextEditingController _qwenModelController;
  late final TextEditingController _qwenAlignerController;
  late final TextEditingController _whisperController;
  late final TextEditingController _whisperModelController;
  late final TextEditingController _ffmpegController;

  late TranscriptionMode _mode;
  late String _language;
  late int _fallbackThreshold;
  late int _maxFallbackSegments;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;

    _mode = config?.mode ?? TranscriptionMode.highestQuality;
    _qwenExecutableController = TextEditingController(
      text: config?.qwenExecutable ?? 'qwen3-asr',
    );
    _qwenModelController = TextEditingController(
      text: config?.qwenModelPath ?? 'Qwen/Qwen3-ASR-1.7B',
    );
    _qwenAlignerController = TextEditingController(
      text: config?.qwenAlignerModelPath ?? 'Qwen/Qwen3-ForcedAligner-0.6B',
    );
    _whisperController = TextEditingController(
      text: config?.whisperExecutable ?? 'whisper-cli',
    );
    _whisperModelController = TextEditingController(
      text: config?.modelPath ?? '',
    );
    _ffmpegController = TextEditingController(
      text: config?.ffmpegExecutable ?? 'ffmpeg',
    );
    _language = config?.language ?? 'auto';
    _fallbackThreshold = config?.fallbackConfidenceThreshold ?? 70;
    _maxFallbackSegments = config?.maxFallbackSegments ?? 12;
  }

  @override
  void dispose() {
    _qwenExecutableController.dispose();
    _qwenModelController.dispose();
    _qwenAlignerController.dispose();
    _whisperController.dispose();
    _whisperModelController.dispose();
    _ffmpegController.dispose();
    super.dispose();
  }

  Future<void> _pickFileInto(TextEditingController controller) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path != null && path.isNotEmpty) {
      controller.text = path;
    }
  }

  Future<void> _pickDirectoryInto(TextEditingController controller) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null && path.isNotEmpty) {
      controller.text = path;
    }
  }

  void _submit() {
    final config = TranscriptionConfig(
      mode: _mode,
      qwenExecutable: _qwenExecutableController.text.trim(),
      qwenModelPath: _qwenModelController.text.trim(),
      qwenAlignerModelPath: _qwenAlignerController.text.trim(),
      qwenDevice: 'cuda',
      qwenDtype: 'bf16',
      whisperExecutable: _whisperController.text.trim(),
      modelPath: _whisperModelController.text.trim(),
      ffmpegExecutable: _ffmpegController.text.trim(),
      language: _language,
      fallbackConfidenceThreshold: _fallbackThreshold,
      maxFallbackSegments: _maxFallbackSegments,
    );

    if (!config.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _mode == TranscriptionMode.highestQuality
                ? '最高质量模式需要完整配置 Qwen3-ASR、ForcedAligner、Whisper 和 FFmpeg'
                : '请完整填写 Whisper、模型和 FFmpeg 配置',
          ),
        ),
      );
      return;
    }

    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    final highQuality = _mode == TranscriptionMode.highestQuality;

    return AlertDialog(
      title: const Text('本地歌词识别设置'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<TranscriptionMode>(
                initialValue: _mode,
                decoration: const InputDecoration(
                  labelText: '识别模式',
                ),
                items: const [
                  DropdownMenuItem(
                    value: TranscriptionMode.highestQuality,
                    child: Text('最高质量 · Qwen 1.7B + 对齐 + Whisper 复核'),
                  ),
                  DropdownMenuItem(
                    value: TranscriptionMode.whisperOnly,
                    child: Text('仅 Whisper · 兼容模式'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _mode = value);
                },
              ),
              if (highQuality) ...[
                const SizedBox(height: AppSpacing.md),
                _InfoCard(
                  title: 'RTX 高质量运行策略',
                  body:
                      'Qwen3-ASR 1.7B 使用 CUDA / BF16 常驻本地 sidecar；ForcedAligner 负责主时间轴。只把可疑片段交给 Whisper large-v3 复核。',
                ),
                const SizedBox(height: AppSpacing.md),
                _PathField(
                  controller: _qwenExecutableController,
                  label: 'Qwen3-ASR native runtime',
                  hint: 'qwen3-asr.exe 或 PATH 中的 qwen3-asr',
                  onBrowse: () => _pickFileInto(_qwenExecutableController),
                ),
                const SizedBox(height: AppSpacing.md),
                _PathField(
                  controller: _qwenModelController,
                  label: 'Qwen3-ASR 1.7B 模型 ID / 目录',
                  hint: 'Qwen/Qwen3-ASR-1.7B 或本地模型目录',
                  onBrowse: () => _pickDirectoryInto(_qwenModelController),
                ),
                const SizedBox(height: AppSpacing.md),
                _PathField(
                  controller: _qwenAlignerController,
                  label: 'Qwen3 ForcedAligner 0.6B 模型 ID / 目录',
                  hint: 'Qwen/Qwen3-ForcedAligner-0.6B 或本地模型目录',
                  onBrowse: () => _pickDirectoryInto(_qwenAlignerController),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _PathField(
                controller: _whisperController,
                label: highQuality
                    ? 'Whisper fallback runtime'
                    : 'whisper-cli',
                hint: 'whisper-cli.exe 或 PATH 中的 whisper-cli',
                onBrowse: () => _pickFileInto(_whisperController),
              ),
              const SizedBox(height: AppSpacing.md),
              _PathField(
                controller: _whisperModelController,
                label: highQuality
                    ? 'Whisper large-v3 fallback 模型'
                    : 'Whisper 模型',
                hint: highQuality
                    ? '建议 ggml-large-v3.bin'
                    : '例如 ggml-medium.bin',
                onBrowse: () => _pickFileInto(_whisperModelController),
              ),
              const SizedBox(height: AppSpacing.md),
              _PathField(
                controller: _ffmpegController,
                label: 'FFmpeg',
                hint: 'ffmpeg.exe 或 PATH 中的 ffmpeg',
                onBrowse: () => _pickFileInto(_ffmpegController),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(labelText: '识别语言'),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('自动检测')),
                  DropdownMenuItem(value: 'zh', child: Text('中文')),
                  DropdownMenuItem(value: 'en', child: Text('英文')),
                  DropdownMenuItem(value: 'ja', child: Text('日文')),
                  DropdownMenuItem(value: 'ko', child: Text('韩文')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _language = value);
                },
              ),
              if (highQuality) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<int>(
                  initialValue: _fallbackThreshold,
                  decoration: const InputDecoration(
                    labelText: '备用识别触发阈值',
                    helperText: '分数越高，越多可疑行会交给 Whisper 复核',
                  ),
                  items: const [
                    DropdownMenuItem(value: 60, child: Text('60 · 保守')),
                    DropdownMenuItem(value: 70, child: Text('70 · 推荐')),
                    DropdownMenuItem(value: 80, child: Text('80 · 严格')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _fallbackThreshold = value);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<int>(
                  initialValue: _maxFallbackSegments,
                  decoration: const InputDecoration(
                    labelText: '单曲最多复核片段',
                  ),
                  items: const [
                    DropdownMenuItem(value: 8, child: Text('8')),
                    DropdownMenuItem(value: 12, child: Text('12 · 推荐')),
                    DropdownMenuItem(value: 20, child: Text('20 · 更彻底')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _maxFallbackSegments = value);
                    }
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                '识别完全在桌面本地执行。输入优先使用已分离的人声；没有人声轨时回退标准化音频或原声。自动结果始终作为可编辑歌词草稿。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _InfoCard({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(body, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PathField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback onBrowse;

  const _PathField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: IconButton(
          tooltip: '选择路径',
          onPressed: onBrowse,
          icon: const Icon(Icons.folder_open_outlined),
        ),
      ),
    );
  }
}
