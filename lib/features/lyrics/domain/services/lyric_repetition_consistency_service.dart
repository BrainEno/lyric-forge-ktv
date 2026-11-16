import '../../../project/domain/models/lyric_document.dart';
import '../text/chinese_script_converter.dart';

/// Why a group's recommended spelling was chosen.
enum LyricRepetitionRecommendation {
  /// One spelling occurs more often than every other one.
  majority,

  /// A spelling contains a row the user edited by hand; that wins over a
  /// majority of recognised rows.
  manuallyConfirmed,

  /// The counts tie and the recogniser's confidence breaks the tie. Never
  /// selected for automatic application.
  higherConfidence,

  /// No spelling can be preferred; the user has to choose.
  undecided,
}

/// One distinct spelling of a repeated line.
class LyricRepetitionVariant {
  /// The text as written on the first row with this spelling.
  final String text;

  /// Comparison key: script-folded, lower-cased, without whitespace and
  /// punctuation. Rows with the same key are one variant.
  final String key;

  /// Row indices with this spelling, ascending.
  final List<int> indices;

  /// Rows among [indices] that were edited by hand.
  final List<int> protectedIndices;

  /// Mean recogniser confidence over the scored rows, or null when none of
  /// them carries an engine score.
  final double? meanConfidence;

  const LyricRepetitionVariant({
    required this.text,
    required this.key,
    required this.indices,
    required this.protectedIndices,
    required this.meanConfidence,
  });

  int get count => indices.length;

  bool get hasProtectedRows => protectedIndices.isNotEmpty;
}

/// Rows that look like the same sung line but are spelt differently.
class LyricRepetitionGroup {
  /// Distinct spellings, most frequent first (ties: earliest row first).
  final List<LyricRepetitionVariant> variants;

  /// Index into [variants] of the suggested spelling, or null when undecided.
  final int? recommendedVariant;
  final LyricRepetitionRecommendation recommendation;

  const LyricRepetitionGroup({
    required this.variants,
    required this.recommendedVariant,
    required this.recommendation,
  });

  int get totalRows =>
      variants.fold(0, (total, variant) => total + variant.count);

  LyricRepetitionVariant? get recommended =>
      recommendedVariant == null ? null : variants[recommendedVariant!];

  /// Whether the dialog should pre-select this group for unification.
  ///
  /// Only clear cases are pre-selected: the recommended spelling is manually
  /// confirmed, or it occurs at least twice and at least twice as often as
  /// every other spelling. Two spellings that each recur are more likely an
  /// intentional variation between verses than a recognition error.
  bool get selectedByDefault {
    final target = recommended;
    if (target == null) return false;
    switch (recommendation) {
      case LyricRepetitionRecommendation.manuallyConfirmed:
        return true;
      case LyricRepetitionRecommendation.majority:
        if (target.count < 2) return false;
        for (final variant in variants) {
          if (identical(variant, target)) continue;
          if (variant.count * 2 > target.count) return false;
        }
        return true;
      case LyricRepetitionRecommendation.higherConfidence:
      case LyricRepetitionRecommendation.undecided:
        return false;
    }
  }
}

/// One row rewritten by a unification.
class LyricRepetitionChange {
  final int index;
  final String? lineId;
  final String before;
  final String after;

  const LyricRepetitionChange({
    required this.index,
    required this.lineId,
    required this.before,
    required this.after,
  });
}

/// The result of scanning a document for inconsistently recognised repeats.
class LyricRepetitionReport {
  final List<LyricRepetitionGroup> groups;

  /// Rows long enough to compare; short rows are never grouped.
  final int comparedRows;

  const LyricRepetitionReport({
    required this.groups,
    required this.comparedRows,
  });

  bool get hasGroups => groups.isNotEmpty;

  /// The rows that change when each group in [choices] is unified to the
  /// variant index it maps to. Protected rows are never rewritten unless
  /// [includeProtected] is set; rows already spelt like the target (ignoring
  /// punctuation and script) are left exactly as they are.
  List<LyricRepetitionChange> changesFor(
    LyricDocument document,
    Map<int, int> choices, {
    bool includeProtected = false,
  }) {
    final changes = <LyricRepetitionChange>[];
    for (final entry in choices.entries) {
      if (entry.key < 0 || entry.key >= groups.length) continue;
      final group = groups[entry.key];
      if (entry.value < 0 || entry.value >= group.variants.length) continue;
      final target = group.variants[entry.value];
      for (final variant in group.variants) {
        if (identical(variant, target)) continue;
        for (final index in variant.indices) {
          if (!includeProtected && variant.protectedIndices.contains(index)) {
            continue;
          }
          final line = document.lines[index];
          changes.add(
            LyricRepetitionChange(
              index: index,
              lineId: line.id,
              before: line.text,
              after: target.text,
            ),
          );
        }
      }
    }
    changes.sort((a, b) => a.index.compareTo(b.index));
    return changes;
  }

