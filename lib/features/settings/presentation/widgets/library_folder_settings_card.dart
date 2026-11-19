import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_button_spinner.dart';
import '../../../player/domain/services/library_folder_settings.dart';

/// Asks for a folder; returns its path, or null when the user cancelled.
typedef LibraryFolderPicker =
    Future<String?> Function({String? initialDirectory});

/// Pairs lyric files in the library folder now; returns what it did.
typedef LibraryLyricsFinder = Future<String> Function();

/// Counts the songs whose lyrics the library paired on its own (D-034).
typedef LibraryAutoPairedCounter = Future<int> Function();

Future<String?> _pickWithFilePicker({String? initialDirectory}) {
  return FilePicker.platform.getDirectoryPath(
    dialogTitle: LibraryFolderSettingsText.pickerTitle,
    initialDirectory: initialDirectory,
    lockParentWindow: true,
  );
}

/// Sentences of the 曲库目录 card (decision D-033).
abstract final class LibraryFolderSettingsText {
  static const String title = '曲库目录';
  static const String subtitle = '导出的歌词文件放在这里，就会自动配给同名歌曲；导出歌词时也默认存到这里。';
  static const String pickerTitle = '选择曲库目录';
  static const String change = '更改…';
  static const String choose = '选择文件夹…';
  static const String reset = '恢复默认';
  static const String findNow = '立即配对歌词';
  static const String matchingRule =
      '按文件名配对：「夜曲.lrc」配给「夜曲.mp3」或标题为“夜曲”的歌曲，'
      '也认「歌手 - 歌名.lrc」。支持 LRC、ASS、VTT、SRT；'
      '已经有歌词的歌曲不会被改动。';
  static const String noFolder = '还没有曲库目录，请选择一个文件夹';
  static const String loadFailed = '读取曲库目录失败，请稍后再试';
  static const String saveFailed = '没能保存曲库目录，请检查文件夹权限后再试';
  static const String resetDone = '已恢复默认曲库目录';

  static String source(LibraryFolderSource from) => switch (from) {
    LibraryFolderSource.custom => '你选择的文件夹',
    LibraryFolderSource.firstLibraryFolder => '默认：你最先添加到音乐库的文件夹',
    LibraryFolderSource.system => '默认：系统“音乐”文件夹',
    LibraryFolderSource.none => noFolder,
  };

  static String chosen(String path) => '曲库目录已改为 $path，里面的歌曲也会加入音乐库';

  static const String noneAutoPaired = '还没有按文件名自动配对的歌曲';
  static const String openAutoPaired = '在音乐库查看';

  /// The line about automatic pairings (D-034).
  static String autoPaired(int count) =>
      count <= 0 ? noneAutoPaired : '已自动配对 $count 首歌';
}

/// 曲库目录: shows the library folder, lets the user change it or go back to
/// the default, and pairs the lyric files in it on request.
class LibraryFolderSettingsCard extends StatefulWidget {
  const LibraryFolderSettingsCard({
    super.key,
    required this.settings,
    this.findLyrics,
    this.pickFolder = _pickWithFilePicker,
    this.countAutoPaired,
    this.openAutoPaired,
  });

  final LibraryFolderSettings settings;

  /// Null hides 立即配对歌词 and skips pairing after a change.
  final LibraryLyricsFinder? findLyrics;
  final LibraryFolderPicker pickFolder;

  /// Null hides the 已自动配对 line.
  final LibraryAutoPairedCounter? countAutoPaired;

  /// Opens the library on its 自动配对 view; completes when the user comes
  /// back, so the count can catch up with anything they unpaired there.
  /// Null hides 在音乐库查看.
  final Future<void> Function()? openAutoPaired;

  static const Key pathKey = ValueKey('library-folder:path');
  static const Key messageKey = ValueKey('library-folder:message');
  static const Key autoPairedKey = ValueKey('library-folder:auto-paired');

  @override
  State<LibraryFolderSettingsCard> createState() =>
      _LibraryFolderSettingsCardState();
}

enum _Busy { none, loading, choosing, resetting, finding }

class _LibraryFolderSettingsCardState extends State<LibraryFolderSettingsCard> {
  LibraryFolder? _folder;
  _Busy _busy = _Busy.loading;
  String? _message;
  bool _messageIsError = false;

