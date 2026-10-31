import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// A single low-friction entry point for reusing models that an older
/// LyricForge install already downloaded somewhere else on this computer.
///
/// The actions deliberately do not ask the user to understand the internal
/// `LyricForge/ASRRuntime` layout. Automatic discovery is primary; pasting a
/// path and browsing are fallbacks. Recognition switches only the managed
/// root pointer and never starts a download by itself.
class AsrExistingModelCard extends StatelessWidget {
  final bool scanning;
  final String? message;
  final VoidCallback? onScan;
  final VoidCallback? onPastePath;
  final VoidCallback? onBrowse;

  const AsrExistingModelCard({
    super.key,
    required this.scanning,
    required this.onScan,
    required this.onPastePath,
    required this.onBrowse,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accent.withAlpha(12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.accent.withAlpha(56)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.travel_explore_rounded,
                size: 20,
                color: AppColors.accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已经下载过模型？',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '先在本机查找以前的 LyricForge ASRRuntime 并原地使用。此步骤只识别'
                      '已有文件：不复制、不删除，也不会开始下载。识别后若仍有组件缺失，'
                      '下方会单独列出原因。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (scanning || message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (scanning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(
                    Icons.fact_check_outlined,
                    size: 16,
                    color: AppColors.accent,
                  ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SelectableText(
                    message ?? '正在查找已有 ASRRuntime…（不会下载）',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: scanning ? null : onScan,
                icon: const Icon(Icons.saved_search_rounded, size: 18),
                label: Text(scanning ? '正在识别已有模型…' : '一键识别已有模型'),
              ),
              OutlinedButton.icon(
                onPressed: scanning ? null : onPastePath,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('粘贴路径识别'),
              ),
              TextButton.icon(
                onPressed: scanning ? null : onBrowse,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('浏览已有 ASRRuntime'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<String?> showAsrExistingModelPathDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _AsrExistingModelPathDialog(),
  );
}

class _AsrExistingModelPathDialog extends StatefulWidget {
  const _AsrExistingModelPathDialog();

  @override
  State<_AsrExistingModelPathDialog> createState() =>
      _AsrExistingModelPathDialogState();
}

class _AsrExistingModelPathDialogState
    extends State<_AsrExistingModelPathDialog> {
  final _controller = TextEditingController();

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  Future<void> _browse() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择磁盘、Models、LyricForge 或已有的 ASRRuntime',
    );
    if (!mounted || selected == null || selected.trim().isEmpty) return;
    _controller.text = selected;
    _controller.selection = TextSelection.collapsed(offset: selected.length);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('粘贴已有 ASRRuntime 路径'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '可以粘贴整盘、Models 容器、LyricForge、ASRRuntime，或 ASRRuntime '
              '内部的任意模型文件夹/文件；Elysium Player 会自动向上或向下找到已有环境。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 2,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: '已有模型路径',
                hintText: r'例如 D:\、D:\Models 或 D:\Models\LyricForge\ASRRuntime',
                prefixIcon: Icon(Icons.folder_open_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '此操作只切换到识别到的已有环境，不复制、不删除，也不会开始下载。',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton.icon(
          onPressed: _browse,
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: const Text('浏览文件夹'),
        ),
        FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: const Text('识别并使用'),
        ),
      ],
    );
  }
}
