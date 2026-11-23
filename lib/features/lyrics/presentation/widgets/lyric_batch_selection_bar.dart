import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_command_keys.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../controllers/lyric_editor_document_controller.dart';

/// Choosing rows of the lyric list for a batch edit (D-066).
@immutable
class LyricBatchControls {
  const LyricBatchControls({
    required this.active,
    required this.selected,
    required this.onToggle,
    required this.onRange,
    required this.onSelectAll,
    required this.onEnd,
    required this.onDelete,
  });

  /// The editor's batch state, with [onDelete] removing the chosen rows.
  factory LyricBatchControls.of(
    LyricEditorDocumentController editor, {
    required VoidCallback onDelete,
  }) {
    return LyricBatchControls(
      active: editor.batchMode,
      selected: editor.batchSelection.toSet(),
      onToggle: editor.toggleBatchLine,
      onRange: editor.selectBatchRange,
      onSelectAll: editor.selectAllBatch,
      onEnd: editor.endBatch,
      onDelete: onDelete,
    );
  }

  /// Batch mode is on: a tap chooses a row instead of opening it.
  final bool active;
  final Set<int> selected;

  /// Chooses row `index`, or takes it out. `includeCurrent` (Ctrl/Cmd+click)
  /// also chooses the row that was selected before.
  final void Function(int index, {bool includeCurrent}) onToggle;

  /// Chooses the rows of `order` from the anchor to `index` (Shift).
  final void Function(int index, List<int> order) onRange;
  final ValueChanged<List<int>> onSelectAll;
  final VoidCallback onEnd;
  final VoidCallback onDelete;

  bool isChosen(int index) => selected.contains(index);
}

/// What the batch bar says.
abstract final class LyricBatchStrings {
  static const String start = '多选';
  static const String end = '退出多选（Esc）';
  static const String nothingChosen = '点选要一起处理的行';
  static String chosen(int count) => '已选 $count 行';
  static const String markReviewed = '标记已复核';
  static const String clearReviewed = '取消复核';
  static const String shift = '平移时间';
  static const String merge = '合并成一行';
  static const String mergeNeedsNeighbours = '只能合并相邻的两行或更多行';
  static const String copy = '复制文字';
  static const String delete = '删除';
  static const String selectAll = '全选';

  /// The tooltip of the 多选 button, naming the keys of this platform.
  static String startTooltip([TargetPlatform? platform]) =>
      '一次复核、平移、合并或删除多行'
      '（也可以 ${AppCommandKeys.modifier(platform)}+点击、Shift+点击或长按）';
}

/// The bottom bar of the lyric list while rows are being chosen (D-066).
///
/// Wide windows show every action with its label; narrower ones show icons,
/// and a phone keeps the three most used and puts the rest in a menu, so
/// the bar fits a 320-wide screen at double text size.
class LyricBatchActionBar extends StatelessWidget {
  const LyricBatchActionBar({
    super.key,
    required this.count,
    required this.allReviewed,
    required this.canMerge,
    required this.onEnd,
    required this.onSelectAll,
    required this.onMarkReviewed,
    required this.onShift,
    required this.onMerge,
    required this.onCopy,
    required this.onDelete,
  });

  final int count;

  /// Every chosen row is reviewed, so the review action clears the marks.
  final bool allReviewed;

  /// The chosen rows are two or more neighbours.
  final bool canMerge;
  final VoidCallback onEnd;

  /// Null when every shown row is already chosen.
  final VoidCallback? onSelectAll;
  final ValueChanged<bool> onMarkReviewed;
  final VoidCallback onShift;
  final VoidCallback onMerge;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  static const barKey = ValueKey('lyric_batch_bar');
  static const startKey = ValueKey('lyric_batch_start');
  static const endKey = ValueKey('lyric_batch_end');
  static const reviewKey = ValueKey('lyric_batch_review');
  static const shiftKey = ValueKey('lyric_batch_shift');
  static const mergeKey = ValueKey('lyric_batch_merge');
  static const copyKey = ValueKey('lyric_batch_copy');
  static const deleteKey = ValueKey('lyric_batch_delete');
  static const selectAllKey = ValueKey('lyric_batch_select_all');
  static const moreKey = ValueKey('lyric_batch_more');

