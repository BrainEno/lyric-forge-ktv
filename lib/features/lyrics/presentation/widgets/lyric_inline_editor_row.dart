import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import 'lyric_editor_atoms.dart';
import 'lyric_row_semantics.dart';

/// A row of the editor's line list opened for typing: the row number, both
/// times as links to the time dialog, a text field and 取消 / 保存.
///
/// Enter or 保存 saves, Esc or 取消 cancels. The text is selected when the
/// row opens, so typing replaces it.
class InlineLyricEditorRow extends StatefulWidget {
  final int index;
  final LyricLine line;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;
  final VoidCallback onEditStartTime;
  final VoidCallback onEditEndTime;

  const InlineLyricEditorRow({
    super.key,
    required this.index,
    required this.line,
    required this.onSave,
    required this.onCancel,
    required this.onEditStartTime,
    required this.onEditEndTime,
  });

  @override
  State<InlineLyricEditorRow> createState() => _InlineLyricEditorRowState();
}

class _InlineLyricEditorRowState extends State<InlineLyricEditorRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.line.text);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void didUpdateWidget(covariant InlineLyricEditorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.text != widget.line.text &&
        _controller.text != widget.line.text) {
      _controller.text = widget.line.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onSave(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            border: Border.all(color: AppColors.accent.withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: spec.isCompact ? 28 : 34,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${widget.index + 1}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  _EditableTimeLink(
                    start: true,
                    time: widget.line.startTime,
                    onTap: widget.onEditStartTime,
                  ),
                  // The arrow is read as part of neither time.
                  const ExcludeSemantics(
                    child: Text(
                      ' → ',
                      style: TextStyle(color: AppColors.textTertiary),
                    ),
                  ),
                  _EditableTimeLink(
                    start: false,
                    time: widget.line.endTime,
                    onTap: widget.onEditEndTime,
                  ),
                  const Spacer(),
                  Text(
                    '按回车保存 · Esc 取消',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    widget.onCancel();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: '输入歌词文本',
                    filled: true,
                    fillColor: AppColors.bgElevated,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('取消'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.fromHeight(
                          spec.minimumInteractiveExtent,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('保存'),
                      style: FilledButton.styleFrom(
                        minimumSize: Size.fromHeight(
                          spec.minimumInteractiveExtent,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A start or end time in the inline editor that opens the time dialog.
///
/// A screen reader used to hear only `00:12.40`, with no hint that it was a
/// start time or that it could be changed (audit A-04).
class _EditableTimeLink extends StatelessWidget {
  final bool start;
  final Duration time;
  final VoidCallback? onTap;

  const _EditableTimeLink({
    required this.start,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: LyricRowSemantics.editableTime(start: start, time: time),
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            formatLyricDuration(time),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
