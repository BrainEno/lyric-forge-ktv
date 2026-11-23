import '../../../project/domain/models/lyric_document.dart';
import 'lyric_timing_shift_service.dart';

/// What the 跳到行 box (D-067) made of the text typed into it.
class LyricLineLocation {
  const LyricLineLocation._({this.index, this.time, this.problem});

  const LyricLineLocation.row(int index) : this._(index: index);

  const LyricLineLocation.atTime(int index, Duration time)
    : this._(index: index, time: time);

  const LyricLineLocation.invalid(String problem) : this._(problem: problem);

  /// The row to go to, or null when the text names none.
  final int? index;

  /// The time typed, when the row was found by time rather than by number.
  final Duration? time;

  /// Why nothing was found, in words for the person typing.
  final String? problem;

  bool get isValid => index != null;
}

/// Finds the row a person means by a row number or by a time in the song.
///
/// Row numbers are as the list shows them, from 1. A time is written the
/// way the list shows start times (`1:23`, `1:23.45`) or in seconds with a
/// unit (`83s`, `83 秒`) or a decimal point (`83.5`). Full-width digits and
/// punctuation from a Chinese keyboard work too, and so do `第 12 行` and
/// `#12`.
abstract final class LyricLineLocator {
  /// Shown before anything is typed.
  static String hint(int lineCount) => '行号 1–$lineCount，或时间，例如 1:23';

  static LyricLineLocation locate(LyricDocument document, String raw) {
    final count = document.lines.length;
    if (count == 0) return const LyricLineLocation.invalid('还没有歌词行');
    final text = _normalize(raw);
    if (text.isEmpty) return LyricLineLocation.invalid(hint(count));

    final row = RegExp(r'^(?:第|#)?\s*(\d+)\s*行?$').firstMatch(text);
    if (row != null) {
      final number = int.tryParse(row.group(1)!);
      if (number == null || number < 1 || number > count) {
        return LyricLineLocation.invalid(
          '没有第 ${row.group(1)} 行，这首歌一共 $count 行',
        );
      }
      return LyricLineLocation.row(number - 1);
    }

    if (text.startsWith('-') || text.startsWith('−')) {
      return const LyricLineLocation.invalid('时间不能是负数');
    }
    final time = parseLyricTimeInput(text);
    if (time == null) {
      return const LyricLineLocation.invalid('看不懂这个输入，请填行号，或像 1:23 这样的时间');
    }
    return LyricLineLocation.atTime(rowAt(document, time), time);
  }

  /// The row sung at [time]: the latest-starting row that covers it, else
  /// the next row to start after it (a gap between rows), else the row that
  /// starts last (past the end of the lyrics).
  static int rowAt(LyricDocument document, Duration time) {
    final lines = document.lines;
    int? covering;
    int? next;
    var last = 0;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.startTime >= lines[last].startTime) last = index;
      if (line.startTime <= time && time < line.endTime) {
        if (covering == null || line.startTime >= lines[covering].startTime) {
          covering = index;
        }
      } else if (line.startTime > time) {
        if (next == null || line.startTime < lines[next].startTime) {
          next = index;
        }
      }
    }
    return covering ?? next ?? last;
  }

  static String _normalize(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.trim().runes) {
      // Full-width ASCII (U+FF01–U+FF5E) as typed on a Chinese keyboard.
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString().replaceAll('。', '.').trim();
  }
}
