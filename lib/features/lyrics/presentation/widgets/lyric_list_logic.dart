import 'package:flutter/services.dart';

import '../../../project/domain/models/lyric_document.dart';
import 'lyric_editor_atoms.dart';

// The rules behind the editor's line list, out of its State object (audit
// follow-up to E-04 and I-03).
//
// lyric_list_pane.dart was 1424 lines. Its State worked out the search, the
// highlighted engine candidates and their summary, the follow-playback scroll
// target and the keyboard commands inline in build, didUpdateWidget and the
// key handler, so none of them could be tested without pumping the whole
// list. They are plain functions here.

/// Whether two index lists hold the same rows in the same order.
bool sameLyricIndices(List<int> left, List<int> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// The search box above the list: matches text, start time or row number.
abstract final class LyricListSearch {
  /// The query as it is compared: trimmed and lower case.
  static String normalize(String query) => query.trim().toLowerCase();

  /// Whether row [index] matches the already [normalize]d [query].
  static bool matches(LyricLine line, int index, String query) {
    if (query.isEmpty) return true;
    return line.text.toLowerCase().contains(query) ||
        formatLyricDuration(line.startTime).contains(query) ||
        '${index + 1}'.contains(query);
  }

  /// The rows of [visible] that match [query], in order. An empty query
  /// returns [visible] itself, so callers can compare by identity.
  static List<int> filter(
    LyricDocument document,
    List<int> visible,
    String query,
  ) {
    final normalized = normalize(query);
    if (normalized.isEmpty) return visible;
    return [
      for (final index in visible)
        if (index >= 0 &&
            index < document.lines.length &&
            matches(document.lines[index], index, normalized))
          index,
    ];
  }
}

/// The engine candidates a document saved, and which of them the list marks.
///
/// A transcription can keep another engine's reading for some rows
/// (`fallbackCandidates`) and say how many of them deserve a badge
/// (`fallbackHighlightLimit`). Rows already reviewed are never marked; the
/// first [highlighted] of the rest are.
class LyricCandidateHighlights {
  const LyricCandidateHighlights({
    required this.total,
    required this.eligible,
    required this.highlighted,
  });

  /// Rows with a saved candidate.
  final int total;

  /// Rows with a candidate that are not reviewed yet.
  final int eligible;

  /// The rows whose candidate the list shows.
  final Set<int> highlighted;

  /// Null when the document saved no candidate list, in which case every
  /// row shows its candidate as before highlights existed.
  static LyricCandidateHighlights? from(
    LyricDocument document, {
    required Set<int> reviewed,
  }) {
    final rawCandidates = document.metadata['fallbackCandidates'];
    if (rawCandidates is! List) return null;
    final indices = <int>{};
    for (final candidate in rawCandidates) {
      if (candidate is! Map) continue;
      final rawIndex = candidate['lineIndex'];
      if (rawIndex is! int ||
          rawIndex < 0 ||
          rawIndex >= document.lines.length) {
        continue;
      }
      indices.add(rawIndex);
    }
    final total = indices.length;
    indices.removeAll(reviewed);
    final eligible = indices.length;
    final rawLimit = document.metadata['fallbackHighlightLimit'];
    final limit = rawLimit is num
        ? rawLimit.toInt().clamp(0, eligible)
        : eligible;
    return LyricCandidateHighlights(
      total: total,
      eligible: eligible,
      highlighted: indices.take(limit).toSet(),
    );
  }

  /// Unreviewed rows with a candidate that carry no badge.
  int get remaining => eligible - highlighted.length;

  /// The summary line is worth showing.
  bool get hasSummary => total > 0;

  /// Whether row [index] shows its candidate.
  bool shows(int index) => highlighted.contains(index);

  /// e.g. `已保存候选 30 行 · 未复核 29 行 · 重点标记 3 行（当前筛选 2 行） ·
  /// 其余未复核 26 行仍可查看`, where [shown] are the rows on screen.
  String summary(Iterable<int> shown) {
    final inView = highlighted.intersection(shown.toSet()).length;
    return '已保存候选 $total 行 · 未复核 $eligible 行 · '
        '重点标记 ${highlighted.length} 行（当前筛选 $inView 行） · '
        '其余未复核 $remaining 行仍可查看';
  }
}

/// What a key does in the list.
enum LyricListCommand {
  /// Select the next shown row.
  next,

  /// Select the previous shown row.
  previous,

  /// Edit the selected row's text.
  edit,

  /// Delete the selected row (with Ctrl or Cmd).
  delete,

  /// Focus the search box (Ctrl or Cmd + F).
  search,

  /// Extend the batch choice to the next shown row (Shift + ↓, D-066).
  extendNext,

  /// Extend the batch choice to the previous shown row (Shift + ↑).
  extendPrevious,

  /// Choose every shown row (Ctrl or Cmd + A).
  selectAll,

  /// Leave batch mode (Esc); only used while it is on.
  endBatch;

  /// Whether the command grows the batch choice as it moves.
  bool get growsBatch => this == extendNext || this == extendPrevious;
}

/// Keyboard and scrolling rules of the list.
abstract final class LyricListNavigation {
  /// The command [key] stands for, given whether Ctrl or Cmd is held.
  ///
  /// Delete and Backspace only delete with Ctrl or Cmd, so a stray key does
  /// not remove a line. [shift] turns the arrows into extending the batch
  /// choice; Esc ends batch mode, and is left alone outside it ([batch]).
  static LyricListCommand? commandFor(
    LogicalKeyboardKey key, {
    required bool command,
    bool shift = false,
    bool batch = false,
  }) {
    if (key == LogicalKeyboardKey.arrowDown) {
      return shift ? LyricListCommand.extendNext : LyricListCommand.next;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return shift
          ? LyricListCommand.extendPrevious
          : LyricListCommand.previous;
    }
    if (key == LogicalKeyboardKey.keyA && command) {
      return LyricListCommand.selectAll;
    }
    if (key == LogicalKeyboardKey.escape) {
      return batch ? LyricListCommand.endBatch : null;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.f2) {
      return LyricListCommand.edit;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      return command ? LyricListCommand.delete : null;
    }
    if (key == LogicalKeyboardKey.keyF && command) {
      return LyricListCommand.search;
    }
    return null;
  }

  /// The row after [selected] in [shown], or null at the end or when
  /// [selected] is not shown.
  static int? next(List<int> shown, int selected) {
    final position = shown.indexOf(selected);
    if (position < 0 || position + 1 >= shown.length) return null;
    return shown[position + 1];
  }

  /// The row before [selected] in [shown], or null at the start or when
  /// [selected] is not shown.
  static int? previous(List<int> shown, int selected) {
    final position = shown.indexOf(selected);
    if (position <= 0) return null;
    return shown[position - 1];
  }

  /// The rough height of a row, for scrolling to rows not built yet.
  static const double estimatedRowExtent = 68;

  /// Where the playing row sits in the viewport: a little above the middle.
  static const double followAnchor = 0.42;

  /// Closer than this, following does not scroll.
  static const double followSlack = 20;

  /// How long following playback waits after the person last scrolled the
  /// list, moved with the arrow keys or jumped to a row (D-067).
  static const Duration followPause = Duration(seconds: 5);

  /// How long a row jumped to stays highlighted.
  static const Duration jumpFlash = Duration(milliseconds: 1400);

  /// How many times a jump re-estimates the offset of a row not built yet
  /// before giving up.
  static const int revealAttempts = 4;

  /// The average row height of a list whose scroll range is [maxExtent]
  /// for [rows] rows in a [viewport]-tall window; [estimatedRowExtent]
  /// before anything was laid out.
  static double averageRowExtent({
    required double maxExtent,
    required double viewport,
    required int rows,
  }) {
    if (rows <= 0) return estimatedRowExtent;
    final average = (maxExtent + viewport) / rows;
    return average.isFinite && average > 0 ? average : estimatedRowExtent;
  }

  /// A first guess at the offset that shows the row at [position], used
  /// to get it built so its real place can be measured.
  static double revealEstimate({
    required int position,
    required double rowExtent,
    required double viewport,
    required double minExtent,
    required double maxExtent,
  }) {
    final raw = position * rowExtent - viewport * followAnchor;
    return raw.clamp(minExtent, maxExtent).toDouble();
  }

  /// Where to scroll so a row is fully on screen after an arrow key, or
  /// null when it already is. [top] is the offset that puts the row at the
  /// top edge, [bottom] the one that puts it at the bottom edge.
  static double? keepVisibleOffset({
    required double offset,
    required double top,
    required double bottom,
    required double minExtent,
    required double maxExtent,
  }) {
    double? target;
    // A row taller than the window shows its start.
    if (offset > top || bottom >= top) {
      target = top;
    } else if (offset < bottom) {
      target = bottom;
    }
    if (target == null) return null;
    final clamped = target.clamp(minExtent, maxExtent).toDouble();
    return (clamped - offset).abs() < 1 ? null : clamped;
  }
}
