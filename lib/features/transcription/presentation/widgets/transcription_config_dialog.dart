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
  late final TextEditingController _whisperController;
  late final TextEditingController _modelController;
  late final TextEditingController _ffmpegController;
  late String _language;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _whisperController = TextEditingController(
      text: config?.whisperExecutable ?? 'whisper-cli',
    );
    _modelController = TextEditingController(text: config?.modelPath ?? '');
    _ffmpegController = TextEditingController(
      text: config?.ffmpegExecutable ?? 'ffmpeg',
    );
    _language = config?.language ?? 'auto';
  }

  @override
  void dispose() {
    _whisperController.dispose();
    _modelController.dispose();
    _ffmpegController.dispose();
    super.dispose();
  }

  Future<void> _pickInto(TextEditingController controller) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path != null && path.isNotEmpty) {
      controller.text = path;
    }
  }

  void _submit() {
    final whisper = _whisperController.text.trim();
    final model = _modelController.text.trim();
    final ffmpeg = _ffmpegController.text.trim();

    if (whisper.isEmpty || model.isEmpty || ffmpeg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请完整填写 Whisper、模型和 FFmpeg 配置')),
      );
      return;
    }

    Navigator.pop(
      context,
      TranscriptionConfig(
        whisperExecutable: whisper,
        modelPath: model,
        ffmpegExecutable: ffmpeg,
        language: _language,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('本地歌词识别设置'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PathField(
                controller: _whisperController,
                label: 'whisper-cli',
                hint: '可填写 whisper-cli 或选择可执行文件',
                onBrowse: () => _pickInto(_whisperController),
              ),
              const SizedBox(height: AppSpacing.md),
              _PathField(
                controller: _modelController,
                label: 'Whisper 模型',
                hint: '例如 ggml-medium.bin',
                onBrowse: () => _pickInto(_modelController),
              ),
              const SizedBox(height: AppSpacing.md),
              _PathField(
                controller: _ffmpegController,
                label: 'FFmpeg',
                hint: '可填写 ffmpeg 或选择可执行文件',
                onBrowse: () => _pickInto(_ffmpegController),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(
                  labelText: '识别语言',
                ),
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
              const SizedBox(height: AppSpacing.md),
              Text(
                '识别完全在桌面本地执行。优先使用已分离的人声；没有人声轨时自动回退原音频。自动识别结果会作为可编辑歌词草稿。',
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
          tooltip: '选择文件',
          onPressed: onBrowse,
          icon: const Icon(Icons.folder_open_outlined),
        ),
      ),
    );
  }
}
