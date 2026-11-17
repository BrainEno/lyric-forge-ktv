import '../../../project/domain/models/lyric_document.dart';

/// The shape of a recognition loop that spans several ASR segments.
enum AsrSegmentLoopKind {
  /// The same row is emitted in consecutive segments (A A A A).
  repeatedRows,

  /// A group of two to four rows cycles back to back (A B A B A B).
  repeatedBlock,
}

/// One loop found in a recogniser's segment list.
///
/// A loop is evidence, not a verdict: songs repeat lines on purpose. Callers
/// decide what to do with it by asking an independent source (a history-free
/// re-decode, the second engine) whether the repetition is really sung.
class AsrSegmentLoop {
  final AsrSegmentLoopKind kind;

  /// First segment of the loop.
  final int firstIndex;

  /// One past the last segment of the loop.
  final int endIndex;

  /// Segments in one repetition: 1 for [AsrSegmentLoopKind.repeatedRows].
  final int blockRows;

  /// Start of the first looped segment.
  final Duration start;

  /// First segment of the compressed lead-in: rows just before the loop whose
  /// timestamps collapsed together with it (back-to-back rows of about a
  /// second each). Equal to [firstIndex] when there is none. A decoder that
  /// starts looping usually squeezes the last real lines into the same
  /// one-second grid first, so their timestamps are as unreliable as the loop.
  final int leadInIndex;

  /// Start of the audio the loop and its lead-in claim.
  final Duration spanStart;

  /// The audio the loop claims: up to the start of the next segment after the
  /// loop when that is later than the loop's own end. A decoder caught in a
  /// loop usually compresses its timestamps, so the looped rows describe less
  /// time than the audio they replaced.
  final Duration end;

  /// How many looped rows report more words per second than anyone sings.
  final int implausibleRateRows;

  /// The looped rows' median duration is at most
  /// [AsrSegmentLoopDetector.compressedRowDuration]: the decoder emitted them
  /// on a collapsed timestamp grid rather than where they were sung.
  final bool compressedTiming;

  /// The repeated rows' normalised keys, one per row of the block.
  final List<String> unitKeys;

  /// The repeated rows' text as first emitted, for diagnostics.
  final List<String> unitText;

  const AsrSegmentLoop({
    required this.kind,
    required this.firstIndex,
    required this.endIndex,
    required this.blockRows,
    required this.start,
    required this.leadInIndex,
    required this.spanStart,
    required this.end,
    required this.implausibleRateRows,
    required this.compressedTiming,
    required this.unitKeys,
    required this.unitText,
  });

  int get rowCount => endIndex - firstIndex;

  /// Complete repetitions of the block.
  int get repeats => rowCount ~/ blockRows;

  /// Segment indices of the loop, in order.
  List<int> get indices => [for (var i = firstIndex; i < endIndex; i++) i];

  /// Most of the looped rows are too dense to be sung in the time they claim:
  /// the decoder's timestamps collapsed, which only happens in a loop.
  bool get hasImplausibleTiming =>
      implausibleRateRows * 2 >= rowCount && implausibleRateRows >= 2;

  /// The repeat count alone is beyond what lyrics do back to back.
  bool get strong =>
      hasImplausibleTiming ||
      switch (kind) {
        AsrSegmentLoopKind.repeatedRows =>
          repeats >= AsrSegmentLoopDetector.strongRowRepeats,
        AsrSegmentLoopKind.repeatedBlock =>
          repeats >= AsrSegmentLoopDetector.strongBlockRepeats,
      };

  Map<String, dynamic> toMetadata() => {
    'kind': kind.name,
    'firstIndex': firstIndex,
    'endIndex': endIndex,
    'blockRows': blockRows,
    'repeats': repeats,
    'startMs': start.inMilliseconds,
    if (leadInIndex != firstIndex) 'leadInIndex': leadInIndex,
    'spanStartMs': spanStart.inMilliseconds,
    'endMs': end.inMilliseconds,
    'implausibleRateRows': implausibleRateRows,
    'compressedTiming': compressedTiming,
    'strong': strong,
    'unit': unitText,
  };
}

