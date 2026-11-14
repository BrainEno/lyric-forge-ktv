import 'dart:convert';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/asr_confidence.dart';
import '../../domain/models/transcription_models.dart';

/// A bounded, reusable interpretation of one whisper.cpp JSON response.
///
/// The service which runs whisper.cpp and the project-evidence reader must use
/// the same mapping so a persisted second opinion cannot silently differ from
/// the transcript used during recognition. Parsed output is still only ASR
/// evidence; it is not a statement about recognition accuracy.
class WhisperJsonTranscriptParseResult {
  final LyricDocument document;
  final String detectedLanguage;
  final int inputSegmentCount;
  final int skippedSegmentCount;
  final int lowConfidenceCount;

  const WhisperJsonTranscriptParseResult({
    required this.document,
    required this.detectedLanguage,
    required this.inputSegmentCount,
    required this.skippedSegmentCount,
    required this.lowConfidenceCount,
  });
}

/// Parses the line-level timeline emitted by whisper.cpp.
///
/// Limits are applied before constructing lyric objects. This parser is shared
/// by normal recognition and by the read-only project artifact reader, which
/// may encounter old or externally modified JSON files.
class WhisperJsonTranscriptParser {
  static const int defaultMaxJsonCharacters = 24 * 1024 * 1024;
  static const int defaultMaxSegments = 20000;
  static const int defaultMaxTextRunesPerLine = 4096;
  static const int maxTimelineMilliseconds = 7 * 24 * 60 * 60 * 1000;
  static const int lowConfidenceThreshold = 65;

  final int maxJsonCharacters;
  final int maxSegments;
  final int maxTextRunesPerLine;

  const WhisperJsonTranscriptParser({
    this.maxJsonCharacters = defaultMaxJsonCharacters,
    this.maxSegments = defaultMaxSegments,
    this.maxTextRunesPerLine = defaultMaxTextRunesPerLine,
  });

  WhisperJsonTranscriptParseResult parse(
    String source, {
    String? rawJsonPath,
  }) {
    if (source.length > maxJsonCharacters) {
      throw const TranscriptionException.environment(
        'Whisper JSON 超出可读取大小限制',
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw TranscriptionException.environment(
        'Whisper JSON 格式无效',
        details: error.message,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const TranscriptionException.environment('Whisper JSON 格式无效');
    }

    final rawSegments = decoded['transcription'];
    if (rawSegments is! List) {
      throw const TranscriptionException.environment(
        'Whisper JSON 缺少 transcription',
      );
    }
    if (rawSegments.length > maxSegments) {
      throw const TranscriptionException.environment(
        'Whisper JSON 的片段数量超出可读取限制',
      );
    }

    final rawResult = decoded['result'];
    final rawLanguage = rawResult is Map ? rawResult['language'] : null;
    final detectedLanguage = rawLanguage is String &&
            rawLanguage.trim().isNotEmpty &&
            rawLanguage.length <= 64
        ? rawLanguage.trim()
        : 'unknown';
    final lines = <LyricLine>[];
    var lowConfidenceCount = 0;
    var skippedSegmentCount = 0;

    for (final raw in rawSegments) {
      final segment = _asStringMap(raw);
      if (segment == null) {
        skippedSegmentCount++;
        continue;
      }
      final rawText = segment['text'];
      if (rawText is! String) {
        skippedSegmentCount++;
        continue;
      }
      final text = rawText.trim();
      if (text.isEmpty || text.runes.length > maxTextRunesPerLine) {
        skippedSegmentCount++;
        continue;
      }

      final offsets = _asStringMap(segment['offsets']);
      if (offsets == null) {
        skippedSegmentCount++;
        continue;
      }
      final from = offsets['from'];
      final to = offsets['to'];
      if (from is! num ||
          to is! num ||
          !from.isFinite ||
          !to.isFinite ||
          from < 0 ||
          to <= from ||
          to > maxTimelineMilliseconds) {
        skippedSegmentCount++;
        continue;
      }
      final startMilliseconds = from.toInt();
      final endMilliseconds = to.toInt();
      if (endMilliseconds <= startMilliseconds) {
        skippedSegmentCount++;
        continue;
      }

      final score = _scoreSegment(segment);
      if (score.source != LyricConfidenceSource.unscored &&
          score.value < lowConfidenceThreshold) {
        lowConfidenceCount++;
      }
      lines.add(
        LyricLine(
          text: text,
          startTime: Duration(milliseconds: startMilliseconds),
          endTime: Duration(milliseconds: endMilliseconds),
          confidence: score.value,
          confidenceSource: score.source,
        ),
      );
    }

    if (lines.isEmpty) {
      throw const TranscriptionException.input(
        'Whisper 没有识别到可用歌词片段',
      );
    }

    final metadata = <String, dynamic>{
      'generatedBy': 'whisper.cpp',
      'draft': true,
      'segmentCount': lines.length,
      'lowConfidenceThreshold': lowConfidenceThreshold,
      'lowConfidenceLineCount': lowConfidenceCount,
      'confidenceSource': 'per-line: model|unscored',
      'skippedSegmentCount': skippedSegmentCount,
      if (rawJsonPath != null && rawJsonPath.trim().isNotEmpty)
        'rawJsonPath': rawJsonPath,
    };
    return WhisperJsonTranscriptParseResult(
      document: LyricDocument(
        language: detectedLanguage,
        lines: lines,
        metadata: metadata,
      ),
      detectedLanguage: detectedLanguage,
      inputSegmentCount: rawSegments.length,
      skippedSegmentCount: skippedSegmentCount,
      lowConfidenceCount: lowConfidenceCount,
    );
  }

  ({int value, LyricConfidenceSource source}) _scoreSegment(
    Map<String, dynamic> segment,
  ) {
    final tokens = segment['tokens'];
    if (tokens is List &&
        tokens.any(
          (token) =>
              token is Map &&
              token['text'] != null &&
              token['text'] is! String,
        )) {
      // Keep valid line text, but don't turn malformed score metadata into a
      // parser crash or a fabricated low-confidence result.
      return (
        value: unscoredConfidencePlaceholder,
        source: LyricConfidenceSource.unscored,
      );
    }
    return scoreWhisperSegment(segment);
  }

  Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      return null;
    }
  }
}
