/// One word as a forced aligner returned it, in the aligner's order.
class AlignedWord {
  final String text;
  final Duration start;
  final Duration end;

  const AlignedWord({
    required this.text,
    required this.start,
    required this.end,
  });

  Duration get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is AlignedWord &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(text, start, end);

  @override
  String toString() => 'AlignedWord($text, $start, $end)';
}

/// What [AlignerWordTimingRepair.repair] changed, for diagnostics.
class AlignerWordTimingRepairResult {
  final List<AlignedWord> words;

  /// Words that arrived with no length (end at or before start).
  final int zeroLengthWords;

  /// Groups of words that shared one instant and were spread out.
  final int spreadClusters;

  const AlignerWordTimingRepairResult({
    required this.words,
    required this.zeroLengthWords,
    required this.spreadClusters,
  });
}

/// Gives every word of a forced alignment a usable time span instead of
/// letting zero-length words disappear.
///
/// When the Qwen3 forced aligner cannot place words — typically a chant or
/// backing vocal the recogniser wrote several times — it returns them with
/// no length, all at one instant, and often stretches the next word over the
/// singing it could not place:
///
/// ```text
/// 223.445–223.445 Whoa      223.445–223.445 find
/// 223.445–223.445 I'm       …            (13 words at one instant)
/// 223.445–247.925 fire      ← stretched over the unplaced chant
/// ```
///
/// Dropping those words (as the parser once did) deleted 12–53 % of the
/// recognised words of real songs, most of them in repeated outro chants. This
/// repair keeps them all:
///
/// * a **cluster** — consecutive words starting within [clusterWindow] of the
///   first, each but the last without length — is spread over the cluster's
///   span (from its start to the latest end in it), in proportion to each
///   word's letters;
/// * when that span is longer than [maxSpreadWordLength] per word, the
///   cluster is placed at the span's **end**: in the measured songs the
///   stretched word started at the last placed word and the unplaced singing
///   came at its end (the chant at 238–255 s in a span from 223.4 to
///   247.9 s; intros swallowed by a first word starting at 0 s);
/// * when that span is shorter than [minWordLength] per word, it is extended
///   towards the next word's start, by at most [fallbackWordLength] per word,
///   and never past the next word;
/// * when there is no room at all the words keep zero length: their text
///   still reaches the draft and the editor's checks can flag the row.
///
/// Words that already have a length and are not part of a cluster are left
/// untouched. The order of words never changes.
class AlignerWordTimingRepair {
  const AlignerWordTimingRepair({
    this.clusterWindow = const Duration(milliseconds: 30),
    this.minWordLength = const Duration(milliseconds: 80),
    this.fallbackWordLength = const Duration(milliseconds: 350),
    this.maxSpreadWordLength = const Duration(milliseconds: 1200),
    this.zeroLengthTolerance = const Duration(milliseconds: 1),
  });

  final Duration clusterWindow;
  final Duration minWordLength;
  final Duration fallbackWordLength;
  final Duration maxSpreadWordLength;

  /// A word this short or shorter counts as having no length.
  final Duration zeroLengthTolerance;

  bool isZeroLength(AlignedWord word) =>
      word.end - word.start <= zeroLengthTolerance;

