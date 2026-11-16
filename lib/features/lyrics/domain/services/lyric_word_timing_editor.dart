import '../../../project/domain/models/lyric_document.dart';
import '../models/timing_provenance.dart';
import 'lyric_karaoke_timing_service.dart';
import 'lyric_word_timing_service.dart';

/// Pure edits for fine-tuning one row's word timing (逐字微调).
///
/// Every operation takes the current word list and returns a new one; the
/// words never overlap, never go backwards and never get shorter than
/// [minimumWord]. Two words that touch share their boundary: moving one's
/// end moves the next one's start with it, so nudging a boundary does not
/// open a gap. Words that do not touch keep their gap until one of them is
/// pushed into the other.
class LyricWordTimingEditor {
  const LyricWordTimingEditor({
    this.wordTiming = const LyricWordTimingService(),
    this.karaoke = const LyricKaraokeTimingService(),
    this.minimumWord = const Duration(milliseconds: 40),
  });

  final LyricWordTimingService wordTiming;
  final LyricKaraokeTimingService karaoke;

  /// No word is made shorter than this.
  final Duration minimumWord;

  static const Duration _touching = Duration(milliseconds: 1);

  /// The words to start editing [line] from: its own word timing on the
  /// row's current span, or else the karaoke estimate, one word per unit.
  ({List<LyricWordTiming> words, bool estimated}) start(LyricLine line) {
    final own = wordTiming.normalized(line);
    if (own.isNotEmpty) return (words: own, estimated: false);
    if (line.endTime <= line.startTime) return (words: const [], estimated: true);
    return (
      words: List.unmodifiable([
        for (final syllable in karaoke.syllables(
          line.text,
          line.startTime,
          line.endTime,
        ))
          if (wordTiming.sungCount(syllable.text) > 0)
            LyricWordTiming(
              text: syllable.text.trim(),
              start: syllable.start,
              end: syllable.start + syllable.duration,
            ),
      ]),
      estimated: true,
    );
  }

  /// [words] with the start of word [index] moved to [to] (clamped). The
  /// previous word's end follows when it touched or would overlap.
  List<LyricWordTiming> moveStart(
    List<LyricWordTiming> words,
    int index,
    Duration to,
  ) {
    if (index < 0 || index >= words.length) return words;
    final word = words[index];
    final previous = index > 0 ? words[index - 1] : null;
    var lower = previous == null
        ? Duration.zero
        : previous.start + minimumWord;
    final upper = word.end - minimumWord;
    if (lower > upper) lower = upper;
    final value = _clamp(to, lower, upper);
    if (value == word.start) return words;
    final result = List<LyricWordTiming>.of(words);
    result[index] = _with(word, start: value);
    if (previous != null &&
        (previous.end > value ||
            (previous.end - word.start).abs() <= _touching)) {
      result[index - 1] = _with(previous, end: value);
    }
    return List.unmodifiable(result);
  }

  /// [words] with the end of word [index] moved to [to] (clamped, and not
  /// past [ceiling] for the last word). The next word's start follows when
  /// it touched or would overlap.
  List<LyricWordTiming> moveEnd(
    List<LyricWordTiming> words,
    int index,
    Duration to, {
    Duration? ceiling,
  }) {
    if (index < 0 || index >= words.length) return words;
    final word = words[index];
    final next = index + 1 < words.length ? words[index + 1] : null;
    final lower = word.start + minimumWord;
    var upper = next == null ? ceiling : next.end - minimumWord;
    if (upper != null && upper < lower) upper = lower;
    final value = _clamp(to, lower, upper);
    if (value == word.end) return words;
    final result = List<LyricWordTiming>.of(words);
    result[index] = _with(word, end: value);
    if (next != null &&
        (next.start < value || (next.start - word.end).abs() <= _touching)) {
      result[index + 1] = _with(next, start: value);
    }
    return List.unmodifiable(result);
  }

  /// [words] with word [index] moved as a whole by [delta], keeping its
  /// length, within its neighbours' bounds.
  List<LyricWordTiming> shift(
    List<LyricWordTiming> words,
    int index,
    Duration delta, {
    Duration? ceiling,
  }) {
    if (index < 0 || index >= words.length || delta == Duration.zero) {
      return words;
    }
    if (delta.isNegative) {
      final moved = moveStart(words, index, words[index].start + delta);
      return moveEnd(
        moved,
        index,
        moved[index].start + (words[index].end - words[index].start),
        ceiling: ceiling,
      );
    }
    final moved = moveEnd(
      words,
      index,
      words[index].end + delta,
      ceiling: ceiling,
    );
    return moveStart(
      moved,
      index,
      moved[index].end - (words[index].end - words[index].start),
    );
  }

