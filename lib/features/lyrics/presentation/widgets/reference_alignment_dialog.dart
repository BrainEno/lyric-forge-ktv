import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_button_spinner.dart';
import '../../domain/models/reference_lyric_input.dart';
import '../../domain/services/reference_lyric_text_parser.dart';

/// What the pasted reference lyrics will be used for.
///
/// One input dialog serves three flows. It used to be titled 参考歌词纠正 and
/// promise inferred timing in every case, so a user who had picked the
/// text-only correction was told the opposite of what would happen, and the
/// two menu entries could only be told apart by their subtitles (audit E-02).
/// The menu and the dialog now share one name per flow, and the two reference
/// flows read as a pair: 纠正文字和时间轴 versus 只改文字.
enum ReferenceLyricPurpose {
  /// Aligns the reference, can fill missed rows and replace timing.
  alignment(
    title: '参考歌词：纠正文字和时间轴',
    menuDetail: '有参考歌词；可补全漏行并重算时间轴',
    dialogDetail: '用正确的歌词文本纠正当前 ASR 草稿，并可补全漏行、推断时间；应用前会自动备份。',
  ),

  /// Corrects the text row by row and keeps the existing timestamps.
  textOnly(
    title: '参考歌词：只改文字',
    menuDetail: '有参考歌词；逐行改正文字，时间戳保持不变',
    dialogDetail: '逐行比对参考歌词，只改正文字，现有时间戳保持不变；每一处改动应用前都可以复核。',
  ),

  /// Feeds the reference into the smart proofreading proposal.
  proposal(
    title: '智能校对：提供参考歌词',
    menuDetail: null,
    dialogDetail: '参考歌词会作为智能校对的优先依据；生成的是提案，逐行确认后才会写入歌词。',
  );

  const ReferenceLyricPurpose({
    required this.title,
    required this.menuDetail,
    required this.dialogDetail,
  });

  /// Dialog title, and the menu title of the flows that have a menu entry.
  final String title;

  /// One-line menu subtitle; null for flows reached from another dialog.
  final String? menuDetail;

  /// The explanation under the dialog title.
  final String dialogDetail;
}

Future<ReferenceLyricInput?> showReferenceAlignmentDialog(
  BuildContext context, {
  required ReferenceLyricTextParser parser,
  required String initialTitle,
  String? initialArtist,
  ReferenceLyricPurpose purpose = ReferenceLyricPurpose.alignment,
}) {
  return showDialog<ReferenceLyricInput>(
    context: context,
    builder: (_) => ReferenceAlignmentDialog(
      parser: parser,
      initialTitle: initialTitle,
      initialArtist: initialArtist,
      purpose: purpose,
    ),
  );
}

enum _ReferenceInputMode { paste, file }

class ReferenceAlignmentDialog extends StatefulWidget {
  final ReferenceLyricTextParser parser;
  final String initialTitle;
  final String? initialArtist;

  /// Which flow the reference is for; sets the title and the explanation.
  final ReferenceLyricPurpose purpose;

  const ReferenceAlignmentDialog({
    super.key,
    required this.parser,
    required this.initialTitle,
    this.initialArtist,
    this.purpose = ReferenceLyricPurpose.alignment,
  });

  @override
  State<ReferenceAlignmentDialog> createState() =>
      _ReferenceAlignmentDialogState();
}

class _ReferenceAlignmentDialogState extends State<ReferenceAlignmentDialog> {
  static const _encodingLabels = <String, String>{
    'auto': '自动检测（推荐）',
    'utf-8': 'UTF-8',
    'utf-16': 'UTF-16',
    'gbk': 'GBK / 中文 Windows',
    'shift_jis': 'Shift-JIS / 日文',
    'euc-jp': 'EUC-JP / 日文',
    'windows-1252': 'Windows-1252',
  };

  late final TextEditingController _pasteController;
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _offsetController;

