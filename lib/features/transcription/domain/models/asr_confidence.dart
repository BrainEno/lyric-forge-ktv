import '../../../project/domain/models/lyric_document.dart';

/// Scores one ASR line and says where the number came from.
///
/// [explicitConfidence] is whatever the engine reported. When it is null the
/// line is [LyricConfidenceSource.unscored] and [unscoredConfidencePlaceholder]
/// is returned; duration/text heuristics never turn a missing score into a
/// scored one.
({int value, LyricConfidenceSource source}) scoreAsrLine({
  required String text,
  required Duration start,
  required Duration end,
  int? explicitConfidence,
}) {
  var score = explicitConfidence ?? unscoredConfidencePlaceholder;
  var adjusted = false;

  final duration = end - start;
  if (duration > const Duration(seconds: 9)) {
    score -= 18;
    adjusted = true;
  }
  if (text.length > 72) {
    score -= 18;
    adjusted = true;
  }
  if (duration < const Duration(milliseconds: 350) && text.length > 8) {
    score -= 18;
    adjusted = true;
  }
  if (hasSuspiciousRepetition(text)) {
    score -= 35;
    adjusted = true;
  }
  if (text.trim().length <= 1) {
    score -= 12;
    adjusted = true;
  }

  return (
    value: score.clamp(25, 99).toInt(),
    source: explicitConfidence == null
        ? LyricConfidenceSource.unscored
        : adjusted
        ? LyricConfidenceSource.heuristic
        : LyricConfidenceSource.model,
  );
}

/// Scores one whisper.cpp segment from its per-token probabilities.
///
/// Returns an [unscored] line when the segment carries no probabilities: an
/// invented 50% would otherwise look like the model had been unsure.
({int value, LyricConfidenceSource source}) scoreWhisperSegment(
  Map<String, dynamic> segment,
) {
  final tokens = segment['tokens'];
  if (tokens is! List) {
    return _unscoredSegment;
  }

  final probabilities = <double>[];
  for (final rawToken in tokens) {
    if (rawToken is! Map) continue;
    final token = Map<String, dynamic>.from(rawToken);
    final text = (token['text'] as String? ?? '').trim();
    // whisper.cpp marks non-speech such as [_BEG_] with bracketed tokens; their
    // probabilities say nothing about the recognised lyrics.
    if (text.startsWith('[_') && text.endsWith('_]')) continue;
    final probability = token['p'];
    if (probability is num) {
      probabilities.add(probability.toDouble().clamp(0.0, 1.0));
    }
  }

  if (probabilities.isEmpty) return _unscoredSegment;

  final average =
      probabilities.reduce((a, b) => a + b) / probabilities.length;
  return (
    value: (average * 100).round().clamp(0, 100).toInt(),
    source: LyricConfidenceSource.model,
  );
}

const ({int value, LyricConfidenceSource source}) _unscoredSegment = (
  value: unscoredConfidencePlaceholder,
  source: LyricConfidenceSource.unscored,
);

/// Detects text a decoder typically emits when it loops: the same token
/// repeated back to back, or a very small vocabulary spread across the line.
bool hasSuspiciousRepetition(String text) {
  final normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff\u3040-\u30ff]+'), ' ')
      .trim();
  if (normalized.length < 8) return false;

  final tokens = normalized.contains(' ')
      ? normalized.split(RegExp(r'\s+'))
      : normalized.runes.map(String.fromCharCode).toList();
  if (tokens.length < 4) return false;

  var repeated = 0;
  for (var i = 1; i < tokens.length; i++) {
    if (tokens[i] == tokens[i - 1]) repeated++;
  }

  return repeated >= 2 || tokens.toSet().length / tokens.length < 0.45;
}