  /// Songs paired automatically; null until counted, or when counting
  /// failed, which hides the line rather than showing a wrong number.
  int? _autoPaired;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_countAutoPaired());
  }

  Future<void> _countAutoPaired() async {
    final count = widget.countAutoPaired;
    if (count == null) return;
    int? counted;
    try {
      counted = await count();
    } on Exception {
      // Leave the line out rather than show a wrong number.
    }
    if (mounted) setState(() => _autoPaired = counted);
  }

  Future<void> _openAutoPaired() async {
    final open = widget.openAutoPaired;
    if (open == null) return;
    await open();
    await _countAutoPaired();
  }

  Future<void> _load() async {
    try {
      final folder = await widget.settings.current();
      if (!mounted) return;
      setState(() {
        _folder = folder;
        _busy = _Busy.none;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _busy = _Busy.none;
        _message = LibraryFolderSettingsText.loadFailed;
        _messageIsError = true;
      });
    }
  }

  Future<void> _choose() async {
    final picked = await widget.pickFolder(initialDirectory: _folder?.path);
    if (picked == null || picked.trim().isEmpty || !mounted) return;
    await _run(_Busy.choosing, () async {
      final folder = await widget.settings.choose(picked);
      final found = await _findQuietly();
      final chosen = LibraryFolderSettingsText.chosen(folder.path ?? picked);
      return (folder, found == null ? chosen : '$chosen。$found');
    });
  }

  Future<void> _reset() => _run(_Busy.resetting, () async {
    final folder = await widget.settings.resetToDefault();
    return (folder, LibraryFolderSettingsText.resetDone);
  });

  Future<void> _find() => _run(_Busy.finding, () async {
    final found = await widget.findLyrics!();
    return (_folder, found);
  });

  Future<String?> _findQuietly() async {
    final find = widget.findLyrics;
    if (find == null) return null;
    try {
      return await find();
    } on Exception {
      return null;
    }
  }

  Future<void> _run(
    _Busy busy,
    Future<(LibraryFolder?, String)> Function() work,
  ) async {
    if (_busy != _Busy.none) return;
    setState(() {
      _busy = busy;
      _message = null;
    });
    try {
      final (folder, message) = await work();
      if (!mounted) return;
      setState(() {
        _folder = folder ?? _folder;
        _message = message;
        _messageIsError = false;
      });
      // Choosing a folder or pairing now can add automatic pairings.
      if (busy != _Busy.resetting) unawaited(_countAutoPaired());
    } on Exception {
      if (!mounted) return;
      setState(() {
        _message = LibraryFolderSettingsText.saveFailed;
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final folder = _folder;
    final path = folder?.path;
    final idle = _busy == _Busy.none;
    final message = _message;
    final autoPaired = _autoPaired;

    Widget label(_Busy busy, String idleLabel) {
      return _busy == busy ? const AppButtonSpinner() : Text(idleLabel);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy == _Busy.loading)
          const LinearProgressIndicator(minHeight: 2)
        else ...[
          SelectableText(
            path ?? LibraryFolderSettingsText.noFolder,
            key: LibraryFolderSettingsCard.pathKey,
            style: text.bodyMedium?.copyWith(
              color: path == null
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (folder != null && path != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              LibraryFolderSettingsText.source(folder.source),
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
        if (autoPaired != null)
          _AutoPairedLine(
            count: autoPaired,
            onOpen: widget.openAutoPaired == null || autoPaired == 0
                ? null
                : _openAutoPaired,
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          LibraryFolderSettingsText.matchingRule,
          style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.tonal(
              onPressed: idle ? _choose : null,
              child: label(
                _Busy.choosing,
                path == null
                    ? LibraryFolderSettingsText.choose
                    : LibraryFolderSettingsText.change,
              ),
            ),
            if (folder?.isCustom == true)
              TextButton(
                onPressed: idle ? _reset : null,
                child: label(_Busy.resetting, LibraryFolderSettingsText.reset),
              ),
            if (widget.findLyrics != null && path != null)
              TextButton(
                onPressed: idle ? _find : null,
                child: label(_Busy.finding, LibraryFolderSettingsText.findNow),
              ),
          ],
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              message,
              key: LibraryFolderSettingsCard.messageKey,
              style: text.bodySmall?.copyWith(
                color: _messageIsError
                    ? AppColors.errorText
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 已自动配对 N 首歌, with the way to those songs in the library (D-034).
class _AutoPairedLine extends StatelessWidget {
  const _AutoPairedLine({required this.count, this.onOpen});

  final int count;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final open = onOpen;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 16,
            color: count > 0 ? AppColors.accent : AppColors.textTertiary,
          ),
          Text(
            LibraryFolderSettingsText.autoPaired(count),
            key: LibraryFolderSettingsCard.autoPairedKey,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: count > 0
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
          if (open != null)
            TextButton.icon(
              onPressed: open,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text(LibraryFolderSettingsText.openAutoPaired),
            ),
        ],
      ),
    );
  }
}
