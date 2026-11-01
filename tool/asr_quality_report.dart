// Line-level lyric quality baseline for LyricForge transcription output.
//
// `tool/asr_transcript_eval.dart` scores whole-text character/token error rates
// and explicitly does not evaluate timestamps or line segmentation. The
// perceived recognition regression lives in exactly that gap: duplicated lyric
// lines produced by the dual-engine fusion step, broken sentence boundaries,
// and drifting timestamps. This tool measures those.
//
// Usage:
//   dart run tool/asr_quality_report.dart --corpus corpus/corpus.json \
//       [--output report.json] [--baseline previous.json] [--fail-on-regression]
//   dart run tool/asr_quality_report.dart --reference ref.lrc \
//       --hypothesis fused.lrc [--engine fused] [--output report.json]
//
// A reference is the manually checked ground truth. A hypothesis is one
// recognizer's output (whisper, qwen, or the fused document). Both accept:
//   *.lrc   LRC timestamps (plain text also accepted)
//   *.json  LyricDocument JSON, a line array, or a projects.json export
//   *.txt   one lyric line per line, no timestamps
//
// The report is deterministic: it contains no generation timestamp, so two
// reports can be diffed to prove that a pipeline change helped or hurt.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart';

/// Bumped when a metric definition or report key changes incompatibly.
const int kQualityReportSchemaVersion = 1;

const int _maxSongs = 200;
const int _maxLinesPerDocument = 300;
const int _maxMatchCells = 400000;
const int _maxCharacterEditCells = 16000000;
const int _maxReportedDuplicateGroups = 40;
const int _maxReportedLinesPerSide = 20;

/// Default text similarity required before two lines count as the same lyric.
const double kDefaultMatchThreshold = 0.6;

/// Two lines at least this similar are treated as the same text when deciding
/// whether one of them duplicates the other.
const double _duplicateSimilarityThreshold = 0.85;

/// A shorter line contained in a longer one at this ratio is a duplicate when
/// their positions collide. This is the signature of the fusion defect: one
/// word of a lyric line emitted as its own row.
const double _containmentThreshold = 0.9;

/// Duplicate candidates must be this close in time; a chorus that repeats a
/// minute later is legitimate and must not be counted.
const int _duplicateWindowMs = 1500;

/// Shortest text that can count as a duplicate. Two-character CJK words such as
/// "跳舞" are exactly the fragments the fusion step duplicates, while a single
/// character is usually an ad-lib and too weak to judge.
const int _minDuplicateTextLength = 2;

/// Matched pairs closer than this in start time count toward `within500msRate`.
const int _timestampToleranceMs = 500;

final RegExp _lrcTimestamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
final RegExp _lrcMetadata = RegExp(r'^\[[a-zA-Z][^\]]*:.*\]$');

/// A timestamp that starts a line, which is what separates LRC from JSON that
/// also begins with `[`.
final RegExp _lrcTimestampAtLineStart = RegExp(r'(?m)^[ \t]*\[\d{1,3}:\d{2}');

const LyricTokenizer _tokenizer = LyricTokenizer();

/// One lyric line with optional millisecond boundaries.
class QualityLine {
  const QualityLine({required this.text, this.startMs, this.endMs});

  final String text;
  final int? startMs;
  final int? endMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'startMs': startMs,
    'endMs': endMs,
  };

  @override
  String toString() => 'QualityLine($startMs…$endMs: $text)';
}

// ---------------------------------------------------------------------------
// Text normalization
// ---------------------------------------------------------------------------

List<String> _tokens(String text) => _tokenizer.tokenize(text);

/// Case-, punctuation- and whitespace-insensitive characters used for CER.
List<int> _characters(String text) => _tokens(text).join().runes.toList();

/// Space-free normalized form used for containment checks.
String _squashed(String text) => _tokens(text).join();

/// Length of the longest common substring of [a] and [b].
int _longestCommonSubstring(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var previous = List<int>.filled(b.length + 1, 0);
  var current = List<int>.filled(b.length + 1, 0);
  var best = 0;
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      current[j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
          ? previous[j - 1] + 1
          : 0;
      if (current[j] > best) best = current[j];
    }
    final swap = previous;
    previous = current;
    current = swap;
    current[0] = 0;
  }
  return best;
}

/// Share of the shorter text that appears inside the longer text.
double _containment(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  return _longestCommonSubstring(shorter, longer) / shorter.length;
}