  AlignerWordTimingRepairResult repair(List<AlignedWord> input) {
    final words = [
      for (final word in input)
        if (word.text.trim().isNotEmpty)
          word.end < word.start
              ? AlignedWord(text: word.text, start: word.start, end: word.start)
              : word,
    ];
    final zeroLength = words.where(isZeroLength).length;
    final result = <AlignedWord>[];
    var clusters = 0;
    var index = 0;
    while (index < words.length) {
      final first = words[index];
      var end = index + 1;
      // Extend while the previous word has no length and the next starts at
      // (nearly) the same instant: the aligner piled them up.
      while (end < words.length &&
          isZeroLength(words[end - 1]) &&
          (words[end].start - first.start).abs() <= clusterWindow) {
        end++;
      }
      final cluster = words.sublist(index, end);
      if (cluster.length == 1 && !isZeroLength(first)) {
        result.add(first);
        index = end;
        continue;
      }

      var spanEnd = first.start;
      for (final word in cluster) {
        if (word.end > spanEnd) spanEnd = word.end;
      }
      final count = cluster.length;
      if (spanEnd - first.start < minWordLength * count) {
        final next = end < words.length ? words[end].start : null;
        var extended = first.start + fallbackWordLength * count;
        if (next != null && next < extended) extended = next;
        if (extended > spanEnd) spanEnd = extended;
      }
      var spanStart = first.start;
      final longest = spanStart + maxSpreadWordLength * count;
      if (spanEnd > longest) spanStart = spanEnd - maxSpreadWordLength * count;
      if (spanEnd <= spanStart) {
        result.addAll(cluster);
      } else {
        result.addAll(_spread(cluster, spanStart, spanEnd));
        clusters++;
      }
      index = end;
    }
    return AlignerWordTimingRepairResult(
      words: List.unmodifiable(result),
      zeroLengthWords: zeroLength,
      spreadClusters: clusters,
    );
  }

  /// Repairs [input] for consumers that need every span to have a length,
  /// such as the reference-alignment planners.
  ///
  /// [repair] runs first, so a cluster of unplaced words is spread out
  /// wherever there is room. Spans are then clamped to [limit] (the audio
  /// duration) when given. A word that is still without length is merged
  /// into the previous word with length — its text joined with a space, its
  /// time unchanged — or into the next one at the very start. Text is never
  /// dropped unless no word has a length at all, when the result is empty.
  ///
  /// Merging keeps the words' order and their text when whitespace is
  /// ignored, which is how the alignment planners compare text.
  List<AlignedWord> repairToTimedSpans(
    List<AlignedWord> input, {
    Duration? limit,
  }) {
    final repaired = [
      for (final word in repair(input).words)
        if (limit != null && word.end > limit)
          AlignedWord(
            text: word.text,
            start: word.start > limit ? limit : word.start,
            end: limit,
          )
        else
          word,
    ];
    final result = <AlignedWord>[];
    final pending = <String>[];
    for (final word in repaired) {
      if (word.end - word.start <= Duration.zero) {
        if (result.isEmpty) {
          pending.add(word.text.trim());
        } else {
          final previous = result.removeLast();
          result.add(
            AlignedWord(
              text: '${previous.text} ${word.text.trim()}',
              start: previous.start,
              end: previous.end,
            ),
          );
        }
        continue;
      }
      if (pending.isNotEmpty) {
        result.add(
          AlignedWord(
            text: [...pending, word.text.trim()].join(' '),
            start: word.start,
            end: word.end,
          ),
        );
        pending.clear();
      } else {
        result.add(word);
      }
    }
    return List.unmodifiable(result);
  }

  List<AlignedWord> _spread(
    List<AlignedWord> cluster,
    Duration start,
    Duration end,
  ) {
    final weights = [for (final word in cluster) _weight(word.text)];
    final total = weights.fold<int>(0, (sum, weight) => sum + weight);
    final span = (end - start).inMicroseconds;
    final spread = <AlignedWord>[];
    var used = 0;
    for (var index = 0; index < cluster.length; index++) {
      final from = start + Duration(microseconds: span * used ~/ total);
      used += weights[index];
      final to = index == cluster.length - 1
          ? end
          : start + Duration(microseconds: span * used ~/ total);
      spread.add(AlignedWord(text: cluster[index].text, start: from, end: to));
    }
    return spread;
  }

  /// Letters and digits in [text], at least one; a Han character or other
  /// spaceless-script character counts as two letters.
  static int _weight(String text) {
    var weight = 0;
    for (final rune in text.runes) {
      if ((rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5a) ||
          (rune >= 0x61 && rune <= 0x7a) ||
          (rune >= 0xc0 && rune <= 0x24f)) {
        weight += 1;
      } else if (rune >= 0x3040) {
        weight += 2;
      }
    }
    return weight < 1 ? 1 : weight;
  }
}
