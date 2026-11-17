import 'whisper_decoding_policy.dart' show RecognitionHints;

/// The `context` text LyricForge sends with a Qwen3-ASR request.
///
/// Qwen3-ASR copies its context into the transcript when a chunk has little or
/// no singing: on the songs measured for D-024 every instrumental chunk came
/// back as "<title>. Artist: <artist>", and the aligner placed those words
/// over the intro, the solos and the outro. A song whose title is also its
/// hook ("Riders on the Storm") then shows the title line again and again
/// where nobody sings. Without the title and artist the same songs kept as
/// many words and lost most of those rows.
///
/// So only the proper nouns the user typed under the project's recognition
/// terms are sent, as a plain comma-separated list; never the title, artist
/// or album, and never lyric text. Returns an empty string when there are no
/// terms, which leaves the field out of the request.
String qwenRecognitionContext(RecognitionHints hints) =>
    qwenRecognitionTerms(hints).join(', ');

/// The recognition terms [qwenRecognitionContext] sends: trimmed, without
/// duplicates (letter case ignored), at most [maxQwenContextTerms].
List<String> qwenRecognitionTerms(RecognitionHints hints) {
  final seen = <String>{};
  final terms = <String>[];
  for (final raw in hints.terms) {
    final term = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (term.isEmpty || term.runes.length > maxQwenContextTermRunes) continue;
    if (!seen.add(term.toLowerCase())) continue;
    terms.add(term);
    if (terms.length == maxQwenContextTerms) break;
  }
  return List.unmodifiable(terms);
}

/// At most this many terms are sent.
const int maxQwenContextTerms = 12;

/// Longer entries are left out: a term is a name, not a sentence.
const int maxQwenContextTermRunes = 32;
