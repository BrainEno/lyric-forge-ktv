import 'package:flutter/semantics.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_review_priority_service.dart';
import '../lyric_review_strings.dart';
import 'lyric_editor_atoms.dart';

/// Screen-reader wording for the lyric editor (audit A-04).
///
/// A screen reader met each editor row as a run of loose pieces: the row
/// number, the start time, a dash, the end time, the text, then badges
/// such as 复核 or 双擎 without saying what they meant. The playing row was
/// only an icon, a hand-edited row only a coloured dot, and the selected
/// row only a border. Editing the text, the times, splitting, merging and
/// deleting were behind a double click, a right click or a long press,
/// which a screen reader cannot perform.
///
/// Each row is now one node: [rowLabel] reads the row in one sentence, the
/// selection is a real selected state, and every gesture-only edit is also
/// a custom action ([rowActions]) that TalkBack and VoiceOver list in their
/// actions menu.
abstract final class LyricRowSemantics {
  static const String auditionPlay = LyricReviewStrings.auditionPlayTooltip;
  static const String auditionPause = LyricReviewStrings.auditionPauseTooltip;
  static const String editText = '编辑文字';
  static const String editStart = '编辑开始时间';
  static const String editEnd = '编辑结束时间';
  static const String startFromPlayback = '标记人声起点为当前播放';
  static const String endFromPlayback = '标记人声终点为当前播放';
  static const String split = '从中间断点拆分为两行';
  static const String merge = '与下一行合并';
  static const String copy = '复制文字';
  static const String delete = '删除此行';

  /// The empty text as it is read.
  static const String emptyText = '空歌词';

  /// One row in one sentence, e.g.
  /// `第 3 行，00:12.40 到 00:15.10，月亮代表我的心，正在播放，建议复核，必看`.
  static String rowLabel({
    required int index,
    required LyricLine line,
    bool playing = false,
    bool isReviewed = false,
    LyricReviewPriority? priority,
    bool hasCandidate = false,
    bool isSecondarySuggestion = false,
    bool isManuallyEdited = false,
  }) {
    final text = line.text.trim();
    return <String>[
      '第 ${index + 1} 行',
      timeRange(line.startTime, line.endTime),
      text.isEmpty ? emptyText : text,
      if (line.isChorus) '副歌',
      if (playing) '正在播放',
      if (isReviewed)
        '已复核'
      else if (priority != null)
        LyricSuggestedReviewStrings.rowSemantics(priority),
      if (!isReviewed && hasCandidate) '有另一引擎的候选',
      if (!isReviewed && isSecondarySuggestion) '建议补入',
      if (isManuallyEdited) '已手动修改',
    ].join('，');
  }

  /// `00:12.40 到 00:15.10`: the dash between the times is not read.
  static String timeRange(Duration start, Duration end) =>
      '${formatLyricDuration(start)} 到 ${formatLyricDuration(end)}';

  /// Label of a time a tap opens for editing.
  static String editableTime({required bool start, required Duration time}) =>
      '${start ? '开始' : '结束'}时间 ${formatLyricDuration(time)}，点按修改';

  /// The gesture-only edits of a row as custom actions, in menu order. A
  /// null callback leaves its action out, so a read-only row offers none.
  static Map<CustomSemanticsAction, VoidCallback> rowActions({
    VoidCallback? onAudition,
    bool auditionPlaying = false,
    VoidCallback? onEditText,
    VoidCallback? onEditStart,
    VoidCallback? onEditEnd,
    VoidCallback? onStartFromPlayback,
    VoidCallback? onEndFromPlayback,
    VoidCallback? onSplit,
    VoidCallback? onMerge,
    VoidCallback? onCopy,
    VoidCallback? onDelete,
  }) {
    final entries = <(String, VoidCallback?)>[
      (auditionPlaying ? auditionPause : auditionPlay, onAudition),
      (editText, onEditText),
      (editStart, onEditStart),
      (editEnd, onEditEnd),
      (startFromPlayback, onStartFromPlayback),
      (endFromPlayback, onEndFromPlayback),
      (split, onSplit),
      (merge, onMerge),
      (copy, onCopy),
      (delete, onDelete),
    ];
    return {
      for (final (label, callback) in entries)
        CustomSemanticsAction(label: label): ?callback,
    };
  }

  /// Label of a word timing chip, e.g. `月亮，00:01.20 到 00:01.80，点按跳到这里`.
  static String wordChip({
    required String word,
    required Duration start,
    required Duration end,
    required bool canSeek,
  }) {
    final text = word.trim().isEmpty ? emptyText : word.trim();
    final range = timeRange(start, end);
    return canSeek ? '$text，$range，点按跳到这里' : '$text，$range';
  }
}