int _editDistance<T>(
  List<T> reference,
  List<T> candidate, {
  required String context,
  int maxCells = _maxMatchCells,
}) {
  final width = candidate.length + 1;
  final height = reference.length + 1;
  if (height * width > maxCells) {
    throw FormatException(
      context + ' exceeds the edit-distance limit; split the document.',
    );
  }
  var previous = List<int>.generate(width, (index) => index);
  var current = List<int>.filled(width, 0);
  for (var i = 1; i < height; i++) {
    current[0] = i;
    for (var j = 1; j < width; j++) {
      final substitution =
          previous[j - 1] + (reference[i - 1] == candidate[j - 1] ? 0 : 1);
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      current[j] = math.min(substitution, math.min(deletion, insertion));
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[width - 1];
}

/// Share of tokens the two lines have in common, used as a cheap prefilter.
double _tokenOverlap(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  final pool = longer.toSet();
  var hits = 0;
  for (final token in shorter) {
    if (pool.contains(token)) hits++;
  }
  return hits / shorter.length;
}

double _similarity(
  List<int> referenceCharacters,
  List<int> candidateCharacters,
  String context,
) {
  final longest = math.max(
    referenceCharacters.length,
    candidateCharacters.length,
  );
  if (longest == 0) return 1;
  final distance = _editDistance<int>(
    referenceCharacters,
    candidateCharacters,
    context: context,
  );
  return 1 - distance / longest;
}

// ---------------------------------------------------------------------------
// Line matching
// ---------------------------------------------------------------------------

class LineMatch {
  const LineMatch({
    required this.referenceIndex,
    required this.hypothesisIndex,
    required this.similarity,
  });

  final int referenceIndex;
  final int hypothesisIndex;
  final double similarity;
}

class MatchOutcome {
  const MatchOutcome({
    required this.matches,
    required this.unmatchedReferenceIndexes,
    required this.unmatchedHypothesisIndexes,
  });

  final List<LineMatch> matches;
  final List<int> unmatchedReferenceIndexes;
  final List<int> unmatchedHypothesisIndexes;
}

/// Aligns reference and hypothesis lines monotonically, maximizing the summed
/// text similarity of pairs that clear [threshold].
///
/// Monotonic alignment keeps a repeated chorus from matching backwards and
/// stops one long line from absorbing several short ones.
MatchOutcome matchLyricLines(
  List<QualityLine> reference,
  List<QualityLine> hypothesis, {
  double threshold = kDefaultMatchThreshold,
}) {
  final referenceCount = reference.length;
  final hypothesisCount = hypothesis.length;
  if (referenceCount > _maxLinesPerDocument ||
      hypothesisCount > _maxLinesPerDocument) {
    throw FormatException(
      'Documents longer than $_maxLinesPerDocument lines must be split first.',
    );
  }
  final cells = (referenceCount + 1) * (hypothesisCount + 1);
  if (cells > _maxMatchCells) {
    throw const FormatException('Document pair is too large to align.');
  }

  final referenceTokens = [for (final line in reference) _tokens(line.text)];
  final referenceCharacters = [
    for (final line in reference) _characters(line.text),
  ];
  final hypothesisTokens = [for (final line in hypothesis) _tokens(line.text)];
  final hypothesisCharacters = [
    for (final line in hypothesis) _characters(line.text),
  ];

  // Exact edit distance is only computed for pairs that can still reach the
  // threshold, then cached because the backtrace asks again.
  final similarityCache = <int, double>{};
  double pairSimilarity(int i, int j) {
    final key = i * hypothesisCount + j;
    final cached = similarityCache[key];
    if (cached != null) return cached;
    var value = 0.0;
    if (_tokenOverlap(referenceTokens[i], hypothesisTokens[j]) >= 0.35) {
      value = _similarity(
        referenceCharacters[i],
        hypothesisCharacters[j],
        'Line ${i + 1}/${j + 1}',
      );
    }
    similarityCache[key] = value;
    return value;
  }

  final width = hypothesisCount + 1;
  final directions = Uint8List(cells);
  var previous = List<double>.filled(width, 0);
  var current = List<double>.filled(width, 0);
  for (var i = 1; i <= referenceCount; i++) {
    current[0] = 0;
    for (var j = 1; j <= hypothesisCount; j++) {
      var best = previous[j];
      var direction = 1; // reference line unmatched
      if (current[j - 1] > best) {
        best = current[j - 1];
        direction = 2; // hypothesis line unmatched
      }
      final similarity = pairSimilarity(i - 1, j - 1);
      if (similarity >= threshold) {
        final paired = previous[j - 1] + similarity;
        if (paired > best) {
          best = paired;
          direction = 3; // matched pair
        }
      }
      current[j] = best;
      directions[i * width + j] = direction;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }

  final matches = <LineMatch>[];
  final unmatchedReference = <int>[];
  final unmatchedHypothesis = <int>[];
  var i = referenceCount;
  var j = hypothesisCount;
  while (i > 0 || j > 0) {
    final direction = i == 0 ? 2 : (j == 0 ? 1 : directions[i * width + j]);
    if (direction == 3) {
      matches.add(
        LineMatch(
          referenceIndex: i - 1,
          hypothesisIndex: j - 1,
          similarity: pairSimilarity(i - 1, j - 1),
        ),
      );
      i--;
      j--;
    } else if (direction == 1) {
      unmatchedReference.add(i - 1);
      i--;
    } else {
      unmatchedHypothesis.add(j - 1);
      j--;
    }
  }
  matches.sort((a, b) => a.referenceIndex.compareTo(b.referenceIndex));
  return MatchOutcome(
    matches: matches,
    unmatchedReferenceIndexes: unmatchedReference.reversed.toList(),
    unmatchedHypothesisIndexes: unmatchedHypothesis.reversed.toList(),
  );
}

// ---------------------------------------------------------------------------
// Duplicate detection
// ---------------------------------------------------------------------------

class DuplicateGroup {
  const DuplicateGroup({
    required this.text,
    required this.lineIndexes,
    required this.kind,
    this.startMs,
  });

  final String text;
  final List<int> lineIndexes;

  /// `contained` when a shorter line sits inside another one, `repeated` when
  /// the same text appears twice at the same position.
  final String kind;
  final int? startMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'lineIndexes': lineIndexes,
    'kind': kind,
    'startMs': startMs,
  };
}

/// Finds lines that restate lyrics already present at the same moment.
///
/// Timestamps are what separate a defect from a chorus: only lines within
/// [_duplicateWindowMs] of each other are candidates. When timestamps are
/// missing, only immediately adjacent lines are compared, because a chorus
/// repeat is far away in the document while a fusion duplicate sits next to
/// its parent line.
List<DuplicateGroup> findDuplicateLyricLines(List<QualityLine> lines) {
  final groups = <DuplicateGroup>[];
  final squashed = [for (final line in lines) _squashed(line.text)];
  final timed = lines.every((line) => line.startMs != null);

  bool nearby(int a, int b) {
    if (!timed) return b - a <= 1;
    return (lines[a].startMs! - lines[b].startMs!).abs() <= _duplicateWindowMs;
  }

  for (var i = 0; i < lines.length; i++) {
    if (squashed[i].length < _minDuplicateTextLength) continue;
    final members = <int>[i];
    var kind = 'repeated';
    for (var j = i + 1; j < lines.length; j++) {
      if (squashed[j].length < _minDuplicateTextLength) continue;
      if (!nearby(i, j)) continue;
      final shorter = squashed[i].length <= squashed[j].length
          ? squashed[i]
          : squashed[j];
      final longer = squashed[i].length <= squashed[j].length
          ? squashed[j]
          : squashed[i];
      if (shorter == longer) {
        members.add(j);
        continue;
      }
      final contained = _containment(shorter, longer) >= _containmentThreshold;
      final nearIdentical =
          _similarity(
            _characters(lines[i].text),
            _characters(lines[j].text),
            'Duplicate check $i/$j',
          ) >=
          _duplicateSimilarityThreshold;
      if (!contained && !nearIdentical) continue;
      members.add(j);
      kind = 'contained';
    }
    if (members.length > 1) {
      // Label the group with the longest text so the readable parent line wins.
      var labelIndex = members.first;
      for (final index in members) {
        if (lines[index].text.length > lines[labelIndex].text.length) {
          labelIndex = index;
        }
      }
      groups.add(
        DuplicateGroup(
          text: lines[labelIndex].text.trim(),
          lineIndexes: members,
          kind: kind,
          startMs: timed ? lines[labelIndex].startMs : null,
        ),
      );
    }
  }
  return groups;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

int _fractionToMilliseconds(String? fraction) {
  if (fraction == null || fraction.isEmpty) return 0;
  if (fraction.length == 1) return int.parse(fraction) * 100;
  if (fraction.length == 2) return int.parse(fraction) * 10;
  return int.parse(fraction.padRight(3, '0').substring(0, 3));
}

/// Parses LRC text. A line may carry several timestamps; each becomes its own
/// entry, matching how players expand a repeated chorus timestamp.
List<QualityLine> parseLrcLyrics(String content) {
  final lines = <QualityLine>[];
  for (final rawLine in const LineSplitter().convert(content)) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;
    if (_lrcMetadata.hasMatch(trimmed) && !_lrcTimestamp.hasMatch(trimmed)) {
      continue;
    }
    final stamps = <int>[];
    var cursor = 0;
    while (cursor < trimmed.length) {
      final match = _lrcTimestamp.matchAsPrefix(trimmed, cursor);
      if (match == null) break;
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final millis = _fractionToMilliseconds(match.group(3));
      stamps.add(minutes * 60000 + seconds * 1000 + millis);
      cursor = match.end;
    }
    if (stamps.isEmpty) continue;
    final text = trimmed.substring(cursor).trim();
    for (final stamp in stamps) {
      lines.add(QualityLine(text: text, startMs: stamp));
    }
  }
  return lines;
}

/// Accepts one lyric line per file line, ignoring blank lines.
List<QualityLine> parsePlainLyrics(String content) => <QualityLine>[
  for (final rawLine in const LineSplitter().convert(content))
    if (rawLine.trim().isNotEmpty) QualityLine(text: rawLine.trim()),
];

int? _optionalMilliseconds(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.round();
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.round();
  }
  return null;
}

List<QualityLine> _parseLineArray(List<dynamic> raw, String label) {
  final lines = <QualityLine>[];
  for (final element in raw) {
    if (element is! Map) {
      throw FormatException('$label contains a non-object lyric line.');
    }
    final map = element.cast<String, dynamic>();
    final text = map['text'] ?? map['lyric'] ?? map['content'];
    if (text is! String) {
      throw FormatException('$label has a lyric line without text.');
    }
    lines.add(
      QualityLine(
        text: text,
        startMs:
            _optionalMilliseconds(map['startMs']) ??
            _optionalMilliseconds(map['startTime']),
        endMs:
            _optionalMilliseconds(map['endMs']) ??
            _optionalMilliseconds(map['endTime']),
      ),
    );
  }
  return lines;
}

List<dynamic>? _linesFromProjects(List<dynamic> projects, String label) {
  final documents = <List<dynamic>>[];
  for (final element in projects) {
    if (element is Map && element['lyricDocument'] is Map) {
      final document = (element['lyricDocument'] as Map)
          .cast<String, dynamic>();
      final lines = document['lines'];
      if (lines is List) documents.add(lines);
    }
  }
  if (documents.isEmpty) return null;
  if (documents.length > 1) {
    throw FormatException(
      '$label contains ${documents.length} lyric documents; export one project.',
    );
  }
  return documents.first;
}

/// Parses LyricDocument JSON, a bare line array, or a projects.json export.
List<QualityLine> parseLyricJsonContent(String content, String label) {
  final decoded = jsonDecode(content);
  List<dynamic>? lineArray;
  if (decoded is List) {
    final first = decoded.isEmpty ? null : decoded.first;
    if (first is Map && !first.containsKey('text')) {
      lineArray = _linesFromProjects(decoded, label);
      if (lineArray == null) {
        throw FormatException('$label contains no lyricDocument entries.');
      }
    } else {
      lineArray = decoded;
    }
  } else if (decoded is Map) {
    final map = decoded.cast<String, dynamic>();
    if (map['lyricDocument'] is Map) {
      final document = (map['lyricDocument'] as Map).cast<String, dynamic>();
      final lines = document['lines'];
      if (lines is! List) {
        throw FormatException('$label lyricDocument has no lines array.');
      }
      lineArray = lines;
    } else if (map['lines'] is List) {
      lineArray = map['lines'] as List;
    }
  }
  if (lineArray == null) {
    throw FormatException('$label JSON is not a lyric document.');
  }
  return _parseLineArray(lineArray, label);
}

/// Detects the format of [content] and parses it.
///
/// An LRC file may open with a metadata tag such as `[ti:...]`, which also
/// starts with `[`, so LRC detection has to look at line starts before the
/// JSON branch treats the file as an array.
List<QualityLine> parseLyricSource(String content, String label) {
  final trimmed = content.trimLeft();
  if (trimmed.isEmpty) {
    throw FormatException('$label is empty.');
  }
  if (_lrcTimestampAtLineStart.hasMatch(content)) {
    return parseLrcLyrics(content);
  }
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return parseLyricJsonContent(content, label);
  }
  return parsePlainLyrics(content);
}

