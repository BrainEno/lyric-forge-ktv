/// Placeholder score for a line whose engine produced no number.
///
/// It exists so review ordering stays stable, not to describe accuracy:
/// [LyricConfidenceSource.unscored] is what tells every threshold in the app to
/// treat the line as unknown rather than as a poor result.
const int unscoredConfidencePlaceholder = 50;

/// Where a line's [LyricLine.confidence] number came from.
///
/// The number is a review signal, not a measurement, and an engine that never
/// produced a probability must not look like one that scored the line badly.
/// [unscored] keeps that distinction available to every consumer: the numeric
/// field still carries a heuristic value for ordering, but thresholds treat the
/// line as "unknown" instead of "low".
enum LyricConfidenceSource {
  /// An engine returned a probability and the line uses it unchanged.
  model,

  /// An engine returned a probability, but duration/text heuristics adjusted it.
  heuristic,

  /// No engine score exists; [LyricLine.confidence] is a placeholder.
  unscored,
}

/// One sung word (or character) of a row with its own time, as a forced
/// aligner or word-by-word tap-to-sync produced it.
///
/// Times are absolute on the timeline the row had when they were recorded.
/// They are kept even when the row is later moved or its text corrected:
/// `LyricWordTimingService` maps them onto the row's current span and only
/// uses them while the row still has as many sung characters as the words
/// do, so a homophone fix (在→再) keeps the timing and a rewrite drops it.
class LyricWordTiming {
  final String text;
  final Duration start;
  final Duration end;

  const LyricWordTiming({
    required this.text,
    required this.start,
    required this.end,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'start': start.inMilliseconds,
    'end': end.inMilliseconds,
  };

  /// Null for malformed entries, so one bad word never breaks a document.
  static LyricWordTiming? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    final start = json['start'];
    final end = json['end'];
    if (text is! String || start is! int || end is! int) return null;
    return LyricWordTiming(
      text: text,
      start: Duration(milliseconds: start),
      end: Duration(milliseconds: end),
    );
  }

  @override
  String toString() => 'LyricWordTiming($text, $start, $end)';
}

class LyricLine {
  final String text;
  final Duration startTime;
  final Duration endTime;
  final bool isChorus;
  final int confidence;

  /// Defaults to [LyricConfidenceSource.model] so documents written before this
  /// field existed keep behaving exactly as they did.
  final LyricConfidenceSource confidenceSource;

  /// Whether [confidence] is backed by an engine score.
  bool get hasConfidenceScore =>
      confidenceSource != LyricConfidenceSource.unscored;

  /// A line is only "low confidence" when it actually has a score to be low.
  bool isLowConfidence(int threshold) =>
      hasConfidenceScore && confidence < threshold;

  /// 稳定行标识：插入/删除/对齐等结构变化后保持不变。
  /// 用于"手工编辑保护"跨会话持久化与对齐结果溯源；旧数据没有该字段时为 null。
  final String? id;

  /// Per-word timing from a forced aligner or word-by-word tap-to-sync;
  /// empty when only the row's start and end are known.
  final List<LyricWordTiming> words;

  const LyricLine({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.isChorus = false,
    this.confidence = 100,
    this.confidenceSource = LyricConfidenceSource.model,
    this.id,
    this.words = const [],
  });

  LyricLine copyWith({
    String? text,
    Duration? startTime,
    Duration? endTime,
    bool? isChorus,
    int? confidence,
    LyricConfidenceSource? confidenceSource,
    String? id,
    List<LyricWordTiming>? words,
  }) {
    return LyricLine(
      text: text ?? this.text,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isChorus: isChorus ?? this.isChorus,
      confidence: confidence ?? this.confidence,
      confidenceSource: confidenceSource ?? this.confidenceSource,
      id: id ?? this.id,
      words: words ?? this.words,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'startTime': startTime.inMilliseconds,
      'endTime': endTime.inMilliseconds,
      'isChorus': isChorus,
      'confidence': confidence,
      'confidenceSource': confidenceSource.name,
      if (id != null) 'id': id,
      if (words.isNotEmpty) 'words': [for (final word in words) word.toJson()],
    };
  }

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      text: json['text'] as String,
      startTime: Duration(milliseconds: json['startTime'] as int),
      endTime: Duration(milliseconds: json['endTime'] as int),
      isChorus: json['isChorus'] as bool? ?? false,
      confidence: json['confidence'] as int? ?? 100,
      confidenceSource: _confidenceSourceFromJson(json['confidenceSource']),
      id: json['id'] as String?,
      words: _wordsFromJson(json['words']),
    );
  }
}

List<LyricWordTiming> _wordsFromJson(Object? raw) {
  if (raw is! List) return const [];
  final words = <LyricWordTiming>[];
  for (final item in raw) {
    final word = LyricWordTiming.tryFromJson(item);
    if (word != null) words.add(word);
  }
  return List.unmodifiable(words);
}

LyricConfidenceSource _confidenceSourceFromJson(Object? raw) {
  if (raw is String) {
    for (final source in LyricConfidenceSource.values) {
      if (source.name == raw) return source;
    }
  }
  return LyricConfidenceSource.model;
}

class LyricDocument {
  final String language;
  final List<LyricLine> lines;
  final Duration? globalOffset;
  final Map<String, dynamic> metadata;

  const LyricDocument({
    required this.language,
    required this.lines,
    this.globalOffset,
    this.metadata = const {},
  });

  LyricDocument copyWith({
    String? language,
    List<LyricLine>? lines,
    Duration? globalOffset,
    Map<String, dynamic>? metadata,
  }) {
    return LyricDocument(
      language: language ?? this.language,
      lines: lines ?? this.lines,
      globalOffset: globalOffset ?? this.globalOffset,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'language': language,
      'lines': lines.map((e) => e.toJson()).toList(),
      'globalOffset': globalOffset?.inMilliseconds,
      'metadata': metadata,
    };
  }

  factory LyricDocument.fromJson(Map<String, dynamic> json) {
    return LyricDocument(
      language: json['language'] as String,
      lines: (json['lines'] as List)
          .map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      globalOffset: json['globalOffset'] != null
          ? Duration(milliseconds: json['globalOffset'] as int)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }
}