  /// From this width every action shows its label.
  static const double labelledWidth = 760;

  /// Below this width the less used actions move into a menu.
  static const double menuWidth = 480;

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final horizontal = spec.pageGutter.clamp(12, 24).toDouble();
    return Container(
      key: barKey,
      padding: EdgeInsets.symmetric(
        horizontal: horizontal,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(top: BorderSide(color: AppColors.accent)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final actions = _actions();
          return Row(
            children: [
              IconButton(
                key: endKey,
                tooltip: LyricBatchStrings.end,
                onPressed: onEnd,
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: Text(
                  count == 0
                      ? LyricBatchStrings.nothingChosen
                      : LyricBatchStrings.chosen(count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (width >= labelledWidth)
                for (final action in actions) action.asLabelled()
              else if (width >= menuWidth)
                for (final action in actions) action.asIcon()
              else ...[
                for (final action in actions.where((a) => a.primary))
                  action.asIcon(),
                _menu(actions.where((a) => !a.primary).toList()),
              ],
            ],
          );
        },
      ),
    );
  }

  List<_BatchAction> _actions() {
    final some = count > 0;
    return [
      _BatchAction(
        key: selectAllKey,
        label: LyricBatchStrings.selectAll,
        icon: Icons.select_all_rounded,
        onPressed: onSelectAll,
      ),
      _BatchAction(
        key: reviewKey,
        label: allReviewed
            ? LyricBatchStrings.clearReviewed
            : LyricBatchStrings.markReviewed,
        icon: allReviewed
            ? Icons.remove_done_rounded
            : Icons.check_circle_outline_rounded,
        onPressed: some ? () => onMarkReviewed(!allReviewed) : null,
        primary: true,
      ),
      _BatchAction(
        key: shiftKey,
        label: LyricBatchStrings.shift,
        icon: Icons.swap_horiz_rounded,
        onPressed: some ? onShift : null,
        primary: true,
      ),
      _BatchAction(
        key: mergeKey,
        label: LyricBatchStrings.merge,
        icon: Icons.call_merge_rounded,
        onPressed: canMerge ? onMerge : null,
        disabledHint: count >= 2
            ? LyricBatchStrings.mergeNeedsNeighbours
            : null,
      ),
      _BatchAction(
        key: copyKey,
        label: LyricBatchStrings.copy,
        icon: Icons.copy_rounded,
        onPressed: some ? onCopy : null,
      ),
      _BatchAction(
        key: deleteKey,
        label: LyricBatchStrings.delete,
        icon: Icons.delete_outline_rounded,
        onPressed: some ? onDelete : null,
        destructive: true,
        primary: true,
      ),
    ];
  }

  Widget _menu(List<_BatchAction> actions) {
    return PopupMenuButton<_BatchAction>(
      key: moreKey,
      tooltip: '更多批量操作',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) => action.onPressed?.call(),
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem(
            key: action.key,
            value: action,
            enabled: action.onPressed != null,
            child: Text(action.disabledHint ?? action.label),
          ),
      ],
    );
  }
}

class _BatchAction {
  const _BatchAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
    this.disabledHint,
  });

  final Key key;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Kept on the bar of a phone; the others go into its menu.
  final bool primary;
  final bool destructive;

  /// Why the action is off, shown in place of its label.
  final String? disabledHint;

  String get _tooltip =>
      onPressed == null && disabledHint != null ? disabledHint! : label;

  Color? get _color => destructive && onPressed != null
      ? AppColors.errorText
      : null;

  Widget asLabelled() => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs),
    child: Tooltip(
      message: _tooltip,
      child: TextButton.icon(
        key: key,
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: _color),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    ),
  );

  Widget asIcon() => IconButton(
    key: key,
    tooltip: _tooltip,
    onPressed: onPressed,
    color: _color,
    icon: Icon(icon),
  );
}
