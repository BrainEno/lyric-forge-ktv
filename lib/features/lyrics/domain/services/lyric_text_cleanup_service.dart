import '../../../project/domain/models/lyric_document.dart';
import '../text/chinese_script_converter.dart';
import 'lyric_indexed_review_metadata.dart';

/// One mechanical clean-up rule for recognised lyric text.
///
/// Every rule changes only how a line is written, never what is sung, so a
/// preview of the result is enough for the user to judge it. Rules that drop
/// whole rows ([removeAsrBoilerplate], [removeAnnotationOnlyLines],
/// [removeEmptyLines]) are listed separately in the preview.
enum LyricTextCleanupRule {
  /// Trims each line, turns ideographic spaces into ASCII spaces and collapses
  /// runs of whitespace into one space.
  normalizeWhitespace,

  /// Converts full-width ASCII letters, digits and symbols (Ａ１！) to their
  /// half-width forms; CJK punctuation such as ，。 is left alone.
  fullWidthAscii,

  /// Removes bracketed non-lyric annotations the recogniser inserts, such as
  /// [音乐], (Music), 【掌声】 and ♪ marks.
  stripAnnotations,

  /// Replaces sentence punctuation inside a line (我爱你，你爱我) with one
  /// space, the usual karaoke convention.
  internalPunctuationToSpace,

  /// Removes sentence punctuation at the end of a line (，。,. and similar);
  /// question and exclamation marks are kept because they can be sung.
  trailingPunctuation,

  /// Removes spaces between two Chinese or Japanese characters. Off by default:
  /// many Chinese lyric files use spaces as deliberate phrase breaks. Hangul is
  /// never touched because Korean separates words with spaces.
  removeCjkSpaces,

  /// Deletes rows that are well-known speech-recogniser hallucinations on
  /// silence or music (字幕由Amara.org社区提供, 谢谢观看, Thanks for watching).
  removeAsrBoilerplate,

  /// Deletes rows that contain nothing but annotations or music marks.
  removeAnnotationOnlyLines,

  /// Deletes rows whose text is empty. Off by default: an empty row can be a
  /// deliberate gap in the karaoke display.
  removeEmptyLines;

  /// Rules enabled when the clean-up dialog opens.
  static const Set<LyricTextCleanupRule> defaults = {
    normalizeWhitespace,
    fullWidthAscii,
    stripAnnotations,
    internalPunctuationToSpace,
    trailingPunctuation,
    removeAsrBoilerplate,
    removeAnnotationOnlyLines,
  };

  /// Whether this rule deletes rows instead of rewriting text.
  bool get removesLines =>
      this == removeAsrBoilerplate ||
      this == removeAnnotationOnlyLines ||
      this == removeEmptyLines;
}

/// One line the clean-up rewrites.
class LyricTextCleanupChange {
  final int index;
  final String? lineId;
  final String before;
  final String after;

  /// Text rules that changed this line, in the order they ran.
  final List<LyricTextCleanupRule> rules;

  const LyricTextCleanupChange({
    required this.index,
    required this.lineId,
    required this.before,
    required this.after,
    required this.rules,
  });
}

/// One row the clean-up deletes.
class LyricTextCleanupRemoval {
  final int index;
  final String? lineId;
  final String text;
  final LyricTextCleanupRule rule;

  const LyricTextCleanupRemoval({
    required this.index,
    required this.lineId,
    required this.text,
    required this.rule,
  });
}

/// A preview of the clean-up; nothing is applied until [applyTo] is called.
class LyricTextCleanupPlan {
  final Set<LyricTextCleanupRule> rules;
  final List<LyricTextCleanupChange> changes;
  final List<LyricTextCleanupRemoval> removals;

  /// Rows that would change or be deleted but were edited by hand, so the
  /// plan leaves them alone.
  final List<int> skippedProtectedIndices;

  const LyricTextCleanupPlan({
    required this.rules,
    required this.changes,
    required this.removals,
    required this.skippedProtectedIndices,
  });

  bool get hasChanges => changes.isNotEmpty || removals.isNotEmpty;