/// Parses one reference/candidate entry: `path`, `text`, or inline `lines`.
List<QualityLine> _parseCorpusEntry(
  Map<String, dynamic> entry,
  String label,
  String? baseDirectory,
) {
  final inlineLines = entry['lines'];
  if (inlineLines is List) return _parseLineArray(inlineLines, label);
  final text = entry['text'];
  if (text is String) return parseLyricSource(text, label);
  final path = entry['path'];
  if (path is String && path.trim().isNotEmpty) {
    final resolved = baseDirectory == null || File(path).isAbsolute
        ? path
        : '$baseDirectory${Platform.pathSeparator}$path';
    final file = File(resolved);
    if (!file.existsSync()) {
      throw FileSystemException('Lyric source not found.', resolved);
    }
    return parseLyricSource(file.readAsStringSync(), label);
  }
  throw FormatException('$label needs a path, text, or lines entry.');
}

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

double? _rate(num? numerator, num? denominator) {
  if (numerator == null || denominator == null || denominator == 0) return null;
  return numerator / denominator;
}

double? _mean(List<int> values) {
  if (values.isEmpty) return null;
  var total = 0;
  for (final value in values) {
    total += value;
  }
  return total / values.length;
}

double? _median(List<int> values) {
  if (values.isEmpty) return null;
  final sorted = List<int>.from(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle].toDouble();
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

/// Nearest-rank percentile: p95 of four samples is the largest one.
double? _percentile(List<int> values, double percentile) {
  if (values.isEmpty) return null;
  final sorted = List<int>.from(values)..sort();
  final rank = (percentile * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1].toDouble();
}

double? _f1(double? recall, double? precision) {
  if (recall == null || precision == null || recall + precision == 0) {
    return null;
  }
  return 2 * recall * precision / (recall + precision);
}

/// Scores one hypothesis document against one reference document.
Map<String, Object?> evaluateLyricQualityPair({
  required String songId,
  required String engine,
  required List<QualityLine> reference,
  required List<QualityLine> hypothesis,
  String? language,
  double matchThreshold = kDefaultMatchThreshold,
}) {
  if (reference.isEmpty) {
    throw FormatException('Reference for $songId has no lyric lines.');
  }
  if (hypothesis.isEmpty) {
    throw FormatException(
      'Hypothesis for $songId ($engine) has no lyric lines.',
    );
  }
  final outcome = matchLyricLines(
    reference,
    hypothesis,
    threshold: matchThreshold,
  );
  final duplicates = findDuplicateLyricLines(hypothesis);
  final duplicateLineCount = duplicates.fold<int>(
    0,
    (sum, group) => sum + group.lineIndexes.length - 1,
  );
  final duplicateLineIndexes = <int>{
    for (final group in duplicates)
      for (final index in group.lineIndexes.skip(1)) index,
  }.toList()..sort();

  final referenceCharacters = _characters(
    reference.map((line) => line.text).join(' '),
  );
  final hypothesisCharacters = _characters(
    hypothesis.map((line) => line.text).join(' '),
  );
  final characterEdits = _editDistance<int>(
    referenceCharacters,
    hypothesisCharacters,
    context: 'Song $songId / $engine character comparison',
    maxCells: _maxCharacterEditCells,
  );

  final startDeltas = <int>[];
  final endDeltas = <int>[];
  for (final match in outcome.matches) {
    final referenceLine = reference[match.referenceIndex];
    final hypothesisLine = hypothesis[match.hypothesisIndex];
    if (referenceLine.startMs != null && hypothesisLine.startMs != null) {
      startDeltas.add((referenceLine.startMs! - hypothesisLine.startMs!).abs());
    }
    if (referenceLine.endMs != null && hypothesisLine.endMs != null) {
      endDeltas.add((referenceLine.endMs! - hypothesisLine.endMs!).abs());
    }
  }

  final matchedCount = outcome.matches.length;
  final referenceLineCount = reference.length;
  final hypothesisLineCount = hypothesis.length;
  final recall = _rate(matchedCount, referenceLineCount);
  final precision = _rate(matchedCount, hypothesisLineCount);

  return <String, Object?>{
    'songId': songId,
    'engine': engine,
    'language': language,
    'matchThreshold': matchThreshold,
    'referenceLineCount': referenceLineCount,
    'hypothesisLineCount': hypothesisLineCount,
    'lineCountRatio': _rate(hypothesisLineCount, referenceLineCount),
    'matchedLineCount': matchedCount,
    'lineRecall': recall,
    'linePrecision': precision,
    'lineF1': _f1(recall, precision),
    'missingLineCount': outcome.unmatchedReferenceIndexes.length,
    'extraLineCount': outcome.unmatchedHypothesisIndexes.length,
    'referenceCharacterCount': referenceCharacters.length,
    'hypothesisCharacterCount': hypothesisCharacters.length,
    'characterEditCount': characterEdits,
    'normalizedCharacterErrorRate': _rate(
      characterEdits,
      referenceCharacters.length,
    ),
    'duplicateLineCount': duplicateLineCount,
    'duplicateLineRate': _rate(duplicateLineCount, hypothesisLineCount),
    'duplicateLineIndexes': duplicateLineIndexes,
    'duplicateGroups': <Object?>[
      for (final group in duplicates.take(_maxReportedDuplicateGroups))
        group.toJson(),
    ],
    'timedMatchCount': startDeltas.length,
    'startTimeMaeMs': _mean(startDeltas),
    'startTimeMedianMs': _median(startDeltas),
    'startTimeP95Ms': _percentile(startDeltas, 0.95),
    'endTimeMaeMs': _mean(endDeltas),
    'within500msRate': _rate(
      startDeltas.where((delta) => delta <= _timestampToleranceMs).length,
      startDeltas.length,
    ),
    'missingReferenceLines': <Object?>[
      for (final index in outcome.unmatchedReferenceIndexes.take(
        _maxReportedLinesPerSide,
      ))
        <String, Object?>{
          'index': index,
          'text': reference[index].text,
          'startMs': reference[index].startMs,
        },
    ],
    'extraHypothesisLines': <Object?>[
      for (final index in outcome.unmatchedHypothesisIndexes.take(
        _maxReportedLinesPerSide,
      ))
        <String, Object?>{
          'index': index,
          'text': hypothesis[index].text,
          'startMs': hypothesis[index].startMs,
        },
    ],
  };
}

Map<String, dynamic> _asMap(Object? value, String context) {
  if (value is! Map) throw FormatException('$context must be an object.');
  return value.cast<String, dynamic>();
}

List<dynamic> _asList(Object? value, String context) {
  if (value is! List) throw FormatException('$context must be an array.');
  return value;
}

double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

/// Aggregates per-song scores.
///
/// Rates are micro-averaged (totals, not averages of averages) so a long song
/// is not outvoted by a short one. Timing metrics are weighted by the number of
/// matched pairs, which is exact for a mean and for a tolerance rate; medians
/// and p95 remain per-song because they cannot be recombined from summaries.
Map<String, Object?> _summarizeEngine(List<Map<String, Object?>> scores) {
  var referenceLineCount = 0;
  var hypothesisLineCount = 0;
  var matchedLineCount = 0;
  var referenceCharacterCount = 0;
  var characterEditCount = 0;
  var duplicateLineCount = 0;
  var timedPairs = 0;
  var weightedStartError = 0.0;
  var weightedWithinTolerance = 0.0;

  for (final score in scores) {
    referenceLineCount += score['referenceLineCount']! as int;
    hypothesisLineCount += score['hypothesisLineCount']! as int;
    matchedLineCount += score['matchedLineCount']! as int;
    referenceCharacterCount += score['referenceCharacterCount']! as int;
    characterEditCount += score['characterEditCount']! as int;
    duplicateLineCount += score['duplicateLineCount']! as int;
    final pairs = score['timedMatchCount']! as int;
    final mae = _asDouble(score['startTimeMaeMs']);
    final within = _asDouble(score['within500msRate']);
    if (pairs > 0 && mae != null) {
      weightedStartError += mae * pairs;
      timedPairs += pairs;
      if (within != null) weightedWithinTolerance += within * pairs;
    }
  }

  final recall = _rate(matchedLineCount, referenceLineCount);
  final precision = _rate(matchedLineCount, hypothesisLineCount);
  return <String, Object?>{
    'songCount': scores.length,
    'referenceLineCount': referenceLineCount,
    'hypothesisLineCount': hypothesisLineCount,
    'lineCountRatio': _rate(hypothesisLineCount, referenceLineCount),
    'matchedLineCount': matchedLineCount,
    'lineRecall': recall,
    'linePrecision': precision,
    'lineF1': _f1(recall, precision),
    'referenceCharacterCount': referenceCharacterCount,
    'characterEditCount': characterEditCount,
    'normalizedCharacterErrorRate': _rate(
      characterEditCount,
      referenceCharacterCount,
    ),
    'duplicateLineCount': duplicateLineCount,
    'duplicateLineRate': _rate(duplicateLineCount, hypothesisLineCount),
    'timedMatchCount': timedPairs,
    'startTimeMaeMs': timedPairs == 0 ? null : weightedStartError / timedPairs,
    'within500msRate': timedPairs == 0
        ? null
        : weightedWithinTolerance / timedPairs,
  };
}

/// Scores a corpus document.
///
/// [baseDirectory] resolves relative `path` entries; pass the corpus file's
/// parent directory. Inline `text`/`lines` entries need no file access.
Map<String, Object?> evaluateQualityCorpus(
  String source, {
  String? baseDirectory,
  double? matchThreshold,
}) {
  final corpus = _asMap(jsonDecode(source), 'Corpus');
  if (corpus['schemaVersion'] != kQualityReportSchemaVersion) {
    throw const FormatException('Corpus must be a schemaVersion 1 object.');
  }
  final thresholdValue = matchThreshold ?? _asDouble(corpus['matchThreshold']);
  final threshold = thresholdValue ?? kDefaultMatchThreshold;
  if (threshold <= 0 || threshold > 1) {
    throw const FormatException(
      'matchThreshold must be greater than 0 and at most 1.',
    );
  }
  final rawSongs = _asList(corpus['songs'], 'Corpus songs');
  if (rawSongs.isEmpty || rawSongs.length > _maxSongs) {
    throw const FormatException('Corpus needs 1–200 songs.');
  }

  final songResults = <Map<String, Object?>>[];
  final warnings = <String>[];
  final scoresByEngine = <String, List<Map<String, Object?>>>{};
  final songIds = <String>{};

  for (final rawSong in rawSongs) {
    final song = _asMap(rawSong, 'Corpus song');
    final rawId = song['id'];
    if (rawId is! String || rawId.trim().isEmpty) {
      throw const FormatException('Every corpus song needs a non-empty id.');
    }
    final id = rawId.trim();
    if (!songIds.add(id)) {
      throw FormatException('Duplicate corpus song id: $id');
    }
    final language = song['language'] is String
        ? song['language'] as String
        : null;

    final rawReference = song['reference'];
    final Map<String, dynamic> referenceEntry;
    if (rawReference is Map) {
      referenceEntry = rawReference.cast<String, dynamic>();
    } else if (rawReference is String) {
      referenceEntry = <String, dynamic>{'path': rawReference};
    } else {
      throw FormatException('Song $id needs a reference entry.');
    }
    final reference = _parseCorpusEntry(
      referenceEntry,
      'Reference for $id',
      baseDirectory,
    );
    final referenceReviewed = referenceEntry['reviewed'] == true;
    if (!referenceReviewed) {
      warnings.add('Song $id: reference is not marked reviewed: true.');
    }

    final candidates = _asList(song['candidates'], 'Candidates for $id');
    if (candidates.isEmpty) {
      throw FormatException('Song $id has no candidates.');
    }
    final engineNames = <String>{};
    final songScores = <Map<String, Object?>>[];
    for (final rawCandidate in candidates) {
      final candidate = _asMap(rawCandidate, 'Candidate for $id');
      final rawEngine = candidate['engine'];
      if (rawEngine is! String || rawEngine.trim().isEmpty) {
        throw FormatException('Every candidate of $id needs an engine.');
      }
      final engine = rawEngine.trim();
      if (!engineNames.add(engine)) {
        throw FormatException('Duplicate engine $engine in song $id');
      }
      final hypothesis = _parseCorpusEntry(
        candidate,
        '$id / $engine',
        baseDirectory,
      );
      final score = evaluateLyricQualityPair(
        songId: id,
        engine: engine,
        language: language,
        reference: reference,
        hypothesis: hypothesis,
        matchThreshold: threshold,
      );
      songScores.add(score);
      (scoresByEngine[engine] ??= <Map<String, Object?>>[]).add(score);
      if (score['timedMatchCount'] == 0) {
        warnings.add(
          'Song $id / $engine: no timestamps on both sides; timing metrics '
          'are null.',
        );
      }
    }
    songResults.add(<String, Object?>{
      'id': id,
      'language': language,
      'referenceLineCount': reference.length,
      'referenceReviewed': referenceReviewed,
      'candidates': songScores,
    });
  }

  final engines = scoresByEngine.keys.toList()..sort();
  return <String, Object?>{
    'schemaVersion': kQualityReportSchemaVersion,
    'evaluator': 'lyricforge-line-quality-v1',
    'matchThreshold': threshold,
    'songCount': songResults.length,
    'candidateCount': scoresByEngine.values.fold<int>(
      0,
      (sum, scores) => sum + scores.length,
    ),
    'overallByEngine': <String, Object?>{
      for (final engine in engines)
        engine: _summarizeEngine(scoresByEngine[engine]!),
    },
    'songs': songResults,
    'warnings': warnings,
    'interpretation': _interpretation,
  };
}

const Map<String, Object?> _interpretation = <String, Object?>{
  'lineRecall':
      'Reference lines matched to a hypothesis line at or above matchThreshold, '
      'over reference lines. Low values mean lyrics are missing.',
  'linePrecision':
      'Matched hypothesis lines over all hypothesis lines. Falls when the '
      'pipeline invents extra rows.',
  'normalizedCharacterErrorRate':
      'Character edits over the whole joined document divided by reference '
      'characters; same normalization as tool/asr_transcript_eval.dart, so the '
      'numbers are comparable between the two tools.',
  'duplicateLineRate':
      'Extra hypothesis lines that restate another line within '
      'duplicateWindowMs, over hypothesis lines. Chorus repeats further apart '
      'are not counted. This is the metric that exposes the dual-engine fusion '
      'defect.',
  'startTimeMaeMs':
      'Mean absolute error of line start times over matched pairs, in '
      'milliseconds. Requires timestamps on both sides.',
  'within500msRate':
      'Share of matched pairs whose start times are within 500 ms.',
  'lineCountRatio':
      'Hypothesis lines over reference lines. 1.0 is ideal; above 1.2 means the '
      'pipeline is inserting rows.',
  'limitations':
      'Judges text, line segmentation, and timestamps only. Audio quality, '
      'vocal separation, and engine speed are out of scope.',
};

// ---------------------------------------------------------------------------
// Baseline comparison
// ---------------------------------------------------------------------------

const double _recallRegressionTolerance = 0.02;
const double _errorRateRegressionTolerance = 0.02;
const double _lineRatioRegressionTolerance = 0.05;
const double _timestampRegressionToleranceMs = 50;

/// Compares two reports and lists per-engine improvements and regressions.
///
/// Store today's report, change the pipeline, re-run, and fail the build when a
/// metric got worse.
Map<String, Object?> compareQualityReports(
  Map<String, Object?> baseline,
  Map<String, Object?> current,
) {
  final baselineEngines = _asMap(
    baseline['overallByEngine'],
    'Baseline overallByEngine',
  );
  final currentEngines = _asMap(
    current['overallByEngine'],
    'Current overallByEngine',
  );
  final engines = currentEngines.keys.toList()..sort();
  final perEngine = <String, Object?>{};
  final regressions = <Map<String, Object?>>[];
  final improvements = <Map<String, Object?>>[];

  void record(
    String engine,
    String metric,
    Map<String, dynamic> before,
    Map<String, dynamic> after, {
    required bool higherIsBetter,
    required double tolerance,
  }) {
    final previous = _asDouble(before[metric]);
    final next = _asDouble(after[metric]);
    if (previous == null || next == null) return;
    final delta = next - previous;
    final entry = <String, Object?>{
      'engine': engine,
      'metric': metric,
      'baseline': previous,
      'current': next,
      'delta': delta,
    };
    if (higherIsBetter ? delta < -tolerance : delta > tolerance) {
      regressions.add(entry);
    } else if (higherIsBetter ? delta > tolerance : delta < -tolerance) {
      improvements.add(entry);
    }
  }

  final newEngines = <String>[];
  for (final engine in engines) {
    final rawBefore = baselineEngines[engine];
    final after = _asMap(currentEngines[engine], 'Engine $engine');
    if (rawBefore is! Map) {
      // First run for this engine: nothing to compare against yet.
      newEngines.add(engine);
      continue;
    }
    final before = rawBefore.cast<String, dynamic>();
    record(
      engine,
      'lineRecall',
      before,
      after,
      higherIsBetter: true,
      tolerance: _recallRegressionTolerance,
    );
    record(
      engine,
      'normalizedCharacterErrorRate',
      before,
      after,
      higherIsBetter: false,
      tolerance: _errorRateRegressionTolerance,
    );
    record(
      engine,
      'duplicateLineRate',
      before,
      after,
      higherIsBetter: false,
      tolerance: _errorRateRegressionTolerance,
    );
    record(
      engine,
      'lineCountRatio',
      before,
      after,
      higherIsBetter: false,
      tolerance: _lineRatioRegressionTolerance,
    );
    record(
      engine,
      'startTimeMaeMs',
      before,
      after,
      higherIsBetter: false,
      tolerance: _timestampRegressionToleranceMs,
    );
    perEngine[engine] = <String, Object?>{
      for (final metric in <String>[
        'lineRecall',
        'linePrecision',
        'normalizedCharacterErrorRate',
        'duplicateLineRate',
        'lineCountRatio',
        'startTimeMaeMs',
        'within500msRate',
      ])
        metric: <String, Object?>{
          'baseline': _asDouble(before[metric]),
          'current': _asDouble(after[metric]),
        },
    };
  }

  final missingEngines =
      baselineEngines.keys
          .where((engine) => !currentEngines.containsKey(engine))
          .toList()
        ..sort();
  return <String, Object?>{
    'baselineEvaluator': baseline['evaluator'],
    'currentEvaluator': current['evaluator'],
    'byEngine': perEngine,
    'enginesOnlyInBaseline': missingEngines,
    'enginesOnlyInCurrent': newEngines,
    'regressions': regressions,
    'improvements': improvements,
    'regressed': regressions.isNotEmpty,
  };
}

// ---------------------------------------------------------------------------
// Text rendering
// ---------------------------------------------------------------------------

String _percent(Object? value) {
  final number = _asDouble(value);
  return number == null ? 'n/a' : (number * 100).toStringAsFixed(1) + '%';
}

String _milliseconds(Object? value) {
  final number = _asDouble(value);
  return number == null ? 'n/a' : number.toStringAsFixed(0) + ' ms';
}

String _ratio(Object? value) {
  final number = _asDouble(value);
  return number == null ? 'n/a' : number.toStringAsFixed(2);
}

String _metricValue(String metric, Object? value) => metric.endsWith('Ms')
    ? _milliseconds(value)
    : (metric == 'lineCountRatio' ? _ratio(value) : _percent(value));

/// Renders a compact human-readable summary of a report.
String formatQualityReport(Map<String, Object?> report) {
  final engines = _asMap(report['overallByEngine'], 'overallByEngine');
  final engineNames = engines.keys.toList()..sort();
  final buffer = StringBuffer()
    ..writeln('# Lyric quality baseline')
    ..writeln()
    ..writeln(
      '${report['songCount']} song(s), ${report['candidateCount']} candidate '
      'document(s), match threshold ${report['matchThreshold']}.',
    )
    ..writeln()
    ..writeln('## By engine')
    ..writeln()
    ..writeln(
      '| engine | songs | recall | precision | CER | duplicate rate | '
      'line ratio | start MAE | within 500 ms |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|');

  for (final engine in engineNames) {
    final summary = _asMap(engines[engine], 'Engine $engine');
    buffer.writeln(
      '| $engine | ${summary['songCount']} | '
      '${_percent(summary['lineRecall'])} | '
      '${_percent(summary['linePrecision'])} | '
      '${_percent(summary['normalizedCharacterErrorRate'])} | '
      '${_percent(summary['duplicateLineRate'])} | '
      '${_ratio(summary['lineCountRatio'])} | '
      '${_milliseconds(summary['startTimeMaeMs'])} | '
      '${_percent(summary['within500msRate'])} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## By song')
    ..writeln()
    ..writeln(
      '| song | engine | ref lines | out lines | matched | recall | CER | '
      'duplicates | start MAE |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|');
  for (final rawSong in report['songs'] as List? ?? const <Object?>[]) {
    final song = _asMap(rawSong, 'song');
    for (final rawCandidate
        in song['candidates'] as List? ?? const <Object?>[]) {
      final candidate = _asMap(rawCandidate, 'candidate');
      buffer.writeln(
        '| ${song['id']} | ${candidate['engine']} | '
        '${candidate['referenceLineCount']} | '
        '${candidate['hypothesisLineCount']} | '
        '${candidate['matchedLineCount']} | '
        '${_percent(candidate['lineRecall'])} | '
        '${_percent(candidate['normalizedCharacterErrorRate'])} | '
        '${candidate['duplicateLineCount']} | '
        '${_milliseconds(candidate['startTimeMaeMs'])} |',
      );
    }
  }

  final duplicates = <Map<String, Object?>>[];
  for (final rawSong in report['songs'] as List? ?? const <Object?>[]) {
    final song = _asMap(rawSong, 'song');
    for (final rawCandidate
        in song['candidates'] as List? ?? const <Object?>[]) {
      final candidate = _asMap(rawCandidate, 'candidate');
      for (final rawGroup
          in candidate['duplicateGroups'] as List? ?? const <Object?>[]) {
        final group = _asMap(rawGroup, 'duplicate group');
        duplicates.add(<String, Object?>{
          'song': song['id'],
          'engine': candidate['engine'],
          'text': group['text'],
          'kind': group['kind'],
          'startMs': group['startMs'],
        });
      }
    }
  }
  if (duplicates.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Duplicate lines')
      ..writeln();
    for (final duplicate in duplicates.take(_maxReportedDuplicateGroups)) {
      final start = _asDouble(duplicate['startMs']);
      buffer.writeln(
        '- ${duplicate['song']} / ${duplicate['engine']} '
        '(${duplicate['kind']}${start == null ? '' : ', t=${start.round()} ms'})'
        ': "${duplicate['text']}"',
      );
    }
  }

  final comparison = report['baselineComparison'];
  if (comparison is Map) {
    final map = comparison.cast<String, Object?>();
    final regressions = map['regressions'] as List? ?? const <Object?>[];
    final improvements = map['improvements'] as List? ?? const <Object?>[];
    buffer
      ..writeln()
      ..writeln('## Against baseline')
      ..writeln();
    if (regressions.isEmpty) {
      buffer.writeln('- No regressions.');
    }
    for (final raw in regressions) {
      final entry = _asMap(raw, 'regression');
      final metric = entry['metric'].toString();
      buffer.writeln(
        '- REGRESSION ${entry['engine']} $metric: '
        '${_metricValue(metric, entry['baseline'])} -> '
        '${_metricValue(metric, entry['current'])}',
      );
    }
    for (final raw in improvements) {
      final entry = _asMap(raw, 'improvement');
      final metric = entry['metric'].toString();
      buffer.writeln(
        '- improved ${entry['engine']} $metric: '
        '${_metricValue(metric, entry['baseline'])} -> '
        '${_metricValue(metric, entry['current'])}',
      );
    }
  }

  final warnings = report['warnings'] as List? ?? const <Object?>[];
  if (warnings.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Warnings');
    for (final warning in warnings) {
      buffer.writeln('- $warning');
    }
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const String _usage = '''
Usage:
  dart run tool/asr_quality_report.dart --corpus <corpus.json> [options]
  dart run tool/asr_quality_report.dart --reference <file> --hypothesis <file>

Options:
  --output <path>            Write the JSON report to a file.
  --baseline <path>          Compare against a previous JSON report.
  --fail-on-regression       Exit 1 when --baseline shows a regression.
  --match-threshold <0..1>   Override the default 0.6 line-match threshold.
  --engine <name>            Engine label for --hypothesis (default: hypothesis).
  --json                     Print JSON instead of the text summary.
  --help                     Show this message.

Sources may be .lrc (timestamps), .txt (plain lines), or .json
(LyricDocument, a line array, or a projects.json export).
''';

String _fileStem(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

Map<String, Object?> singlePairReport({
  required List<QualityLine> reference,
  required List<QualityLine> hypothesis,
  required String engine,
  required String songId,
  double matchThreshold = kDefaultMatchThreshold,
}) {
  final score = evaluateLyricQualityPair(
    songId: songId,
    engine: engine,
    reference: reference,
    hypothesis: hypothesis,
    matchThreshold: matchThreshold,
  );
  return <String, Object?>{
    'schemaVersion': kQualityReportSchemaVersion,
    'evaluator': 'lyricforge-line-quality-v1',
    'matchThreshold': matchThreshold,
    'songCount': 1,
    'candidateCount': 1,
    'overallByEngine': <String, Object?>{
      engine: _summarizeEngine(<Map<String, Object?>>[score]),
    },
    'songs': <Object?>[
      <String, Object?>{
        'id': songId,
        'language': null,
        'referenceLineCount': reference.length,
        'referenceReviewed': false,
        'candidates': <Object?>[score],
      },
    ],
    'warnings': <Object?>[
      'Reference is not marked reviewed: true; only a hand-checked reference '
          'makes these numbers a baseline.',
    ],
    'interpretation': _interpretation,
  };
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help')) {
    stdout.write(_usage);
    if (args.isEmpty) exitCode = 2;
    return;
  }

  final values = <String, String>{};
  final flags = <String>{};
  const valueOptions = <String>{
    '--corpus',
    '--reference',
    '--hypothesis',
    '--output',
    '--baseline',
    '--engine',
    '--match-threshold',
  };
  const flagOptions = <String>{'--fail-on-regression', '--json'};

  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (valueOptions.contains(argument)) {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        stderr.writeln('Missing value for $argument. Use --help.');
        exitCode = 2;
        return;
      }
      if (values.containsKey(argument)) {
        stderr.writeln('Duplicate option: $argument.');
        exitCode = 2;
        return;
      }
      values[argument] = args[++index];
    } else if (flagOptions.contains(argument)) {
      flags.add(argument);
    } else {
      stderr.writeln('Unknown option: $argument. Use --help.');
      exitCode = 2;
      return;
    }
  }

  var threshold = kDefaultMatchThreshold;
  final rawThreshold = values['--match-threshold'];
  if (rawThreshold != null) {
    final parsed = double.tryParse(rawThreshold);
    if (parsed == null || parsed <= 0 || parsed > 1) {
      stderr.writeln('--match-threshold must be > 0 and at most 1.');
      exitCode = 2;
      return;
    }
    threshold = parsed;
  }

  final corpusPath = values['--corpus'];
  final referencePath = values['--reference'];
  final hypothesisPath = values['--hypothesis'];
  final outputPath = values['--output'];
  final baselinePath = values['--baseline'];
  final engine = values['--engine'] ?? 'hypothesis';

  try {
    late Map<String, Object?> report;
    if (corpusPath != null) {
      if (referencePath != null || hypothesisPath != null) {
        stderr.writeln('Use either --corpus or --reference/--hypothesis.');
        exitCode = 2;
        return;
      }
      final corpusFile = File(corpusPath);
      if (!corpusFile.existsSync()) {
        throw FileSystemException('Corpus not found.', corpusPath);
      }
      report = evaluateQualityCorpus(
        corpusFile.readAsStringSync(),
        baseDirectory: corpusFile.parent.absolute.path,
        matchThreshold: rawThreshold == null ? null : threshold,
      );
    } else if (referencePath != null && hypothesisPath != null) {
      for (final path in <String>[referencePath, hypothesisPath]) {
        if (!File(path).existsSync()) {
          throw FileSystemException('Lyric source not found.', path);
        }
      }
      report = singlePairReport(
        reference: parseLyricSource(
          File(referencePath).readAsStringSync(),
          'Reference $referencePath',
        ),
        hypothesis: parseLyricSource(
          File(hypothesisPath).readAsStringSync(),
          'Hypothesis $hypothesisPath',
        ),
        engine: engine,
        songId: _fileStem(hypothesisPath),
        matchThreshold: threshold,
      );
    } else {
      stderr.writeln(
        'Provide --corpus, or both --reference and --hypothesis. Use --help.',
      );
      exitCode = 2;
      return;
    }

    if (baselinePath != null) {
      final baselineFile = File(baselinePath);
      if (!baselineFile.existsSync()) {
        throw FileSystemException('Baseline report not found.', baselinePath);
      }
      report['baselineComparison'] = compareQualityReports(
        _asMap(jsonDecode(baselineFile.readAsStringSync()), 'Baseline report'),
        report,
      );
    }

    final encoded = const JsonEncoder.withIndent('  ').convert(report) + '\n';
    if (outputPath != null) {
      File(outputPath).writeAsStringSync(encoded);
      stdout.writeln('Wrote lyric quality report: $outputPath');
    }
    stdout.write(
      flags.contains('--json') ? encoded : formatQualityReport(report),
    );

    if (flags.contains('--fail-on-regression')) {
      final comparison = report['baselineComparison'];
      final regressions = comparison is Map ? comparison['regressions'] : null;
      if (regressions is List && regressions.isNotEmpty) {
        stderr.writeln(
          'Quality regressed against the baseline (${regressions.length} '
          'metric(s)); see the report above.',
        );
        exitCode = 1;
      }
    }
  } on FormatException catch (error) {
    stderr.writeln('Invalid lyric quality input: ${error.message}');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('${error.message}: ${error.path ?? ''}');
    exitCode = 2;
  }
}