  /// [words] with word [index] and the next one joined into one word.
  List<LyricWordTiming> mergeWithNext(List<LyricWordTiming> words, int index) {
    if (index < 0 || index + 1 >= words.length) return words;
    final first = words[index];
    final second = words[index + 1];
    final space = _endsWithLetter(first.text) && _startsWithLetter(second.text)
        ? ' '
        : '';
    final result = List<LyricWordTiming>.of(words)
      ..replaceRange(index, index + 2, [
        LyricWordTiming(
          text: '${first.text}$space${second.text}',
          start: first.start,
          end: second.end > first.end ? second.end : first.end,
        ),
      ]);
    return List.unmodifiable(result);
  }

  /// [words] with word [index] split in the middle of its sung characters,
  /// its time divided by character count. Words with one sung character
  /// cannot be split.
  List<LyricWordTiming> split(List<LyricWordTiming> words, int index) {
    if (index < 0 || index >= words.length) return words;
    final word = words[index];
    final count = wordTiming.sungCount(word.text);
    if (count < 2) return words;
    final half = (count + 1) ~/ 2;
    final runes = word.text.runes.toList(growable: false);
    var sung = 0;
    var cut = runes.length;
    for (var position = 0; position < runes.length; position++) {
      if (sung == half && wordTiming.isSung(runes[position])) {
        cut = position;
        break;
      }
      if (wordTiming.isSung(runes[position])) sung++;
    }
    final left = String.fromCharCodes(runes.sublist(0, cut)).trim();
    final right = String.fromCharCodes(runes.sublist(cut)).trim();
    if (left.isEmpty || right.isEmpty) return words;
    final span = (word.end - word.start).inMicroseconds;
    final middle = word.start + Duration(microseconds: span * half ~/ count);
    final result = List<LyricWordTiming>.of(words)
      ..replaceRange(index, index + 1, [
        LyricWordTiming(text: left, start: word.start, end: middle),
        LyricWordTiming(text: right, start: middle, end: word.end),
      ]);
    return List.unmodifiable(result);
  }

  /// [line] with [words] as its word timing. The row grows to cover the
  /// words; with [fitRow] it starts at the first word and ends with the
  /// last one instead.
  LyricLine apply(
    LyricLine line,
    List<LyricWordTiming> words, {
    bool fitRow = false,
  }) {
    if (words.isEmpty) return line.copyWith(words: const []);
    var start = line.startTime;
    var end = line.endTime;
    final first = words.first.start;
    final last = words.last.end;
    if (fitRow || first < start) start = first;
    if (fitRow || last > end) end = last;
    return line.copyWith(
      startTime: start,
      endTime: end,
      words: List.unmodifiable(words),
    );
  }

  /// [document] with row [index] replaced by [line], recorded as timed by
  /// hand.
  LyricDocument replaceRow(LyricDocument document, int index, LyricLine line) {
    final lines = List<LyricLine>.of(document.lines);
    lines[index] = line;
    final id = line.id;
    if (id == null) return document.copyWith(lines: lines);
    final raw = document.metadata[kLyricTimingProvenanceKey];
    return document.copyWith(
      lines: lines,
      metadata: {
        ...document.metadata,
        kLyricTimingProvenanceKey: {
          if (raw is Map)
            for (final entry in raw.entries)
              if (entry.key is String) entry.key as String: entry.value,
          id: LyricTimingProvenance.manual.name,
        },
      },
    );
  }

  /// Whether [words] differ from [other] in text or time.
  static bool sameWords(List<LyricWordTiming> words, List<LyricWordTiming> other) {
    if (words.length != other.length) return false;
    for (var index = 0; index < words.length; index++) {
      final a = words[index];
      final b = other[index];
      if (a.text != b.text || a.start != b.start || a.end != b.end) {
        return false;
      }
    }
    return true;
  }

  static Duration _clamp(Duration value, Duration lower, Duration? upper) {
    if (value < lower) return lower;
    if (upper != null && value > upper) return upper;
    return value;
  }

  static LyricWordTiming _with(
    LyricWordTiming word, {
    Duration? start,
    Duration? end,
  }) => LyricWordTiming(
    text: word.text,
    start: start ?? word.start,
    end: end ?? word.end,
  );

  static bool _isAsciiLetter(int rune) =>
      (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);

  static bool _endsWithLetter(String text) =>
      text.isNotEmpty && _isAsciiLetter(text.runes.last);

  static bool _startsWithLetter(String text) =>
      text.isNotEmpty && _isAsciiLetter(text.runes.first);
}
