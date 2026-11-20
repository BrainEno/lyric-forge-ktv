import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_review_priority_service.dart';
import '../lyric_review_strings.dart';
import 'lyric_editor_atoms.dart';
import 'lyric_row_audition_button.dart';
import 'lyric_row_semantics.dart';

/// The edits behind a row's right-click menu, in menu order.
///
/// The menu used to be eight hand-written entries and an eight-way switch on
/// string values. It left out 复制文字, which a screen reader could already
/// reach as a custom action. Both now follow this list, so a mouse user and
/// a screen-reader user are offered the same edits under the same names
/// (D-036: action labels reuse the menu text).
enum LyricRowMenuAction {
  editText(LyricRowSemantics.editText, Icons.edit_rounded),
  editStart(LyricRowSemantics.editStart, Icons.timer_outlined),
  editEnd(LyricRowSemantics.editEnd, Icons.timer_outlined),
  startFromPlayback(
    LyricRowSemantics.startFromPlayback,
    Icons.my_location_rounded,
  ),
  endFromPlayback(LyricRowSemantics.endFromPlayback, Icons.my_location_rounded),
  split(LyricRowSemantics.split, Icons.call_split_rounded),
  merge(LyricRowSemantics.merge, Icons.call_merge_rounded),
  copy(LyricRowSemantics.copy, Icons.copy_rounded),
  delete(LyricRowSemantics.delete, Icons.delete_outline_rounded);

  const LyricRowMenuAction(this.label, this.icon);

  /// The name a screen reader announces.
  final String label;
  final IconData icon;

  /// The menu text: editing the text also names its shortcut.
  String get menuLabel => this == editText ? '$label（双击）' : label;

  /// Shown in the error colour.
  bool get destructive => this == delete;
}

/// One lyric line in the editor's list, in review mode.
///
/// Shows the row number (or a playing icon), the audition button, both times
/// as links, the text and badges for chorus, a saved engine candidate, a
/// suggested insertion, the review state and the review priority. A tap
/// selects, a double tap or long press edits the text, and a right click
/// opens [menuActions]. A screen reader meets it as one node (audit A-04).
class LyricReviewRow extends StatelessWidget {
  final int index;
  final LyricLine line;
  final Map<String, dynamic>? fallbackCandidate;
  final bool isReviewed;
  final bool isSecondarySuggestion;
  final LyricReviewPriority? priority;
  final bool selected;
  final bool playing;
  final bool hasAudio;
  final bool auditionIsPlaying;
  final VoidCallback? onPreview;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;

  /// Splits the row at its natural break.
  final VoidCallback? onSplit;

  /// Merges the row with the next one; null on the last row.
  final VoidCallback? onMergeWithNext;
  final VoidCallback? onCopy;
  final VoidCallback? onEditStartTime;
  final VoidCallback? onEditEndTime;
  final VoidCallback? onSetStartFromPlayback;
  final VoidCallback? onSetEndFromPlayback;
  final bool isManuallyEdited;

  const LyricReviewRow({
    super.key,
    required this.index,
    required this.line,
    required this.fallbackCandidate,
    required this.isReviewed,
    this.isSecondarySuggestion = false,
    required this.priority,
    required this.selected,
    required this.playing,
    required this.hasAudio,
    required this.auditionIsPlaying,
    required this.onPreview,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onDelete,
    this.onSplit,
    this.onMergeWithNext,
    this.onCopy,
    this.onEditStartTime,
    this.onEditEndTime,
    this.onSetStartFromPlayback,
    this.onSetEndFromPlayback,
    this.isManuallyEdited = false,
  });

  /// Texts longer than this many characters may wrap to four lines while
  /// the row is selected.
  static const int longTextLength = 28;

  /// The row's priority badge turns to a warning from this score.
  static const int warningScore = 45;

  /// What [action] runs on this row, or null when the row does not offer it.
  VoidCallback? callbackFor(LyricRowMenuAction action) => switch (action) {
    LyricRowMenuAction.editText => onDoubleTap,
    LyricRowMenuAction.editStart => onEditStartTime,
    LyricRowMenuAction.editEnd => onEditEndTime,
    LyricRowMenuAction.startFromPlayback => onSetStartFromPlayback,
    LyricRowMenuAction.endFromPlayback => onSetEndFromPlayback,
    LyricRowMenuAction.split => onSplit,
    LyricRowMenuAction.merge => onMergeWithNext,
    LyricRowMenuAction.copy => onCopy,
    LyricRowMenuAction.delete => onDelete,
  };