  /// How many rows each rule touches, for the rule list in the dialog.
  Map<LyricTextCleanupRule, int> get countsByRule {
    final counts = <LyricTextCleanupRule, int>{};
    for (final change in changes) {
      for (final rule in change.rules) {
        counts[rule] = (counts[rule] ?? 0) + 1;
      }
    }
    for (final removal in removals) {
      counts[removal.rule] = (counts[removal.rule] ?? 0) + 1;
    }
    return counts;
  }

  /// The row the editor should select after applying: the first surviving
  /// changed row, otherwise the row now at the first deleted position.
  int? selectionAfterApply(int lineCountBefore) {
    final removed = {for (final removal in removals) removal.index};
    if (changes.isNotEmpty) {
      final first = changes.first.index;
      return first - removed.where((index) => index < first).length;
    }
    if (removals.isEmpty) return null;
    final remaining = lineCountBefore - removals.length;
    if (remaining <= 0) return null;
    final position = removals.first.index;
    return position < remaining ? position : remaining - 1;
  }

  /// Applies the plan. Text changes keep timing, ids and confidence; deleted
  /// rows take their row-indexed review evidence with them.
  LyricDocument applyTo(LyricDocument document) {
    if (!hasChanges) return document;
    final lines = List<LyricLine>.of(document.lines);
    for (final change in changes) {
      final line = lines[change.index];
      if (line.text != change.before) {
        throw StateError(
          'Line ${change.index} changed after the clean-up plan was made.',
        );
      }
      lines[change.index] = line.copyWith(text: change.after);
    }
    var metadata = document.metadata;
    final descending = [...removals]
      ..sort((a, b) => b.index.compareTo(a.index));
    for (final removal in descending) {
      if (lines[removal.index].text != removal.text) {
        throw StateError(
          'Line ${removal.index} changed after the clean-up plan was made.',
        );
      }
      lines.removeAt(removal.index);
      metadata = LyricIndexedReviewMetadata.afterRowRemoved(
        metadata,
        removal.index,
      );
    }
    return document.copyWith(lines: lines, metadata: metadata);
  }
}

/// Plans mechanical clean-up of recognised lyric text.
///
/// Speech recognisers write lyrics like prose: sentence punctuation, full-width
/// letters, [音乐] markers and, on silent stretches, captions they learned from
/// video subtitles. None of that belongs on a karaoke screen, and fixing it by
/// hand row by row is the most tedious part of proofreading. The plan is a
/// preview; manually edited rows are skipped unless the caller opts in.
class LyricTextCleanupService {
  const LyricTextCleanupService();

  /// Sentence punctuation that is replaced inside a line and removed at its
  /// end. Question and exclamation marks are deliberately absent.
  static const String sentencePunctuation = '，。、；：,.;:';

  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Bracketed spans that hold a recogniser annotation rather than lyrics.
  /// Only short spans whose content is a known marker word are removed, so a
  /// sung parenthetical such as (你在哪里) survives.
  static final RegExp _bracketedSpan = RegExp(
    r'[\[\(（【〔<《「]\s*([^\]\)）】〕>》」]{1,24}?)\s*[\]\)）】〕>》」]',
  );

  static final RegExp _musicMarks = RegExp('[♪♫♬♩🎵🎶]+');

  /// Words that mark a bracketed span as an annotation; compared lower-cased
  /// with whitespace removed.
  static const Set<String> annotationWords = {
    '音乐',
    '音樂',
    '纯音乐',
    '純音樂',
    '间奏',
    '間奏',
    '前奏',
    '尾奏',
    '掌声',
    '掌聲',
    '笑',
    '笑声',
    '笑聲',
    '欢呼',
    '歡呼',
    '鼓掌',
    '叹气',
    '嘆氣',
    '哼唱',
    '无声',
    '無聲',
    '静音',
    '靜音',
    '音效',
    '背景音乐',
    '背景音樂',
    'music',
    'instrumental',
    'applause',
    'laughter',
    'laughs',
    'cheering',
    'silence',
    'humming',
    'inaudible',
    'blankaudio',
    'noise',
    'musicplaying',
    'upbeatmusic',
    'soundeffect',
  };

