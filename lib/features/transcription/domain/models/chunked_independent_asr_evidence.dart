import '../../../project/domain/models/lyric_document.dart';
import 'independent_asr_evidence.dart';

/// A complete, bounded set of independent per-chunk snapshots.
///
/// These snapshots describe separate inputs and are deliberately not a pair
/// of full-song transcripts. Overlap copies remain separate, and consumers
/// must not compare either side to the merged/editable draft as consensus.
/// Source and chunk hashes describe observed bytes, not a file lock or proof
/// of recognition accuracy.
class ChunkedIndependentAsrEvidence {
  static const metadataKey = 'chunkedIndependentAsrEvidence';
  static const schemaVersion = 1;
  static const maxChunks = 1000;
  static const maxLinesPerTranscript = 2000;
  static const maxTotalLines = 20000;
  static const maxTextRunesPerLine = 4096;
  static const maxDurationMs = 7 * 24 * 60 * 60 * 1000;
  static final _hashPattern = RegExp(r'^[0-9a-f]{64}$');
  static final _enginePattern = RegExp(r'^[a-z0-9._-]{1,80}$');

  final String sourceAudioSha256;
  final Duration duration;
  final Duration chunkDuration;
  final Duration overlap;
  final List<IndependentAsrChunk> chunks;

  ChunkedIndependentAsrEvidence._({
    required this.sourceAudioSha256,
    required this.duration,
    required this.chunkDuration,
    required this.overlap,
    required List<IndependentAsrChunk> chunks,
  }) : chunks = List.unmodifiable(chunks);

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'scope': 'completeChunkPlan',
    'sourceAudioSha256': sourceAudioSha256,
    'durationMs': duration.inMilliseconds,
    'chunkDurationMs': chunkDuration.inMilliseconds,
    'overlapMs': overlap.inMilliseconds,
    'chunks': [for (final chunk in chunks) chunk.toJson()],
  };

  /// Reject partial plans, unknown schemas, invalid times, and evidence from
  /// different engine configurations rather than guessing missing provenance.
  static ChunkedIndependentAsrEvidence? tryParse(Object? raw) {
    if (raw is! Map ||
        raw['schemaVersion'] is! int ||
        raw['schemaVersion'] != schemaVersion ||
        raw['scope'] != 'completeChunkPlan' ||
        raw['sourceAudioSha256'] is! String ||
        !_hashPattern.hasMatch(raw['sourceAudioSha256'] as String) ||
        raw['durationMs'] is! int ||
        raw['chunkDurationMs'] is! int ||
        raw['overlapMs'] is! int ||
        raw['chunks'] is! List) {
      return null;
    }
    final total = raw['durationMs'] as int;
    final length = raw['chunkDurationMs'] as int;
    final overlap = raw['overlapMs'] as int;
    final rawChunks = raw['chunks'] as List;
    if (total <= 0 ||
        total > maxDurationMs ||
        length <= 0 ||
        overlap < 0 ||
        overlap >= length ||
        total <= length ||
        rawChunks.length < 2 ||
        rawChunks.length > maxChunks) {
      return null;
    }
    final step = length - overlap;
    final chunks = <IndependentAsrChunk>[];
    String? primaryEngine;
    String? secondaryEngine;
    String? primaryLanguage;
    String? secondaryLanguage;
    var totalLines = 0;
    for (var i = 0; i < rawChunks.length; i++) {
      final item = rawChunks[i];
      final expectedStart = i * step;
      final expectedEnd = expectedStart + length < total
          ? expectedStart + length
          : total;
      if (item is! Map ||
          item['index'] is! int ||
          item['startMs'] is! int ||
          item['endMs'] is! int ||
          item['index'] != i ||
          item['startMs'] != expectedStart ||
          item['endMs'] != expectedEnd ||
          expectedStart >= total ||
          (i < rawChunks.length - 1 && expectedEnd == total))
        return null;
      final counts = _rawLineCount(item['evidence']);
      if (counts == null || totalLines + counts > maxTotalLines) return null;
      final evidence = IndependentAsrEvidence.tryParse(item['evidence']);
      if (evidence == null ||
          evidence.sourceAudioSha256 == null ||
          !_independentEngines(
            evidence.primary.engine,
            evidence.secondary.engine,
          ) ||
          !_validTranscript(evidence.primary, expectedEnd - expectedStart) ||
          !_validTranscript(evidence.secondary, expectedEnd - expectedStart))
        return null;
      primaryEngine ??= evidence.primary.engine;
      secondaryEngine ??= evidence.secondary.engine;
      primaryLanguage ??= evidence.primary.language;
      secondaryLanguage ??= evidence.secondary.language;
      if (primaryEngine != evidence.primary.engine ||
          secondaryEngine != evidence.secondary.engine ||
          primaryLanguage != evidence.primary.language ||
          secondaryLanguage != evidence.secondary.language)
        return null;
      totalLines += counts;
      chunks.add(
        IndependentAsrChunk._(
          index: i,
          start: Duration(milliseconds: expectedStart),
          end: Duration(milliseconds: expectedEnd),
          evidence: evidence,
        ),
      );
    }
    if (chunks.last.end.inMilliseconds != total) return null;
    return ChunkedIndependentAsrEvidence._(
      sourceAudioSha256: raw['sourceAudioSha256'] as String,
      duration: Duration(milliseconds: total),
      chunkDuration: Duration(milliseconds: length),
      overlap: Duration(milliseconds: overlap),
      chunks: chunks,
    );
  }

  // Inspect sizes before constructing transcripts from untrusted project JSON.
  static int? _rawLineCount(Object? raw) {
    if (raw is! Map || raw['primary'] is! Map || raw['secondary'] is! Map)
      return null;
    var total = 0;
    for (final value in [raw['primary'], raw['secondary']]) {
      final lines = (value as Map)['lines'];
      if (lines is! List ||
          lines.isEmpty ||
          lines.length > maxLinesPerTranscript)
        return null;
      for (final line in lines) {
        if (line is! Map ||
            line['text'] is! String ||
            (line['text'] as String).runes.length > maxTextRunesPerLine)
          return null;
      }
      total += lines.length;
    }
    return total;
  }

  static bool _independentEngines(String primary, String secondary) {
    if (!_enginePattern.hasMatch(primary) ||
        !_enginePattern.hasMatch(secondary))
      return false;
    bool qwen(String engine) => engine.startsWith('qwen3-asr-');
    bool whisper(String engine) => engine.startsWith('whisper.cpp-');
    return (qwen(primary) && whisper(secondary)) ||
        (whisper(primary) && qwen(secondary));
  }

  static bool _validTranscript(
    IndependentAsrTranscript transcript,
    int durationMs,
  ) {
    if ((transcript.globalOffset ?? Duration.zero) != Duration.zero ||
        transcript.lines.length > maxLinesPerTranscript)
      return false;
    var previous = -1;
    for (final line in transcript.lines) {
      final start = line.startTime.inMilliseconds;
      final end = line.endTime.inMilliseconds;
      if (line.text.trim().isEmpty || start < previous || end > durationMs)
        return false;
      previous = start;
    }
    return true;
  }
}

/// Source indices remain local to one invocation, including in overlap regions.
class IndependentAsrChunk {
  final int index;
  final Duration start;
  final Duration end;
  final IndependentAsrEvidence evidence;

  const IndependentAsrChunk._({
    required this.index,
    required this.start,
    required this.end,
    required this.evidence,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'evidence': evidence.toJson(),
  };

  /// Copy one original transcript onto the full source timeline. This is not
  /// deduplication, fusion, or a mapping to current editor rows.
  LyricDocument globalTranscript({required bool primary}) {
    final transcript = primary ? evidence.primary : evidence.secondary;
    return LyricDocument(
      language: transcript.language,
      lines: List.unmodifiable([
        for (final line in transcript.lines)
          line.copyWith(
            startTime: line.startTime + start,
            endTime: line.endTime + start,
          ),
      ]),
    );
  }
}