  /// The edits this row offers, in menu order.
  List<LyricRowMenuAction> get menuActions => [
    for (final action in LyricRowMenuAction.values)
      if (callbackFor(action) != null) action,
  ];

  /// The text as shown: an empty line says so.
  String get displayText => line.text.trim().isEmpty ? '（空歌词）' : line.text;

  bool get isLongText => line.text.runes.length > longTextLength;

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final actions = menuActions;
    if (actions.isEmpty) return;
    final picked = await showMenu<LyricRowMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        for (final action in actions)
          PopupMenuItem(
            value: action,
            child: ListTile(
              leading: Icon(
                action.icon,
                size: 18,
                color: action.destructive ? AppColors.errorText : null,
              ),
              title: Text(
                action.menuLabel,
                style: action.destructive
                    ? TextStyle(color: AppColors.errorText)
                    : null,
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
    if (picked != null) callbackFor(picked)?.call();
  }

  /// The row as a screen reader meets it: one node that reads the whole row,
  /// carries the selection, and lists every gesture-only edit as a custom
  /// action (audit A-04). The pieces inside are not read one by one.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      selected: selected,
      label: LyricRowSemantics.rowLabel(
        index: index,
        line: line,
        playing: playing,
        isReviewed: isReviewed,
        priority: priority,
        hasCandidate: fallbackCandidate != null,
        isSecondarySuggestion: isSecondarySuggestion,
        isManuallyEdited: isManuallyEdited,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
      customSemanticsActions: LyricRowSemantics.rowActions(
        onAudition: hasAudio ? onPreview : null,
        auditionPlaying: auditionIsPlaying,
        onEditText: onDoubleTap,
        onEditStart: onEditStartTime,
        onEditEnd: onEditEndTime,
        onStartFromPlayback: onSetStartFromPlayback,
        onEndFromPlayback: onSetEndFromPlayback,
        onSplit: onSplit,
        onMerge: onMergeWithNext,
        onCopy: onCopy,
        onDelete: onDelete,
      ),
      child: _buildRow(context),
    );
  }

  Widget _buildRow(BuildContext context) {
    final spec = AppResponsive.of(context);
    final background = selected
        ? AppColors.bgSurface
        : playing
        ? AppColors.accent.withAlpha(18)
        : Colors.transparent;
    final expanded = selected && isLongText;
    final content = Container(
      constraints: BoxConstraints(minHeight: spec.minimumInteractiveExtent),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: selected
            ? Border.all(color: AppColors.accent.withAlpha(120))
            : null,
      ),
      child: Row(
        crossAxisAlignment: expanded || spec.isCompact
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: spec.isCompact ? 28 : 34,
            child: _RowNumber(
              index: index,
              playing: playing,
              edited: isManuallyEdited,
            ),
          ),
          LyricRowAuditionButton(
            hasAudio: hasAudio,
            isPlaying: auditionIsPlaying,
            onPressed: onPreview,
          ),
          if (hasAudio) const SizedBox(width: AppSpacing.xs),
          if (spec.isCompact)
            ..._compactBody(context, spec, expanded: expanded)
          else
            ..._wideBody(context, spec, expanded: expanded),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onLongPress: onLongPress,
          onSecondaryTapDown: (details) =>
              _showContextMenu(context, details.globalPosition),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          child: onDoubleTap == null
              ? content
              : Tooltip(message: rowTooltip, child: content),
        ),
      ),
    );
  }

  /// The hover hint of a row whose text can be edited.
  static const String rowTooltip = '双击直接编辑文字 · 右键更多操作';

  /// One line: times, text, badges, hint and chevron side by side.
  List<Widget> _wideBody(
    BuildContext context,
    AppLayoutSpec spec, {
    required bool expanded,
  }) {
    return [
      ..._times(context),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: _text(context, maxLines: expanded ? 4 : 2)),
      for (final badge in _statusBadges(compact: false)) ...[
        const SizedBox(width: AppSpacing.xs),
        badge,
      ],
      if (selected && onDoubleTap != null) ...[
        const SizedBox(width: AppSpacing.xs),
        Tooltip(
          message: '双击或按 F2 编辑',
          child: Icon(
            Icons.edit_outlined,
            size: 14,
            color: AppColors.textTertiary.withAlpha(160),
          ),
        ),
      ],
      if (!spec.supportsTwoPane) ...[
        const SizedBox(width: AppSpacing.xs),
        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: AppColors.textTertiary,
        ),
      ],
    ];
  }

  /// A phone has no room for both times, the text and the badges on one
  /// line: in a 390-wide widget test, three badges pushed the row 96 px past
  /// its edge, and large text does the same on a device. The text gets the
  /// first line and the times and badges wrap below it, so a long row grows
  /// taller instead of overflowing.
  List<Widget> _compactBody(
    BuildContext context,
    AppLayoutSpec spec, {
    required bool expanded,
  }) {
    return [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(context, maxLines: expanded ? 4 : 1),
            const SizedBox(height: 2),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [..._times(context), ..._statusBadges(compact: true)],
            ),
          ],
        ),
      ),
      if (!spec.supportsTwoPane) ...[
        const SizedBox(width: AppSpacing.xs),
        Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    ];
  }

  List<Widget> _times(BuildContext context) => [
    _RowTime(time: line.startTime, onTap: onEditStartTime),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        '–',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.borderSubtle),
      ),
    ),
    _RowTime(time: line.endTime, onTap: onEditEndTime),
  ];

  Widget _text(BuildContext context, {required int maxLines}) {
    return Text(
      displayText,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: line.text.trim().isEmpty
            ? AppColors.textTertiary
            : AppColors.textPrimary,
        fontWeight: playing ? FontWeight.w700 : FontWeight.w500,
        fontStyle: isManuallyEdited ? FontStyle.italic : null,
      ),
    );
  }

  /// Chorus (wide layouts only), saved engine candidate, suggested
  /// insertion, and the review state or priority; phones use short labels.
  List<Widget> _statusBadges({required bool compact}) {
    final priority = this.priority;
    return [
      if (!compact && line.isChorus)
        const LyricTinyBadge(label: '副歌', accent: true),
      if (fallbackCandidate != null && !isReviewed)
        LyricTinyBadge(label: compact ? '双擎' : '双引擎'),
      if (isSecondarySuggestion && !isReviewed)
        LyricTinyBadge(label: compact ? '补入' : '建议补入', warning: true),
      if (isReviewed)
        const LyricTinyBadge(label: '已复核', accent: true)
      else if (priority != null)
        Tooltip(
          message: priority.reasons
              .map(LyricReviewStrings.priorityReason)
              .join('\n'),
          child: LyricTinyBadge(
            label: compact ? '复核' : '优先 ${priority.score}',
            warning: priority.score >= warningScore,
          ),
        ),
    ];
  }
}

/// The row number with a dot for a hand-edited line, or the playing icon.
class _RowNumber extends StatelessWidget {
  const _RowNumber({
    required this.index,
    required this.playing,
    required this.edited,
  });

  final int index;
  final bool playing;
  final bool edited;

  @override
  Widget build(BuildContext context) {
    if (playing) {
      return Icon(
        Icons.graphic_eq_rounded,
        size: 18,
        color: AppColors.accent,
      );
    }
    // Three-digit rows at large text sizes are wider than the column; they
    // shrink to fit instead of overflowing.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${index + 1}',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          if (edited)
            Container(
              margin: const EdgeInsets.only(left: 3),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

/// A start or end time of a review row; dotted underline when it can be
/// tapped to edit.
class _RowTime extends StatelessWidget {
  const _RowTime({required this.time, required this.onTap});

  final Duration time;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '点击直接编辑时间',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            formatLyricDuration(time),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              fontFeatures: const [FontFeature.tabularFigures()],
              decoration: onTap != null ? TextDecoration.underline : null,
              decorationStyle: TextDecorationStyle.dotted,
            ),
          ),
        ),
      ),
    );
  }
}