  /// Fragments of captions that recognisers trained on video subtitles emit on
  /// silence or instrumental passages. Matched against a lower-cased,
  /// whitespace-free, script-folded copy of the line, so only whole-row
  /// matches with little else on the row are removed.
  static const List<String> asrBoilerplateFragments = [
    '字幕由amara.org社区提供',
    '字幕由amara.org社區提供',
    'amara.org',
    '请不吝点赞订阅转发打赏支持明镜与点点栏目',
    '請不吝點讚訂閱轉發打賞支持明鏡與點點欄目',
    '点赞订阅转发',
    '點讚訂閱轉發',
    '谢谢观看',
    '謝謝觀看',
    '感谢观看',
    '感謝觀看',
    '谢谢收看',
    '謝謝收看',
    '感谢收听',
    '感謝收聽',
    '本字幕由',
    '字幕制作',
    '字幕製作',
    '中文字幕',
    '订阅我的频道',
    '訂閱我的頻道',
    'thanksforwatching',
    'thankyouforwatching',
    'subtitlesby',
    'pleasesubscribe',
    'likeandsubscribe',
    'ご視聴ありがとうございました',
    'チャンネル登録',
  ];

  /// A boilerplate fragment must cover at least this share of the row; a long
  /// sung line that happens to contain 谢谢观看 is not removed.
  static const double boilerplateCoverage = 0.6;

  LyricTextCleanupPlan plan(
    LyricDocument document, {
    Set<LyricTextCleanupRule> rules = LyricTextCleanupRule.defaults,
    Set<int> protectedIndices = const {},
  }) {
    final changes = <LyricTextCleanupChange>[];
    final removals = <LyricTextCleanupRemoval>[];
    final skipped = <int>[];

    for (var index = 0; index < document.lines.length; index++) {
      final line = document.lines[index];
      final removalRule = _removalRule(line.text, rules);
      if (removalRule != null) {
        if (protectedIndices.contains(index)) {
          skipped.add(index);
          continue;
        }
        removals.add(
          LyricTextCleanupRemoval(
            index: index,
            lineId: line.id,
            text: line.text,
            rule: removalRule,
          ),
        );
        continue;
      }

      final applied = <LyricTextCleanupRule>[];
      final after = cleanText(line.text, rules, appliedRules: applied);
      // A row that would become empty is never blanked by a text rule; the
      // removal rules decide whether it goes.
      if (after == line.text || after.isEmpty) continue;
      if (protectedIndices.contains(index)) {
        skipped.add(index);
        continue;
      }
      changes.add(
        LyricTextCleanupChange(
          index: index,
          lineId: line.id,
          before: line.text,
          after: after,
          rules: List.unmodifiable(applied),
        ),
      );
    }

    return LyricTextCleanupPlan(
      rules: Set.unmodifiable(rules),
      changes: List.unmodifiable(changes),
      removals: List.unmodifiable(removals),
      skippedProtectedIndices: List.unmodifiable(skipped),
    );
  }

  /// Runs the enabled text rules over [text] in a fixed order. Rules that
  /// changed the text are appended to [appliedRules] when given.
  String cleanText(
    String text,
    Set<LyricTextCleanupRule> rules, {
    List<LyricTextCleanupRule>? appliedRules,
  }) {
    var current = text;
    void run(LyricTextCleanupRule rule, String Function(String) transform) {
      if (!rules.contains(rule)) return;
      var next = transform(current);
      // A rule that empties a bracket at the edge ("[音乐] 我爱你") must not
      // leave a stray space behind, but only the whitespace rule may trim
      // padding that was already in the original text.
      if (current.trim() == current) next = next.trim();
      if (next == current) return;
      current = next;
      appliedRules?.add(rule);
    }

    run(LyricTextCleanupRule.fullWidthAscii, toHalfWidthAscii);
    run(LyricTextCleanupRule.stripAnnotations, stripAnnotations);
    run(
      LyricTextCleanupRule.internalPunctuationToSpace,
      replaceInternalPunctuation,
    );
    run(LyricTextCleanupRule.trailingPunctuation, stripTrailingPunctuation);
    run(LyricTextCleanupRule.removeCjkSpaces, removeCjkSpaces);
    run(LyricTextCleanupRule.normalizeWhitespace, normalizeWhitespace);
    return current;
  }

