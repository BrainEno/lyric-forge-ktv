import 'package:flutter/material.dart';

import '../../../../core/layout/app_capabilities.dart';
import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../lyrics/domain/online/song_lyrics_lookup.dart';
import '../../../lyrics/domain/services/lyric_file_import_service.dart';
import '../../../lyrics/domain/services/reference_lyric_text_parser.dart';
import '../../../project/domain/models/lyric_timing.dart';

/// Parses pasted lyrics the way the dialog will save them.
///
/// Pure so the rules can be tested without a widget: the text format is
/// detected from its content (LRC, SRT, WebVTT, ASS or plain text), and
/// [stripTimestamps] turns timed text into reference text. Returns null when
/// nothing usable is left.
LyricImportResult? parsePastedLyrics(
  LyricFileImportService importer,
  String text, {
  bool stripTimestamps = false,
}) {
  if (text.trim().isEmpty) return null;
  final extension = ReferenceLyricTextParser.detectExtension(text);
  LyricImportResult parsed;
  try {
    parsed = importer.parseText(text, extension: extension);
  } on LyricImportException {
    if (extension == 'txt') return null;
    // Text that only looks timed (a stray "[00:12]" in prose) is still
    // worth keeping as plain lines.
    try {
      parsed = importer.parseText(text, extension: 'txt');
    } on LyricImportException {
      return null;
    }
  }
  if (parsed.document.lines.isEmpty) return null;
  final result = stripTimestamps || parsed.document.isUntimed
      ? untimedImportResult(parsed)
      : parsed;
  final document = result.document;
  return LyricImportResult(
    document: document.copyWith(
      metadata: {...document.metadata, 'source': pastedLyricsSource},
    ),
    format: result.format,
    sourcePath: '',
    detectedEncoding: result.detectedEncoding,
    title: result.title,
    artist: result.artist,
    album: result.album,
    conflicts: result.conflicts,
  );
}

/// Lets the user paste lyrics for a song: plain text is saved as reference
/// lyrics (shown statically in the player), timed text keeps its timing
/// unless the user removes it.
Future<LyricImportResult?> showPasteLyricsDialog(
  BuildContext context, {
  required LyricFileImportService importer,
  String? songTitle,
}) {
  return showDialog<LyricImportResult>(
    context: context,
    builder: (_) => PasteLyricsDialog(importer: importer, songTitle: songTitle),
  );
}

class PasteLyricsDialog extends StatefulWidget {
  final LyricFileImportService importer;
  final String? songTitle;

  const PasteLyricsDialog({super.key, required this.importer, this.songTitle});

  @override
  State<PasteLyricsDialog> createState() => _PasteLyricsDialogState();
}

class _PasteLyricsDialogState extends State<PasteLyricsDialog> {
  final TextEditingController _text = TextEditingController();
  bool _stripTimestamps = false;
  LyricImportResult? _parsed;
  bool _hasTimestamps = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_reparse);
  }

  @override
  void dispose() {
    _text.removeListener(_reparse);
    _text.dispose();
    super.dispose();
  }

  void _reparse() {
    final raw = parsePastedLyrics(widget.importer, _text.text);
    setState(() {
      _hasTimestamps = raw?.document.isTimed ?? false;
      _parsed = _stripTimestamps && raw != null
          ? parsePastedLyrics(
              widget.importer,
              _text.text,
              stripTimestamps: true,
            )
          : raw;
    });
  }

  void _setStrip(bool value) {
    _stripTimestamps = value;
    _reparse();
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final width = spec.isCompact
        ? (spec.width - spec.pageGutter * 2).clamp(280.0, 560.0).toDouble()
        : 560.0;
    final parsed = _parsed;
    final lineCount = parsed?.document.lines.length ?? 0;
    final timed = parsed?.document.isTimed ?? false;
    final title = widget.songTitle?.trim();
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);

    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      insetPadding: EdgeInsets.all(spec.pageGutter),
      title: Text(
        title == null || title.isEmpty ? '粘贴歌词' : '粘贴歌词 · $title',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppCapabilities.lyricWorkbench
                    ? '一行一句。纯文本会保存为参考歌词：播放时静态显示、手动滚动，'
                          '之后可以在歌词编辑器里打轴。也可以粘贴 LRC / SRT 等带时间的歌词。'
                    : '一行一句。纯文本会保存为参考歌词：播放时静态显示、手动滚动。'
                          '也可以粘贴 LRC / SRT 等带时间的歌词，播放时会跟着滚动。',
                style: style,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('paste-lyrics-text'),
                controller: _text,
                autofocus: true,
                minLines: 8,
                maxLines: 14,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  hintText: '在这里粘贴歌词',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_hasTimestamps)
                CheckboxListTile(
                  key: const ValueKey('paste-lyrics-strip'),
                  contentPadding: EdgeInsets.zero,
                  value: _stripTimestamps,
                  onChanged: (value) => _setStrip(value ?? false),
                  title: const Text('去掉时间戳，只保存文字'),
                  subtitle: const Text('时间轴和你的歌曲版本对不上时勾选'),
                ),
              Text(
                key: const ValueKey('paste-lyrics-summary'),
                lineCount == 0
                    ? '还没有可保存的歌词'
                    : timed
                    ? '共 $lineCount 行，带时间轴'
                    : '共 $lineCount 行，纯文本（无时间轴）',
                style: style,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const ValueKey('paste-lyrics-save'),
          onPressed: parsed == null
              ? null
              : () => Navigator.of(context).pop(parsed),
          icon: const Icon(Icons.save_rounded),
          label: const Text('保存歌词'),
        ),
      ],
    );
  }
}