  /// Applies [changes] (from [changesFor]); only row text changes.
  static LyricDocument apply(
    LyricDocument document,
    List<LyricRepetitionChange> changes,
  ) {
    if (changes.isEmpty) return document;
    final lines = List<LyricLine>.of(document.lines);
    for (final change in changes) {
      final line = lines[change.index];
      if (line.text != change.before) {
        throw StateError(
          'Line ${change.index} changed after the repetition scan.',
        );
      }
      lines[change.index] = line.copyWith(text: change.after);
    }
    return document.copyWith(lines: lines);
  }
}

/// Finds repeated lines (choruses, hooks) that were recognised differently.
///
/// A chorus is usually sung three or four times with the same words, and a
/// recogniser seldom gets every repeat right: one pass reads 我爱你, the next
/// 我碍你. Without reference lyrics the other repeats are the best evidence
/// for the correct spelling, so this groups rows that are near-identical and
/// proposes the majority spelling for the outliers. It only reports; the
/// caller decides which groups to apply.
class LyricRepetitionConsistencyService {
  final ChineseScriptConverter converter;

  /// Rows with fewer comparable characters are ignored; short interjections
  /// (啊, oh baby) differ legitimately and carry no evidence.
  final int minimumKeyLength;

  /// Maximum edit distance relative to the longer key.
  final double maximumDifferenceRatio;

  /// Keys longer than this are compared on their first [maximumKeyLength]
  /// characters only, bounding the cost on pathological rows.
  final int maximumKeyLength;

  /// Minimum confidence gap (0–100) for confidence to break a tie.
  final double confidenceTieBreakGap;

  const LyricRepetitionConsistencyService({
    this.converter = const ChineseScriptConverter(),
    this.minimumKeyLength = 4,
    this.maximumDifferenceRatio = 0.25,
    this.maximumKeyLength = 80,
    this.confidenceTieBreakGap = 10,
  });

  static final RegExp _noise = RegExp(
    r'[\s，。、；：！？,.;:!?「」『』“”"'
    "'"
    r'()（）\[\]【】～~\-—…·♪]',
  );

  /// Comparison key for a row; empty when the row has nothing to compare.
  String keyFor(String text) {
    final folded = converter.foldForComparison(text.toLowerCase());
    final key = folded.replaceAll(_noise, '');
    final runes = key.runes.toList();
    if (runes.length <= maximumKeyLength) return key;
    return String.fromCharCodes(runes.take(maximumKeyLength));
  }

  LyricRepetitionReport analyze(
    LyricDocument document, {
    Set<int> protectedIndices = const {},
  }) {
    // 1. Rows with the same key form one variant.
    final byKey = <String, List<int>>{};
    var compared = 0;
    for (var index = 0; index < document.lines.length; index++) {
      final key = keyFor(document.lines[index].text);
      if (key.runes.length < minimumKeyLength) continue;
      compared++;
      byKey.putIfAbsent(key, () => <int>[]).add(index);
    }

    final variants = [
      for (final entry in byKey.entries)
        _variant(document, entry.key, entry.value, protectedIndices),
    ]..sort(_byFrequency);

    // 2. Greedy clustering: the most frequent unassigned variant seeds a
    //    group and absorbs every unassigned variant close to it. Comparing
    //    against the seed (not any member) keeps chains like A~B~C from
    //    merging A and C when they are not alike.
    final keyRunes = [
      for (final variant in variants) variant.key.runes.toList(),
    ];
    final assigned = List<bool>.filled(variants.length, false);
    final groups = <LyricRepetitionGroup>[];
    for (var seed = 0; seed < variants.length; seed++) {
      if (assigned[seed]) continue;
      assigned[seed] = true;
      final members = <LyricRepetitionVariant>[variants[seed]];
      for (var other = seed + 1; other < variants.length; other++) {
        if (assigned[other]) continue;
        if (_isNearDuplicate(keyRunes[seed], keyRunes[other])) {
          assigned[other] = true;
          members.add(variants[other]);
        }
      }
      if (members.length < 2) continue;
      groups.add(_group(members));
    }
    groups.sort((a, b) => _firstIndex(a).compareTo(_firstIndex(b)));
    return LyricRepetitionReport(
      groups: List.unmodifiable(groups),
      comparedRows: compared,
    );
  }

