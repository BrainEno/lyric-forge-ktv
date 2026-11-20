import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import 'lyric_editor_atoms.dart';

/// Reading and checking a time typed into the editor.
abstract final class LyricTimeInput {
  /// The shortest a line may become when one of its times moves.
  static const Duration minimumLineLength = Duration(milliseconds: 10);

  static final RegExp _clock = RegExp(
    r'^(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?$',
  );

  /// `mm:ss.hh`, `m:ss`, `mm:ss:hh`, `mm:ss.mmm` or plain seconds such as
  /// `83.5`. A fraction is read as the digits after the point, so `.5` is
  /// half a second, `.45` 450 ms and `.123` 123 ms. Returns null for
  /// anything else, including 60 seconds or more after a colon.
  static Duration? parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final match = _clock.firstMatch(trimmed);
    if (match != null) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      if (seconds >= 60) return null;
      final fraction = match.group(3);
      final millis = fraction == null
          ? 0
          : int.parse(fraction.padRight(3, '0'));
      return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
    }
    final asSeconds = double.tryParse(trimmed);
    if (asSeconds != null && asSeconds >= 0 && asSeconds.isFinite) {
      return Duration(milliseconds: (asSeconds * 1000).round());
    }
    return null;
  }

  static const String formatError = '格式应为 mm:ss.hh，例如 01:23.45';
  static const String hint = 'mm:ss.hh，例如 01:23.45';
  static const String helper = '也支持 83.5（秒）';

  static String title({required bool start}) => start ? '编辑开始时间' : '编辑结束时间';
  static String label({required bool start}) => start ? '开始时间' : '结束时间';
  static String current(Duration time) => '当前：${formatLyricDuration(time)}';

  /// Why [time] cannot become the start ([start]) or end of [line], or null
  /// when it can. A line keeps at least [minimumLineLength].
  static String? rejection(
    LyricLine line,
    Duration time, {
    required bool start,
  }) {
    if (start) {
      return time > line.endTime - minimumLineLength ? '开始时间不能晚于结束时间' : null;
    }
    return time < line.startTime + minimumLineLength ? '结束时间不能早于开始时间' : null;
  }

  /// [line] with [time] as its start or end.
  static LyricLine apply(LyricLine line, Duration time, {required bool start}) {
    return start
        ? line.copyWith(startTime: time)
        : line.copyWith(endTime: time);
  }
}

/// Asks for a new start or end time of [line].
///
/// Returns the edited line, or null when the dialog was cancelled or the time
/// would leave the line shorter than [LyricTimeInput.minimumLineLength]; in
/// that case the reason is shown in a snack bar.
Future<LyricLine?> editLyricLineTime(
  BuildContext context,
  LyricLine line, {
  required bool start,
}) async {
  final initial = start ? line.startTime : line.endTime;
  final result = await showDialog<Duration>(
    context: context,
    builder: (_) => TimestampEditDialog(
      title: LyricTimeInput.title(start: start),
      initial: initial,
      label: LyricTimeInput.label(start: start),
    ),
  );
  if (result == null || !context.mounted) return null;
  final rejection = LyricTimeInput.rejection(line, result, start: start);
  if (rejection != null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(rejection)));
    return null;
  }
  return LyricTimeInput.apply(line, result, start: start);
}

/// A dialog with one time field; pops with the parsed [Duration].
class TimestampEditDialog extends StatefulWidget {
  final String title;
  final Duration initial;
  final String label;

  const TimestampEditDialog({
    super.key,
    required this.title,
    required this.initial,
    required this.label,
  });

  @override
  State<TimestampEditDialog> createState() => _TimestampEditDialogState();
}

class _TimestampEditDialogState extends State<TimestampEditDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: formatLyricDuration(widget.initial),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = LyricTimeInput.parse(_controller.text);
    if (parsed == null) {
      setState(() => _error = LyricTimeInput.formatError);
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: LyricTimeInput.hint,
              helperText: LyricTimeInput.helper,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            LyricTimeInput.current(widget.initial),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