/// Finds loops that run across ASR segments.
///
/// whisper.cpp conditions every 30 s window on the text it decoded before
/// (up to 224 tokens of rolling history). Once a window repeats the previous
/// couplet, the next window sees that couplet twice in its prompt and is even
/// more likely to repeat it, so the loop feeds itself until the history is
/// reset — in songs that is often the whole second half. Each looped segment
/// is an ordinary-looking line, so a per-line repetition check cannot see it.
///
/// Rows are compared by [loopKey], which ignores case, punctuation and
/// back-to-back duplicate words, so `Oh-oh-oh-oh` and `Oh-oh-oh-oh-oh` match.
class AsrSegmentLoopDetector {
  /// Identical consecutive rows needed for a finding.
  static const int minRowRepeats = 3;

  /// Repetitions of a two-to-four row block needed for a finding.
  static const int minBlockRepeats = 3;

  /// Identical rows beyond which the repeat count alone is a loop.
  static const int strongRowRepeats = 6;

  /// Block repetitions beyond which the repeat count alone is a loop.
  static const int strongBlockRepeats = 4;

  /// Largest block considered.
  static const int maxBlockRows = 4;

  /// Spoken-unit rate above which a row cannot have been sung in its span.
  /// A unit is a word in spaced scripts and a character in CJK text; fast rap
  /// stays near five words a second.
  static const double maxPlausibleUnitsPerSecond = 7.0;

  /// Median row length at or below which a loop's timestamps count as
  /// collapsed.
  static const Duration compressedRowDuration = Duration(milliseconds: 1500);

  /// Largest gap between two rows of a compressed lead-in.
  static const Duration leadInGap = Duration(milliseconds: 200);

  /// Rows a compressed lead-in may reach back.
  static const int maxLeadInRows = 12;

  const AsrSegmentLoopDetector();

  List<AsrSegmentLoop> detect(List<LyricLine> lines) {
    final keys = [for (final line in lines) loopKey(line.text)];
    final loops = <AsrSegmentLoop>[];
    var index = 0;
    while (index < keys.length) {
      if (keys[index].isEmpty) {
        index++;
        continue;
      }
      final match = _longestRunAt(keys, index);
      if (match == null) {
        index++;
        continue;
      }
      final (blockRows, rowCount) = match;
      final endIndex = index + rowCount;
      final floor = loops.isEmpty ? 0 : loops.last.endIndex;
      loops.add(_buildLoop(lines, keys, index, endIndex, blockRows, floor));
      index = endIndex;
    }
    return List.unmodifiable(loops);
  }

  /// The block size and row count of the longest qualifying loop that starts
  /// at [start], preferring the smaller block on ties.
  (int, int)? _longestRunAt(List<String> keys, int start) {
    (int, int)? best;
    for (var blockRows = 1; blockRows <= maxBlockRows; blockRows++) {
      if (start + blockRows * 2 > keys.length) break;
      final block = keys.sublist(start, start + blockRows);
      if (block.any((key) => key.isEmpty)) break;
      // A block that is itself periodic (A A, A B A B) is found at its
      // smallest size.
      if (blockRows > 1 && _hasSmallerPeriod(block)) continue;
      var rows = blockRows;
      while (start + rows < keys.length &&
          keys[start + rows] == block[rows % blockRows]) {
        rows++;
      }
      final repeats = rows ~/ blockRows;
      final required = blockRows == 1 ? minRowRepeats : minBlockRepeats;
      if (repeats < required) continue;
      // Only whole repetitions belong to the loop; a trailing partial block
      // is an ordinary row that happens to start the next repetition.
      final covered = repeats * blockRows;
      if (best == null || covered > best.$2) best = (blockRows, covered);
    }
    return best;
  }

  static bool _hasSmallerPeriod(List<String> block) {
    for (var period = 1; period < block.length; period++) {
      if (block.length % period != 0) continue;
      var periodic = true;
      for (var i = period; i < block.length; i++) {
        if (block[i] != block[i - period]) {
          periodic = false;
          break;
        }
      }
      if (periodic) return true;
    }
    return false;
  }

