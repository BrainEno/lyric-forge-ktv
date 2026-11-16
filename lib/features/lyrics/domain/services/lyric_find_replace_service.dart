import '../../../project/domain/models/lyric_document.dart';
import '../text/chinese_script_converter.dart';

/// What to look for and what to put in its place.
class LyricFindReplaceQuery {
  final String find;
  final String replacement;

  /// Treats the simplified, traditional and regional forms of a character as
  /// the same, so 爱 also finds 愛. The replacement is inserted as typed.
  final bool ignoreChineseScript;

  /// Ignores letter case for Latin text.
  final bool ignoreCase;

  /// Only matches Latin text at word boundaries, so "love" does not hit
  /// "lovely". Has no effect on CJK text, which has no word boundaries.
  final bool wholeWord;

  const LyricFindReplaceQuery({
    required this.find,
    required this.replacement,
    this.ignoreChineseScript = true,
    this.ignoreCase = true,
    this.wholeWord = false,
  });
}

/// Why a find-and-replace plan has nothing to apply.
enum LyricFindReplaceNoopReason {
  /// The search text is empty.
  emptyQuery,

  /// No line contains the search text.
  noMatches,

  /// Every match already reads exactly like the replacement.
  replacementIdentical,

  /// Lines matched, but all of them were edited by hand and are skipped.
  onlyProtectedLines,
}

/// A matched span in a line, in UTF-16 offsets of the original text.
class LyricTextSpanRange {
  final int start;
  final int end;

  const LyricTextSpanRange(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      other is LyricTextSpanRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'LyricTextSpanRange($start, $end)';
}

/// One line the search found.
class LyricFindReplaceMatch {
  final int index;
  final String? lineId;
  final String before;
  final String after;
  final List<LyricTextSpanRange> ranges;

  /// The line was edited by hand; it is listed but not replaced unless the
  /// caller opts in.
  final bool isProtected;

  const LyricFindReplaceMatch({
    required this.index,
    required this.lineId,
    required this.before,
    required this.after,
    required this.ranges,
    required this.isProtected,
  });

  int get occurrences => ranges.length;

  bool get changesText => before != after;
}

/// A preview of a find-and-replace across the whole document.
class LyricFindReplacePlan {
  final LyricFindReplaceQuery query;

  /// Every line that contains the search text, in document order, including
  /// protected and unchanged ones so the preview can explain them.
  final List<LyricFindReplaceMatch> matches;
  final LyricFindReplaceNoopReason? noopReason;

  const LyricFindReplacePlan({
    required this.query,
    required this.matches,
    required this.noopReason,
  });

  /// Lines that will be rewritten when the plan is applied as is.
  List<LyricFindReplaceMatch> get changes => [
    for (final match in matches)
      if (!match.isProtected && match.changesText) match,
  ];

  List<LyricFindReplaceMatch> get protectedMatches => [
    for (final match in matches)
      if (match.isProtected && match.changesText) match,
  ];

  bool get hasChanges => changes.isNotEmpty;

  int get totalOccurrences =>
      matches.fold(0, (total, match) => total + match.occurrences);

  /// Applies the replacement to every line in [changes] except the indices
  /// in [excludedIndices]. Only text changes; timing and ids are kept.
  LyricDocument applyTo(
    LyricDocument document, {
    Set<int> excludedIndices = const {},
  }) {
    final selected = selectedChanges(excludedIndices);
    if (selected.isEmpty) return document;
    final lines = List<LyricLine>.of(document.lines);
    for (final change in selected) {
      final line = lines[change.index];
      if (line.text != change.before) {
        throw StateError(
          'Line ${change.index} changed after the replace plan was made.',
        );
      }
      lines[change.index] = line.copyWith(text: change.after);
    }
    return document.copyWith(lines: lines);
  }

  List<LyricFindReplaceMatch> selectedChanges(Set<int> excludedIndices) => [
    for (final change in changes)
      if (!excludedIndices.contains(change.index)) change,
  ];
}

/// Plans a document-wide find-and-replace.
///
/// Recognisers tend to get the same word wrong every time it is sung, most
/// often names, places and English words inside Chinese lyrics. Fixing one
/// row at a time misses repeats; this replaces every occurrence at once
/// after a preview. Matching can ignore simplified/traditional differences,
/// because a recognised draft frequently mixes the two.
class LyricFindReplaceService {
  final ChineseScriptConverter converter;

  const LyricFindReplaceService({
    this.converter = const ChineseScriptConverter(),
  });

