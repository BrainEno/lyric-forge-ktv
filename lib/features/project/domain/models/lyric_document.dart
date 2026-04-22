class LyricLine {
  final String text;
  final Duration startTime;
  final Duration endTime;
  final bool isChorus;
  final int confidence;

  const LyricLine({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.isChorus = false,
    this.confidence = 100,
  });

  LyricLine copyWith({
    String? text,
    Duration? startTime,
    Duration? endTime,
    bool? isChorus,
    int? confidence,
  }) {
    return LyricLine(
      text: text ?? this.text,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isChorus: isChorus ?? this.isChorus,
      confidence: confidence ?? this.confidence,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'startTime': startTime.inMilliseconds,
      'endTime': endTime.inMilliseconds,
      'isChorus': isChorus,
      'confidence': confidence,
    };
  }

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      text: json['text'] as String,
      startTime: Duration(milliseconds: json['startTime'] as int),
      endTime: Duration(milliseconds: json['endTime'] as int),
      isChorus: json['isChorus'] as bool? ?? false,
      confidence: json['confidence'] as int? ?? 100,
    );
  }
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
