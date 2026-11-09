import '../../../project/domain/models/lyric_document.dart';

/// Immutable snapshots of two independently generated transcripts, before fusion.
///
/// This records what the engines returned for a single input, not a guarantee
/// that either transcript covers the whole song or that the audio is unchanged.
/// Engine identities are display/provenance labels, not model content hashes.
class IndependentAsrEvidence {
  static const metadataKey = 'independentAsrEvidence';
  static const schemaVersion = 1;

  final DateTime capturedAtUtc;
  final IndependentAsrTranscript primary;
  final IndependentAsrTranscript secondary;

  IndependentAsrEvidence({
    required DateTime capturedAt,
    required this.primary,
    required this.secondary,
  }) : capturedAtUtc = capturedAt.toUtc();

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'scope': 'singleInput',
    'capturedAtUtc': capturedAtUtc.toIso8601String(),
    'primary': primary.toJson(),
    'secondary': secondary.toJson(),
  };

  /// Unknown or malformed metadata is not reliable comparison evidence.
  static IndependentAsrEvidence? tryParse(Object? value) {
    if (value is! Map ||
        value['schemaVersion'] != schemaVersion ||
        value['scope'] != 'singleInput' ||
        value['capturedAtUtc'] is! String) {
      return null;
    }
    final capturedAt = DateTime.tryParse(value['capturedAtUtc'] as String);
    final primary = IndependentAsrTranscript.tryParse(value['primary']);
    final secondary = IndependentAsrTranscript.tryParse(value['secondary']);
    if (capturedAt == null ||
        !capturedAt.isUtc ||
        primary == null ||
        secondary == null) {
      return null;
    }
    return IndependentAsrEvidence(
      capturedAt: capturedAt,
      primary: primary,
      secondary: secondary,
    );
  }
}

class IndependentAsrTranscript {
  final String engine;
  final String language;
  final Duration? globalOffset;
  final List<LyricLine> lines;

  IndependentAsrTranscript({
    required this.engine,
    required LyricDocument document,
  }) : language = document.language,
       globalOffset = document.globalOffset,
       lines = List.unmodifiable(document.lines);

  /// The original engine metadata and filesystem paths are deliberately not
  /// embedded; only text, timing and per-line confidence provenance are kept.
  LyricDocument toDocument() => LyricDocument(
    language: language,
    globalOffset: globalOffset,
    lines: List.unmodifiable(lines),
  );

  Map<String, dynamic> toJson() => {
    'engine': engine,
    'language': language,
    'globalOffsetMs': globalOffset?.inMilliseconds,
    'lines': [for (final line in lines) line.toJson()],
  };

  static IndependentAsrTranscript? tryParse(Object? value) {
    if (value is! Map ||
        value['engine'] is! String ||
        (value['engine'] as String).trim().isEmpty ||
        value['language'] is! String ||
        (value['language'] as String).trim().isEmpty ||
        (value['globalOffsetMs'] != null && value['globalOffsetMs'] is! int) ||
        value['lines'] is! List ||
        (value['lines'] as List).isEmpty) {
      return null;
    }
    final lines = <LyricLine>[];
    for (final raw in value['lines'] as List) {
      if (raw is! Map ||
          raw['text'] is! String ||
          raw['startTime'] is! int ||
          raw['endTime'] is! int ||
          (raw['startTime'] as int) < 0 ||
          (raw['endTime'] as int) <= (raw['startTime'] as int) ||
          raw['confidence'] is! int ||
          (raw['confidence'] as int) < 0 ||
          (raw['confidence'] as int) > 100 ||
          raw['confidenceSource'] is! String ||
          !LyricConfidenceSource.values.asNameMap().containsKey(
            raw['confidenceSource'],
          ) ||
          raw['isChorus'] is! bool ||
          (raw['id'] != null && raw['id'] is! String)) {
        return null;
      }
      lines.add(
        LyricLine(
          text: raw['text'] as String,
          startTime: Duration(milliseconds: raw['startTime'] as int),
          endTime: Duration(milliseconds: raw['endTime'] as int),
          confidence: raw['confidence'] as int,
          confidenceSource: LyricConfidenceSource.values
              .asNameMap()[raw['confidenceSource']]!,
          isChorus: raw['isChorus'] as bool,
          id: raw['id'] as String?,
        ),
      );
    }
    return IndependentAsrTranscript(
      engine: value['engine'] as String,
      document: LyricDocument(
        language: value['language'] as String,
        globalOffset: value['globalOffsetMs'] == null
            ? null
            : Duration(milliseconds: value['globalOffsetMs'] as int),
        lines: lines,
      ),
    );
  }
}