  _ReferenceInputMode _mode = _ReferenceInputMode.paste;
  String _encodingValue = 'auto';
  String? _filePath;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pasteController = TextEditingController();
    _titleController = TextEditingController(text: widget.initialTitle);
    _artistController = TextEditingController(text: widget.initialArtist ?? '');
    _offsetController = TextEditingController();
  }

  @override
  void dispose() {
    _pasteController.dispose();
    _titleController.dispose();
    _artistController.dispose();
    _offsetController.dispose();
    super.dispose();
  }

  String get _pasteExtension =>
      ReferenceLyricTextParser.detectExtension(_pasteController.text);

  bool get _pasteHasText => _pasteController.text.trim().isNotEmpty;

  String? get _encodingHint => _encodingValue == 'auto' ? null : _encodingValue;

  String _formatLabel(String extension) {
    return switch (extension) {
      'lrc' => 'LRC · 带时间戳',
      'srt' => 'SRT · 带时间戳',
      'vtt' => 'WebVTT · 带时间戳',
      'ass' || 'ssa' => 'ASS · 带时间戳',
      _ => '纯文本 · 仅纠正文字',
    };
  }

  Future<void> _pickFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: '选择参考歌词文件',
        type: FileType.custom,
        allowedExtensions: widget.parser.supportedExtensions.toList()..sort(),
        allowMultiple: false,
      );
      final path = picked?.files.single.path;
      if (path == null || path.isEmpty || !mounted) return;
      setState(() {
        _filePath = path;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '无法打开文件选择器：$error');
    }
  }

  Duration? _parseOffset() {
    final raw = _offsetController.text.trim();
    if (raw.isEmpty) return Duration.zero;

    final value = int.tryParse(raw);
    if (value == null) {
      setState(() => _error = '整体偏移必须是整数毫秒');
      return null;
    }
    if (value.abs() > 600000) {
      setState(() => _error = '整体偏移请控制在 ±10 分钟以内');
      return null;
    }
    return Duration(milliseconds: value);
  }

  Future<ReferenceLyricInput> _parseFile(Duration offset) {
    final path = _filePath;
    if (path == null) {
      throw const ReferenceLyricParseException('请先选择参考歌词文件');
    }
    return widget.parser.parseFile(
      path,
      encodingHint: _encodingHint,
      offset: offset,
      title: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      artist: _artistController.text.trim().isEmpty
          ? null
          : _artistController.text.trim(),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    final offset = _parseOffset();
    if (offset == null) {
      setState(() => _busy = false);
      return;
    }

    try {
      final title = _titleController.text.trim();
      final artist = _artistController.text.trim();
      final input = _mode == _ReferenceInputMode.paste
          ? widget.parser.parsePasted(
              _pasteController.text,
              offset: offset,
              title: title.isEmpty ? null : title,
              artist: artist.isEmpty ? null : artist,
            )
          : await _parseFile(offset);
      if (!mounted) return;
      Navigator.of(context).pop(input);
    } on ReferenceLyricParseException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '解析参考歌词失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final media = MediaQuery.of(context);
    final maxWidth = spec.isCompact ? 560.0 : 620.0;
    final maxHeight =
        (media.size.height -
                media.viewInsets.bottom -
                spec.pageGutter * 2 -
                120)
            .clamp(240.0, 680.0)
            .toDouble();

    // AlertDialog measures its content with intrinsics, so this width must not
    // come from a LayoutBuilder. Estimate it from the viewport and the same
    // inset/padding applied below, then decide whether the two metadata fields
    // still fit side by side.
    final dialogWidth = (media.size.width - spec.pageGutter * 2)
        .clamp(0.0, maxWidth)
        .toDouble();
    final contentWidth = (dialogWidth - spec.pageGutter * 2).clamp(
      0.0,
      double.infinity,
    );
    final stackMetadataFields = contentWidth < 460;

    final titleField = TextField(
      controller: _titleController,
      decoration: const InputDecoration(labelText: '参考歌名', isDense: true),
    );
    final artistField = TextField(
      controller: _artistController,
      decoration: const InputDecoration(labelText: '参考艺术家', isDense: true),
    );

    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      insetPadding: EdgeInsets.all(spec.pageGutter),
      titlePadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        spec.pageGutter,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        0,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      actionsPadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        spec.pageGutter,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.purpose.title),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.purpose.dialogDetail,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<_ReferenceInputMode>(
                segments: const [
                  ButtonSegment(
                    value: _ReferenceInputMode.paste,
                    icon: Icon(Icons.content_paste_rounded, size: 18),
                    label: Text('粘贴'),
                  ),
                  ButtonSegment(
                    value: _ReferenceInputMode.file,
                    icon: Icon(Icons.folder_open_rounded, size: 18),
                    label: Text('文件'),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (values) {
                  setState(() {
                    _mode = values.first;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (_mode == _ReferenceInputMode.paste) ...[
                TextField(
                  controller: _pasteController,
                  minLines: 6,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '参考歌词',
                    hintText: '粘贴纯文本或 LRC 歌词\n例如：\n[00:12.34]月亮代表我的心',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _pasteHasText
                      ? '识别为：${_formatLabel(_pasteExtension)}'
                      : '纯文本会纠正文字并补全漏行（按相邻行推断时间）；LRC/SRT 等带时间戳的文本还可选择采用参考时间轴。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _pasteHasText
                        ? AppColors.textSecondary
                        : AppColors.textTertiary,
                  ),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(0, spec.minimumInteractiveExtent),
                  ),
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(_filePath == null ? '选择歌词文件' : '重新选择文件'),
                ),
                if (_filePath != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _SelectedFileSummary(
                    fileName: _filePath!.split(Platform.pathSeparator).last,
                    formatLabel: _formatLabel(
                      _filePath!.split('.').last.toLowerCase(),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  key: ValueKey(_encodingValue),
                  initialValue: _encodingValue,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '文本编码',
                    prefixIcon: Icon(Icons.translate_rounded),
                  ),
                  items: [
                    for (final entry in _encodingLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _encodingValue = value);
                          }
                        },
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '自动检测失败时，可手动选择 GBK 或日文编码后重试。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                '溯源信息（可选）',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '只写入当前工程的 metadata，方便以后知道这版歌词来自哪里，不做在线校验。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (stackMetadataFields)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    titleField,
                    const SizedBox(height: AppSpacing.sm),
                    artistField,
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: titleField),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: artistField),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _offsetController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: '时间轴整体偏移',
                  helperText: '正数让参考歌词整体延后；仅对带时间戳的参考生效。',
                  suffixText: 'ms',
                  isDense: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(20),
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusMedium,
                    ),
                    border: Border.all(color: AppColors.error.withAlpha(80)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: AppColors.errorText,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.errorText),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            minimumSize: Size(0, spec.minimumInteractiveExtent),
          ),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: Size(0, spec.minimumInteractiveExtent),
          ),
          icon: _busy
              ? const AppButtonSpinner(size: 16)
              : const Icon(Icons.auto_fix_high_rounded),
          label: Text(_busy ? '解析中…' : '开始对齐'),
        ),
      ],
    );
  }
}

class _SelectedFileSummary extends StatelessWidget {
  final String fileName;
  final String formatLabel;

  const _SelectedFileSummary({
    required this.fileName,
    required this.formatLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(Icons.lyrics_outlined, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  formatLabel,
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
