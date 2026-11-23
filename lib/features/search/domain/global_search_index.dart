import 'global_search_item.dart';

/// Lower-cases [text], turns full-width letters, digits and spaces into
/// their ASCII forms and collapses runs of white space, so "ＡＢＣ  Song"
/// and "abc song" read the same.
String normalizeSearchText(String text) {
  final buffer = StringBuffer();
  var space = false;
  for (final rune in text.runes) {
    var code = rune;
    if (code == 0x3000) code = 0x20;
    if (code >= 0xFF01 && code <= 0xFF5E) code -= 0xFEE0;
    final isSpace = code == 0x20 || code == 0x09 || code == 0x0A;
    if (isSpace) {
      space = buffer.isNotEmpty;
      continue;
    }
    if (space) buffer.write(' ');
    space = false;
    buffer.writeCharCode(code);
  }
  return buffer.toString().toLowerCase();
}

/// Where [query] first appears in [text], ignoring case and full-width
/// forms, as a start and an end into [text]; null when it does not.
///
/// For highlighting the matched part of a title. Only exact runs are found;
/// a query whose words appear apart highlights nothing.
({int start, int end})? findSearchMatch(String text, String query) {
  final needle = normalizeSearchText(query);
  if (needle.isEmpty) return null;
  // Normalising keeps one character per character except for collapsed
  // white space, so compare against a same-length folded copy instead.
  final folded = String.fromCharCodes(
    text.runes.map((rune) {
      var code = rune;
      if (code == 0x3000) code = 0x20;
      if (code >= 0xFF01 && code <= 0xFF5E) code -= 0xFEE0;
      return code;
    }),
  ).toLowerCase();
  if (folded.length != text.length) return null;
  final start = folded.indexOf(needle);
  return start < 0 ? null : (start: start, end: start + needle.length);
}

/// The searchable items, normalised once, ranked per query (D-065).
///
/// Every word of the query has to appear somewhere in the item. Titles count
/// most: the whole title, then a title that starts with the query, a title
/// containing it, a title containing every word, and last the subtitle and
/// keywords. A project whose name does not match but whose lyrics contain
/// the query is listed under 歌词里提到 with the line.
class GlobalSearchIndex {
  GlobalSearchIndex(List<GlobalSearchItem> items)
    : _entries = [
        for (var i = 0; i < items.length; i++) _IndexedItem(items[i], i),
      ];

  final List<_IndexedItem> _entries;

  int get length => _entries.length;

  /// What the empty search shows: the pages and actions, then the first
  /// [recentProjects] projects (the source lists the newest first).
  GlobalSearchResults browse({int recentProjects = 5}) {
    final actions = [
      for (final entry in _entries)
        if (entry.item.kind == GlobalSearchKind.action)
          GlobalSearchHit(
            item: entry.item,
            kind: GlobalSearchKind.action,
            score: 0,
          ),
    ];
    final projects = [
      for (final entry in _entries)
        if (entry.item.kind == GlobalSearchKind.project)
          GlobalSearchHit(
            item: entry.item,
            kind: GlobalSearchKind.project,
            score: 0,
          ),
    ].take(recentProjects).toList(growable: false);
    return GlobalSearchResults([
      if (actions.isNotEmpty)
        GlobalSearchGroup(kind: GlobalSearchKind.action, hits: actions),
      if (projects.isNotEmpty)
        GlobalSearchGroup(kind: GlobalSearchKind.project, hits: projects),
    ]);
  }

  /// The results for [query], or [browse] when it is blank.
  GlobalSearchResults search(String query) {
    final needle = normalizeSearchText(query);
    if (needle.isEmpty) return browse();
    final words = needle.split(' ');

    final scored = <({GlobalSearchHit hit, int length, int order})>[];
    for (final entry in _entries) {
      final hit = entry.match(needle, words);
      if (hit == null) continue;
      scored.add((hit: hit, length: entry.title.length, order: entry.order));
    }
    scored.sort((a, b) {
      final score = b.hit.score.compareTo(a.hit.score);
      if (score != 0) return score;
      final length = a.length.compareTo(b.length);
      return length != 0 ? length : a.order.compareTo(b.order);
    });

    final byKind = <GlobalSearchKind, List<GlobalSearchHit>>{};
    for (final value in scored) {
      byKind.putIfAbsent(value.hit.kind, () => []).add(value.hit);
    }
    final groups = [
      for (final MapEntry(key: kind, value: hits) in byKind.entries)
        GlobalSearchGroup(
          kind: kind,
          hits: hits.take(kind.limit).toList(growable: false),
          hidden: hits.length > kind.limit ? hits.length - kind.limit : 0,
        ),
    ];
    // The group with the best match first; on a tie, the fixed kind order.
    groups.sort((a, b) {
      final score = b.hits.first.score.compareTo(a.hits.first.score);
      return score != 0 ? score : a.kind.index.compareTo(b.kind.index);
    });
    return GlobalSearchResults(groups);
  }
}

class _IndexedItem {
  _IndexedItem(this.item, this.order)
    : title = normalizeSearchText(item.title),
      rest = [
        normalizeSearchText(item.subtitle ?? ''),
        for (final keyword in item.keywords) normalizeSearchText(keyword),
      ].join('\n'),
      keywords = [
        for (final keyword in item.keywords) normalizeSearchText(keyword),
      ],
      lines = [for (final line in item.lyricLines) normalizeSearchText(line)];

  final GlobalSearchItem item;
  final int order;
  final String title;
  final String rest;
  final List<String> keywords;
  final List<String> lines;

  static const exact = 1000;
  static const prefix = 800;
  static const wordStart = 700;
  static const contains = 600;
  static const allWords = 500;
  static const keyword = 450;
  static const elsewhere = 300;
  static const lyric = 200;

  GlobalSearchHit? match(String needle, List<String> words) {
    final score = _score(needle, words);
    if (score != null) {
      return GlobalSearchHit(item: item, kind: item.kind, score: score);
    }
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (words.every(line.contains)) {
        return GlobalSearchHit(
          item: item,
          kind: GlobalSearchKind.lyric,
          score: lyric,
          lyricLine: item.lyricLines[i].trim(),
        );
      }
    }
    return null;
  }

  int? _score(String needle, List<String> words) {
    if (title == needle) return exact;
    if (title.startsWith(needle)) return prefix;
    final at = title.indexOf(needle);
    if (at > 0) {
      final before = title.codeUnitAt(at - 1);
      final boundary =
          before == 0x20 || before == 0x2D || before == 0x28 || before == 0x5F;
      return boundary ? wordStart : contains;
    }
    if (words.every(title.contains)) return allWords;
    if (keywords.any((value) => value == needle || value.startsWith(needle))) {
      return keyword;
    }
    final everything = '$title\n$rest';
    if (words.every(everything.contains)) return elsewhere;
    return null;
  }
}