  LyricFindReplacePlan plan(
    LyricDocument document, {
    required LyricFindReplaceQuery query,
    Set<int> protectedIndices = const {},
    bool includeProtected = false,
  }) {
    if (query.find.isEmpty) {
      return LyricFindReplacePlan(
        query: query,
        matches: const [],
        noopReason: LyricFindReplaceNoopReason.emptyQuery,
      );
    }
    final needle = _foldedRunes(query.find, query);
    final matches = <LyricFindReplaceMatch>[];
    for (var index = 0; index < document.lines.length; index++) {
      final line = document.lines[index];
      final ranges = findRanges(line.text, query, foldedNeedle: needle);
      if (ranges.isEmpty) continue;
      matches.add(
        LyricFindReplaceMatch(
          index: index,
          lineId: line.id,
          before: line.text,
          after: _replace(line.text, ranges, query.replacement),
          ranges: List.unmodifiable(ranges),
          isProtected: !includeProtected && protectedIndices.contains(index),
        ),
      );
    }

    LyricFindReplaceNoopReason? noop;
    if (matches.isEmpty) {
      noop = LyricFindReplaceNoopReason.noMatches;
    } else if (!matches.any((match) => match.changesText)) {
      noop = LyricFindReplaceNoopReason.replacementIdentical;
    } else if (!matches.any(
      (match) => match.changesText && !match.isProtected,
    )) {
      noop = LyricFindReplaceNoopReason.onlyProtectedLines;
    }
    return LyricFindReplacePlan(
      query: query,
      matches: List.unmodifiable(matches),
      noopReason: noop,
    );
  }

  /// Non-overlapping occurrences of the query in [text], left to right.
  List<LyricTextSpanRange> findRanges(
    String text,
    LyricFindReplaceQuery query, {
    List<int>? foldedNeedle,
  }) {
    final needle = foldedNeedle ?? _foldedRunes(query.find, query);
    if (needle.isEmpty || text.isEmpty) return const [];
    final runes = text.runes.toList();
    final haystack = [for (final rune in runes) _foldRune(rune, query)];
    // UTF-16 offset of every rune, plus the end, so ranges map back to the
    // original string even with surrogate pairs.
    final offsets = List<int>.filled(runes.length + 1, 0);
    for (var i = 0; i < runes.length; i++) {
      offsets[i + 1] = offsets[i] + (runes[i] > 0xffff ? 2 : 1);
    }

    final ranges = <LyricTextSpanRange>[];
    var i = 0;
    while (i + needle.length <= haystack.length) {
      if (_matchesAt(haystack, needle, i) &&
          (!query.wholeWord || _isWordBounded(runes, i, needle.length))) {
        ranges.add(LyricTextSpanRange(offsets[i], offsets[i + needle.length]));
        i += needle.length;
      } else {
        i++;
      }
    }
    return ranges;
  }

  static bool _matchesAt(List<int> haystack, List<int> needle, int start) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[start + j] != needle[j]) return false;
    }
    return true;
  }

  static bool _isWordBounded(List<int> runes, int start, int length) {
    final first = runes[start];
    final last = runes[start + length - 1];
    if (_isLatinWordRune(first) &&
        start > 0 &&
        _isLatinWordRune(runes[start - 1])) {
      return false;
    }
    final end = start + length;
    if (_isLatinWordRune(last) &&
        end < runes.length &&
        _isLatinWordRune(runes[end])) {
      return false;
    }
    return true;
  }

  static bool _isLatinWordRune(int rune) =>
      (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5a) ||
      (rune >= 0x61 && rune <= 0x7a) ||
      rune == 0x27 ||
      (rune >= 0xc0 && rune <= 0x24f && rune != 0xd7 && rune != 0xf7);

  List<int> _foldedRunes(String text, LyricFindReplaceQuery query) => [
    for (final rune in text.runes) _foldRune(rune, query),
  ];

  int _foldRune(int rune, LyricFindReplaceQuery query) {
    var folded = rune;
    if (query.ignoreCase) folded = _lowerCase(folded);
    if (query.ignoreChineseScript) folded = converter.foldRune(folded);
    return folded;
  }

  /// Lower-cases ASCII, Latin-1 and full-width Latin letters; anything else is
  /// returned unchanged so the rune count never shifts.
  static int _lowerCase(int rune) {
    if (rune >= 0x41 && rune <= 0x5a) return rune + 0x20;
    if (rune >= 0xc0 && rune <= 0xde && rune != 0xd7) return rune + 0x20;
    if (rune >= 0xff21 && rune <= 0xff3a) return rune + 0x20;
    return rune;
  }

  static String _replace(
    String text,
    List<LyricTextSpanRange> ranges,
    String replacement,
  ) {
    final output = StringBuffer();
    var cursor = 0;
    for (final range in ranges) {
      output
        ..write(text.substring(cursor, range.start))
        ..write(replacement);
      cursor = range.end;
    }
    output.write(text.substring(cursor));
    return output.toString();
  }
}
