import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/app_command_keys.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_line_locator.dart';
import '../../domain/services/lyric_timing_shift_service.dart';
import 'lyric_list_logic.dart';

/// Text of 跳到行 (D-067), shared by the menu, the dialog and the tests.
abstract final class LyricJumpStrings {
  static const title = '跳到行';
  static const menuDetailTouch = '输入行号或时间，直接定位到那一行';
  static const confirm = '跳转';

  /// The menu's second line, naming the shortcut on a keyboard platform.
  static String menuDetail([TargetPlatform? platform]) {
    final target = platform ?? defaultTargetPlatform;
    if (target == TargetPlatform.iOS || target == TargetPlatform.android) {
      return menuDetailTouch;
    }
    return '输入行号或时间（${AppCommandKeys.withCommand('G', target)}）';
  }
}

/// How following playback behaves, as the 跟随播放 chip explains it.
abstract final class LyricListFollowStrings {
  static String get tooltip =>
      '播放时列表自动滚到正在唱的行。自己滚动列表、按方向键或跳到别的行后，'
      '先停 ${LyricListNavigation.followPause.inSeconds} 秒再跟上；'
      '也可以点「回到正在播放」马上回去。';
}

/// Asks the editor's line list to bring a row into view and flash it.
///
/// The editor owns one for as long as it is open: Ctrl/⌘+G and the menu
/// call [jumpTo] after the dialog, and the list, which owns the scrolling,
/// listens.
class LyricLineJumpController extends ChangeNotifier {
  int? _target;
  int _requestId = 0;

  /// The row of the latest request.
  int? get target => _target;

  /// Grows with every request, so asking for the same row again still
  /// scrolls to it and flashes it.
  int get requestId => _requestId;

  void jumpTo(int index) {
    _target = index;
    _requestId++;
    notifyListeners();
  }
}

/// Keeps one [LyricLineJumpController] alive for a stateless editor.
class LyricLineJumpHost extends StatefulWidget {
  const LyricLineJumpHost({super.key, required this.builder});

  final Widget Function(BuildContext context, LyricLineJumpController jump)
  builder;

  @override
  State<LyricLineJumpHost> createState() => _LyricLineJumpHostState();
}

class _LyricLineJumpHostState extends State<LyricLineJumpHost> {
  final _jump = LyricLineJumpController();

  @override
  void dispose() {
    _jump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _jump);
}

/// Asks which row to go to. Returns the row index, or null when cancelled.
Future<int?> showLyricJumpToLineDialog(
  BuildContext context, {
  required LyricDocument document,
  int? current,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => LyricJumpToLineDialog(document: document, current: current),
  );
}

class LyricJumpToLineDialog extends StatefulWidget {
  const LyricJumpToLineDialog({
    super.key,
    required this.document,
    this.current,
  });

  final LyricDocument document;

  /// The selected row, offered as the starting text.
  final int? current;

  static const inputKey = ValueKey('lyric_jump_input');
  static const confirmKey = ValueKey('lyric_jump_confirm');

  /// How much of the row's text the preview shows.
  static const previewLength = 40;

  @override
  State<LyricJumpToLineDialog> createState() => _LyricJumpToLineDialogState();
}

class _LyricJumpToLineDialogState extends State<LyricJumpToLineDialog> {
  late final TextEditingController _input;
  late LyricLineLocation _location;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    final start = current == null || current >= widget.document.lines.length
        ? ''
        : '${current + 1}';
    _input = TextEditingController(text: start)
      ..selection = TextSelection(baseOffset: 0, extentOffset: start.length);
    _location = _locate(start);
    _input.addListener(_update);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  LyricLineLocation _locate(String text) =>
      LyricLineLocator.locate(widget.document, text);

  void _update() => setState(() => _location = _locate(_input.text));

  void _confirm() {
    final index = _location.index;
    if (index == null) return;
    Navigator.of(context).pop(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final location = _location;
    final index = location.index;
    final typed = _input.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text(LyricJumpStrings.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: LyricJumpToLineDialog.inputKey,
              controller: _input,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '行号或时间',
                hintText: LyricLineLocator.hint(widget.document.lines.length),
                errorText: typed ? location.problem : null,
                isDense: true,
              ),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: AppSpacing.md),
            if (index == null)
              Text(
                typed
                    ? '找到要去的行后，这里会显示它的内容。'
                    : LyricLineLocator.hint(widget.document.lines.length),
                style: style?.copyWith(color: AppColors.textTertiary),
              )
            else
              _Preview(
                document: widget.document,
                index: index,
                time: location.time,
                style: style,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: LyricJumpToLineDialog.confirmKey,
          onPressed: index == null ? null : _confirm,
          child: const Text(LyricJumpStrings.confirm),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.document,
    required this.index,
    required this.time,
    required this.style,
  });

  final LyricDocument document;
  final int index;
  final Duration? time;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final line = document.lines[index];
    final text = line.text.trim();
    final limit = LyricJumpToLineDialog.previewLength;
    final shown = text.isEmpty
        ? '（空行）'
        : text.length > limit
        ? '${text.substring(0, limit)}…'
        : text;
    final at = time;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          at == null
              ? '第 ${index + 1} 行 · ${formatLyricTimeInput(line.startTime)}'
              : '${formatLyricTimeInput(at)} → 第 ${index + 1} 行 · '
                    '${formatLyricTimeInput(line.startTime)} 开始',
          style: style?.copyWith(
            color: AppColors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          shown,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