  /// Which removal rule, if any, deletes a row with [text].
  LyricTextCleanupRule? _removalRule(
    String text,
    Set<LyricTextCleanupRule> rules,
  ) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return rules.contains(LyricTextCleanupRule.removeEmptyLines)
          ? LyricTextCleanupRule.removeEmptyLines
          : null;
    }
    if (rules.contains(LyricTextCleanupRule.removeAsrBoilerplate) &&
        isAsrBoilerplate(trimmed)) {
      return LyricTextCleanupRule.removeAsrBoilerplate;
    }
    if (rules.contains(LyricTextCleanupRule.removeAnnotationOnlyLines) &&
        isAnnotationOnly(trimmed)) {
      return LyricTextCleanupRule.removeAnnotationOnlyLines;
    }
    return null;
  }

  /// Whether [text] is, almost entirely, a known recogniser caption.
  bool isAsrBoilerplate(String text) {
    final key = _comparisonKey(text);
    if (key.isEmpty) return false;
    for (final fragment in asrBoilerplateFragments) {
      final folded = _comparisonKey(fragment);
      if (!key.contains(folded)) continue;
      if (folded.length / key.length >= boilerplateCoverage) return true;
    }
    return false;
  }

  /// Whether [text] contains nothing but annotations, music marks,
  /// punctuation and whitespace.
  bool isAnnotationOnly(String text) {
    final hadAnnotation =
        _musicMarks.hasMatch(text) || stripAnnotations(text) != text;
    if (!hadAnnotation) return false;
    final rest = stripAnnotations(text).replaceAll(_musicMarks, '');
    for (final rune in rest.runes) {
      if (_isWhitespace(rune) || _isPunctuation(rune)) continue;
      return false;
    }
    return true;
  }

  String normalizeWhitespace(String text) =>
      text.replaceAll('\u3000', ' ').replaceAll(_whitespaceRun, ' ').trim();

  String toHalfWidthAscii(String text) {
    final output = StringBuffer();
    var changed = false;
    for (final rune in text.runes) {
      // U+FF01..U+FF5E mirror ASCII 0x21..0x7E. Full-width CJK punctuation
      // with its own meaning (，。) lives elsewhere and is untouched; the
      // full-width comma, colon and semicolon in this block are kept too so
      // the punctuation rules still see them as CJK punctuation.
      if (rune >= 0xff01 && rune <= 0xff5e && !_keepsFullWidth(rune)) {
        output.writeCharCode(rune - 0xfee0);
        changed = true;
      } else {
        output.writeCharCode(rune);
      }
    }
    return changed ? output.toString() : text;
  }

  String stripAnnotations(String text) {
    var result = text.replaceAllMapped(_bracketedSpan, (match) {
      final inner = match.group(1)!;
      final key = inner.toLowerCase().replaceAll(_whitespaceRun, '');
      return annotationWords.contains(key) ? ' ' : match.group(0)!;
    });
    result = result.replaceAll(_musicMarks, ' ');
    return result == text ? text : result.replaceAll(_whitespaceRun, ' ');
  }

  /// Full-width sentence punctuation inside a line always becomes a space;
  /// ASCII punctuation only when it sits next to CJK text, so "I love you,
  /// baby" keeps its comma while "我爱你,你爱我" loses it.
  String replaceInternalPunctuation(String text) {
    final runes = text.runes.toList();
    var end = runes.length;
    while (end > 0 &&
        (_isSentencePunctuation(runes[end - 1]) ||
            _isWhitespace(runes[end - 1]))) {
      end--;
    }
    var start = 0;
    while (start < end &&
        (_isSentencePunctuation(runes[start]) || _isWhitespace(runes[start]))) {
      start++;
    }
    final output = StringBuffer();
    var changed = false;
    var pendingSpace = false;
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      final inside = i >= start && i < end;
      if (inside && _isSentencePunctuation(rune) && _replacesInside(runes, i)) {
        changed = true;
        pendingSpace = true;
        continue;
      }
      if (pendingSpace) {
        if (_isWhitespace(rune)) continue;
        // Strip spaces already written before the punctuation mark.
        final written = output.toString().trimRight();
        output
          ..clear()
          ..write(written)
          ..write(' ');
        pendingSpace = false;
      }
      output.writeCharCode(rune);
    }
    return changed ? output.toString() : text;
  }

  String stripTrailingPunctuation(String text) {
    final runes = text.runes.toList();
    var end = runes.length;
    var removed = false;
    while (end > 0) {
      final rune = runes[end - 1];
      if (_isWhitespace(rune)) {
        end--;
        continue;
      }
      if (_isSentencePunctuation(rune)) {
        end--;
        removed = true;
        continue;
      }
      break;
    }
    if (!removed) return text;
    return String.fromCharCodes(runes.sublist(0, end));
  }

  String removeCjkSpaces(String text) {
    final runes = text.runes.toList();
    final output = StringBuffer();
    var changed = false;
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      if (_isWhitespace(rune)) {
        var j = i;
        while (j < runes.length && _isWhitespace(runes[j])) {
          j++;
        }
        final before = i > 0 ? runes[i - 1] : null;
        final after = j < runes.length ? runes[j] : null;
        if (before != null &&
            after != null &&
            _isSpacelessScript(before) &&
            _isSpacelessScript(after)) {
          changed = true;
          i = j - 1;
          continue;
        }
      }
      output.writeCharCode(rune);
    }
    return changed ? output.toString() : text;
  }

  static const ChineseScriptConverter _converter = ChineseScriptConverter();

  static final RegExp _keyNoise = RegExp(
    r'[，。、；：！？,;:!?「」『』“”"' "'" r'～~\-—…·]',
  );

  static String _comparisonKey(String text) => _converter
      .foldForComparison(text.toLowerCase())
      .replaceAll(_whitespaceRun, '')
      .replaceAll(_keyNoise, '');

  static bool _keepsFullWidth(int rune) =>
      rune == 0xff0c || // ，
      rune == 0xff1a || // ：
      rune == 0xff1b || // ；
      rune == 0xff01 || // ！
      rune == 0xff1f || // ？
      rune == 0xff08 || // （
      rune == 0xff09; //   ）

  static bool _isSentencePunctuation(int rune) =>
      sentencePunctuation.runes.contains(rune);

  /// Whether the punctuation mark at [index] is replaced by a space.
  static bool _replacesInside(List<int> runes, int index) {
    final rune = runes[index];
    if (rune >= 0x80) return true;
    // The period in 3.5 or the comma in 1,000 is not sentence punctuation.
    if (index > 0 &&
        index < runes.length - 1 &&
        _isAsciiDigit(runes[index - 1]) &&
        _isAsciiDigit(runes[index + 1])) {
      return false;
    }
    return _nearestIsCjk(runes, index, -1) || _nearestIsCjk(runes, index, 1);
  }

  static bool _nearestIsCjk(List<int> runes, int index, int step) {
    for (var i = index + step; i >= 0 && i < runes.length; i += step) {
      if (_isWhitespace(runes[i])) continue;
      return _isSpacelessScript(runes[i]) || _isHangul(runes[i]);
    }
    return false;
  }

  static bool _isHangul(int rune) =>
      (rune >= 0xac00 && rune <= 0xd7af) || (rune >= 0x1100 && rune <= 0x11ff);

  static bool _isAsciiDigit(int rune) => rune >= 0x30 && rune <= 0x39;

  static bool _isWhitespace(int rune) =>
      rune == 0x20 ||
      rune == 0x09 ||
      rune == 0x0a ||
      rune == 0x0d ||
      rune == 0xa0 ||
      rune == 0x3000;

  static bool _isPunctuation(int rune) {
    if (rune < 0x80) {
      return !((rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5a) ||
          (rune >= 0x61 && rune <= 0x7a));
    }
    return (rune >= 0x3000 && rune <= 0x303f) ||
        (rune >= 0xff00 && rune <= 0xff0f) ||
        (rune >= 0xff1a && rune <= 0xff20) ||
        (rune >= 0x2010 && rune <= 0x205e);
  }

  /// Han characters and Japanese kana; Hangul is excluded on purpose.
  static bool _isSpacelessScript(int rune) {
    if (ChineseScriptConverter.isHanRune(rune)) return true;
    return (rune >= 0x3040 && rune <= 0x30ff) || (rune >= 0x31f0 && rune <= 0x31ff);
  }
}