  AsrSegmentLoop _buildLoop(
    List<LyricLine> lines,
    List<String> keys,
    int firstIndex,
    int endIndex,
    int blockRows,
    int floor,
  ) {
    var implausible = 0;
    var loopEnd = lines[firstIndex].endTime;
    final durations = <int>[];
    for (var i = firstIndex; i < endIndex; i++) {
      if (isImplausiblyDense(lines[i])) implausible++;
      if (lines[i].endTime > loopEnd) loopEnd = lines[i].endTime;
      durations.add((lines[i].endTime - lines[i].startTime).inMilliseconds);
    }
    if (endIndex < lines.length && lines[endIndex].startTime > loopEnd) {
      loopEnd = lines[endIndex].startTime;
    }
    durations.sort();
    final compressed =
        durations[durations.length ~/ 2] <=
        compressedRowDuration.inMilliseconds;
    var leadIn = firstIndex;
    if (compressed) {
      while (leadIn > floor &&
          firstIndex - leadIn < maxLeadInRows &&
          _continuesCompressedRun(lines[leadIn - 1], lines[leadIn])) {
        leadIn--;
      }
    }
    return AsrSegmentLoop(
      kind: blockRows == 1
          ? AsrSegmentLoopKind.repeatedRows
          : AsrSegmentLoopKind.repeatedBlock,
      firstIndex: firstIndex,
      endIndex: endIndex,
      blockRows: blockRows,
      start: lines[firstIndex].startTime,
      leadInIndex: leadIn,
      spanStart: lines[leadIn].startTime,
      end: loopEnd,
      implausibleRateRows: implausible,
      compressedTiming: compressed,
      unitKeys: List.unmodifiable(
        keys.sublist(firstIndex, firstIndex + blockRows),
      ),
      unitText: List.unmodifiable([
        for (var i = firstIndex; i < firstIndex + blockRows; i++)
          lines[i].text.trim(),
      ]),
    );
  }

  /// Whether [previous] belongs to the same collapsed timestamp grid as the
  /// row after it: short, wordy, and directly adjacent.
  static bool _continuesCompressedRun(LyricLine previous, LyricLine next) {
    final duration = previous.endTime - previous.startTime;
    if (duration > compressedRowDuration || duration <= Duration.zero) {
      return false;
    }
    if (spokenUnits(previous.text) < 3) return false;
    final gap = next.startTime - previous.endTime;
    return gap <= leadInGap && gap >= -leadInGap;
  }

  /// Whether [line] holds more spoken units than can be sung in its span.
  static bool isImplausiblyDense(LyricLine line) {
    final units = spokenUnits(line.text);
    if (units < 4) return false;
    final milliseconds = (line.endTime - line.startTime).inMilliseconds;
    if (milliseconds <= 0) return true;
    return units * 1000 / milliseconds > maxPlausibleUnitsPerSecond;
  }

  /// Words in spaced scripts plus characters of CJK text.
  static int spokenUnits(String text) {
    var units = 0;
    var inWord = false;
    for (final rune in text.runes) {
      if (_isCjk(rune)) {
        units++;
        inWord = false;
      } else if (_isWordRune(rune)) {
        if (!inWord) units++;
        inWord = true;
      } else if (inWord && (rune == 0x27 || rune == 0x2019)) {
        // An apostrophe inside a word does not end it ("don't").
        continue;
      } else {
        inWord = false;
      }
    }
    return units;
  }

  /// Lower-cased words with punctuation removed and back-to-back duplicates
  /// collapsed; CJK characters count as words. Empty for rows without words.
  static String loopKey(String text) {
    final collapsed = <String>[];
    for (final token in tokens(text)) {
      if (collapsed.isEmpty || collapsed.last != token) collapsed.add(token);
    }
    return collapsed.join(' ');
  }

  /// Lower-cased words of [text] in order, punctuation removed, repeats kept;
  /// each CJK character is a word and apostrophes join contractions.
  static List<String> tokens(String text) {
    final tokens = <String>[];
    final word = StringBuffer();
    void flush() {
      if (word.isEmpty) return;
      tokens.add(word.toString());
      word.clear();
    }

    for (final rune in text.toLowerCase().runes) {
      if (_isCjk(rune)) {
        flush();
        tokens.add(String.fromCharCode(rune));
      } else if (_isWordRune(rune)) {
        word.writeCharCode(rune);
      } else if (rune == 0x27 || rune == 0x2019) {
        // Apostrophes join contractions: "don't" and "dont" are one word.
        continue;
      } else {
        flush();
      }
    }
    flush();
    return tokens;
  }

  static final RegExp _wordCharacter = RegExp(
    r'[\p{L}\p{M}\p{N}]',
    unicode: true,
  );

  /// Letters, combining marks and digits of any script (CJK is handled by
  /// [_isCjk] first).
  static bool _isWordRune(int rune) =>
      _wordCharacter.hasMatch(String.fromCharCode(rune));

  static bool _isCjk(int rune) =>
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF);
}
