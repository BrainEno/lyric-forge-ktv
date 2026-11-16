import '../../../project/domain/models/lyric_document.dart';
import 'lyric_line_structure_service.dart';

/// The time of one sung character of a row, on the row's current timeline.
typedef LyricCharacterTime = ({Duration start, Duration end});

/// Reads, validates and transforms per-word timing ([LyricLine.words]).
///
/// Word times are matched to a row by **sung characters**: every rune that
/// carries singing weight (Han, kana, Hangul, letters, digits) counts, while
/// spaces and punctuation do not. A row's words are usable as long as they
/// contain exactly as many sung characters as the row's text, which keeps
/// them through script conversion, punctuation clean-up and single-character
/// corrections, and drops them as soon as a character is added or removed.
///
/// Words keep the absolute times they were recorded with. When they still
/// lie inside the row (within [tolerance]) they are used as they are;
/// when the row has since been moved or stretched (chunk offsets, timing
/// shift, tap-to-sync, a trimmed end), they are mapped linearly from their
/// own span onto the row's span.
class LyricWordTimingService {
  const LyricWordTimingService({
    this.structure = const LyricLineStructureService(),
    this.tolerance = const Duration(milliseconds: 60),
  });

  final LyricLineStructureService structure;

  /// How far the words may stick out of the row and still count as inside.
  final Duration tolerance;

  /// Whether [rune] is a sung character.
  bool isSung(int rune) => structure.sungWeight(String.fromCharCode(rune)) > 0;

  /// How many sung characters [text] has.
  int sungCount(String text) {
    var count = 0;
    for (final rune in text.runes) {
      if (isSung(rune)) count++;
    }
    return count;
  }

  /// Whether [line] has word timing that matches its text and span.
  bool isUsable(LyricLine line) => characterTimes(line) != null;

  /// One entry per sung character of [line]'s text, on the row's current
  /// timeline and inside its span, or null when the row has no usable word
  /// timing.
  ///
  /// A word with several sung characters is divided evenly between them.
  List<LyricCharacterTime>? characterTimes(LyricLine line) {
    final words = line.words;
    if (words.isEmpty) return null;
    final rowStart = line.startTime;
    final rowEnd = line.endTime;
    if (rowEnd <= rowStart) return null;

    final raw = <LyricCharacterTime>[];
    for (final word in words) {
      final count = sungCount(word.text);
      if (count == 0) continue;
      final end = word.end > word.start ? word.end : word.start;
      final span = (end - word.start).inMicroseconds;
      for (var index = 0; index < count; index++) {
        raw.add((
          start: word.start + Duration(microseconds: span * index ~/ count),
          end: word.start + Duration(microseconds: span * (index + 1) ~/ count),
        ));
      }
    }
    if (raw.isEmpty || raw.length != sungCount(line.text)) return null;

    var wordsStart = raw.first.start;
    var wordsEnd = raw.first.end;
    for (final time in raw) {
      if (time.start < wordsStart) wordsStart = time.start;
      if (time.end > wordsEnd) wordsEnd = time.end;
    }

    final inside =
        wordsStart >= rowStart - tolerance && wordsEnd <= rowEnd + tolerance;
    Duration place(Duration value) {
      Duration mapped;
      if (inside || wordsEnd <= wordsStart) {
        mapped = inside ? value : rowStart;
      } else {
        final ratio =
            (value - wordsStart).inMicroseconds /
            (wordsEnd - wordsStart).inMicroseconds;
        mapped =
            rowStart +
            Duration(
              microseconds: ((rowEnd - rowStart).inMicroseconds * ratio)
                  .round(),
            );
      }
      if (mapped < rowStart) return rowStart;
      if (mapped > rowEnd) return rowEnd;
      return mapped;
    }

    final result = <LyricCharacterTime>[];
    var floor = rowStart;
    for (final time in raw) {
      var start = place(time.start);
      if (start < floor) start = floor;
      var end = place(time.end);
      if (end < start) end = start;
      result.add((start: start, end: end));
      floor = start;
    }
    return result;
  }

  /// Words for the sung characters [from] (inclusive) to [to] (exclusive)
  /// of [line], on the row's current timeline, grouped as the original
  /// words were. Empty when the row has no usable word timing.
  List<LyricWordTiming> slice(LyricLine line, int from, int to) {
    final times = characterTimes(line);
    if (times == null || from >= to) return const [];
    final result = <LyricWordTiming>[];
    var position = 0;
    for (final word in line.words) {
      final runes = word.text.runes.toList(growable: false);
      final count = runes.where(isSung).length;
      if (count == 0) continue;
      final first = position < from ? from : position;
      final last = position + count > to ? to : position + count;
      if (first < last) {
        final text = StringBuffer();
        var sungIndex = position;
        for (final rune in runes) {
          if (isSung(rune)) {
            if (sungIndex >= first && sungIndex < last) {
              text.writeCharCode(rune);
            }
            sungIndex++;
          } else if (sungIndex > first && sungIndex <= last) {
            // Punctuation and spaces after a kept character stay with it.
            text.writeCharCode(rune);
          }
        }
        result.add(
          LyricWordTiming(
            text: text.toString(),
            start: times[first].start,
            end: times[last - 1].end,
          ),
        );
      }
      position += count;
      if (position >= to) break;
    }
    return List.unmodifiable(result);
  }

  /// The row's words re-based onto its current span, so they survive later
  /// edits that rely on absolute times. Empty when not usable.
  List<LyricWordTiming> normalized(LyricLine line) =>
      slice(line, 0, sungCount(line.text));

  /// Where the sung character at [index] begins, or null.
  Duration? characterStart(LyricLine line, int index) {
    final times = characterTimes(line);
    if (times == null || index < 0 || index >= times.length) return null;
    return times[index].start;
  }

  /// How many rows of [document] have usable word timing.
  int usableRowCount(LyricDocument document) =>
      document.lines.where(isUsable).length;
}