  LyricRepetitionVariant _variant(
    LyricDocument document,
    String key,
    List<int> indices,
    Set<int> protectedIndices,
  ) {
    var scored = 0;
    var total = 0;
    for (final index in indices) {
      final line = document.lines[index];
      if (!line.hasConfidenceScore) continue;
      scored++;
      total += line.confidence;
    }
    final protectedRows = [
      for (final index in indices)
        if (protectedIndices.contains(index)) index,
    ];
    // A manually edited row is the user's spelling, so it represents the
    // variant; otherwise the first row does.
    final representative = protectedRows.isNotEmpty
        ? protectedRows.first
        : indices.first;
    return LyricRepetitionVariant(
      text: document.lines[representative].text.trim(),
      key: key,
      indices: List.unmodifiable(indices),
      protectedIndices: List.unmodifiable(protectedRows),
      meanConfidence: scored == 0 ? null : total / scored,
    );
  }

  LyricRepetitionGroup _group(List<LyricRepetitionVariant> members) {
    final variants = [...members]..sort(_byFrequency);

    final confirmed = [
      for (var i = 0; i < variants.length; i++)
        if (variants[i].hasProtectedRows) i,
    ];
    if (confirmed.length == 1) {
      return LyricRepetitionGroup(
        variants: List.unmodifiable(variants),
        recommendedVariant: confirmed.single,
        recommendation: LyricRepetitionRecommendation.manuallyConfirmed,
      );
    }
    if (confirmed.length > 1) {
      // The user confirmed more than one spelling: the variation is
      // deliberate and nothing should be suggested.
      return LyricRepetitionGroup(
        variants: List.unmodifiable(variants),
        recommendedVariant: null,
        recommendation: LyricRepetitionRecommendation.undecided,
      );
    }

    if (variants[0].count > variants[1].count) {
      return LyricRepetitionGroup(
        variants: List.unmodifiable(variants),
        recommendedVariant: 0,
        recommendation: LyricRepetitionRecommendation.majority,
      );
    }

    final tied = [
      for (var i = 0; i < variants.length; i++)
        if (variants[i].count == variants[0].count) i,
    ];
    int? best;
    double? bestConfidence;
    double? runnerUp;
    for (final i in tied) {
      final confidence = variants[i].meanConfidence;
      if (confidence == null) {
        best = null;
        bestConfidence = null;
        break;
      }
      if (bestConfidence == null || confidence > bestConfidence) {
        runnerUp = bestConfidence;
        bestConfidence = confidence;
        best = i;
      } else if (runnerUp == null || confidence > runnerUp) {
        runnerUp = confidence;
      }
    }
    if (best != null &&
        bestConfidence != null &&
        runnerUp != null &&
        bestConfidence - runnerUp >= confidenceTieBreakGap) {
      return LyricRepetitionGroup(
        variants: List.unmodifiable(variants),
        recommendedVariant: best,
        recommendation: LyricRepetitionRecommendation.higherConfidence,
      );
    }
    return LyricRepetitionGroup(
      variants: List.unmodifiable(variants),
      recommendedVariant: null,
      recommendation: LyricRepetitionRecommendation.undecided,
    );
  }

  bool _isNearDuplicate(List<int> a, List<int> b) {
    final longer = a.length > b.length ? a.length : b.length;
    final shorter = a.length > b.length ? b.length : a.length;
    final allowed = (longer * maximumDifferenceRatio).floor();
    final budget = allowed < 1 ? 1 : allowed;
    if (longer - shorter > budget) return false;
    final distance = boundedEditDistance(a, b, budget);
    return distance != null && distance > 0 && distance <= budget;
  }

  /// Levenshtein distance between [a] and [b], or null when it exceeds
  /// [limit]. Uses a band of width `2 * limit + 1` around the diagonal.
  static int? boundedEditDistance(List<int> a, List<int> b, int limit) {
    if ((a.length - b.length).abs() > limit) return null;
    final big = limit + 1;
    var previous = List<int>.generate(
      b.length + 1,
      (j) => j <= limit ? j : big,
    );
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, big);
      current[0] = i <= limit ? i : big;
      final from = i - limit > 1 ? i - limit : 1;
      final to = i + limit < b.length ? i + limit : b.length;
      var rowMinimum = current[0];
      for (var j = from; j <= to; j++) {
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        var value = substitution;
        if (deletion < value) value = deletion;
        if (insertion < value) value = insertion;
        current[j] = value > big ? big : value;
        if (current[j] < rowMinimum) rowMinimum = current[j];
      }
      if (rowMinimum > limit) return null;
      previous = current;
    }
    final result = previous[b.length];
    return result > limit ? null : result;
  }

  static int _byFrequency(LyricRepetitionVariant a, LyricRepetitionVariant b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return a.indices.first.compareTo(b.indices.first);
  }

  static int _firstIndex(LyricRepetitionGroup group) {
    var first = group.variants.first.indices.first;
    for (final variant in group.variants) {
      if (variant.indices.first < first) first = variant.indices.first;
    }
    return first;
  }
}
