import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../project/domain/models/lyric_document.dart';

/// A fusion-time snapshot, not proof that a timestamp is accurate or that an
/// aligner actually received the timed text. Consumers must use [forLine]
/// rather than trusting the indexed JSON after edits or structural changes.
abstract final class FusionTimingEvidence {
  static const metadataKey = 'fusionTimingEvidence';
  static const version = 1;

  /// Hash the exact UTF-8 text, including punctuation and whitespace.
  static String textHash(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static Map<String, dynamic> entry({
    required int lineIndex,
    required LyricLine result,
    required String timedText,
    required bool secondaryOnly,
  }) {
    final changed = !secondaryOnly && timedText != result.text;
    return {
      'lineIndex': lineIndex,
      'startMs': result.startTime.inMilliseconds,
      'endMs': result.endTime.inMilliseconds,
      'finalTextHash': textHash(result.text),
      'timedTextHash': textHash(timedText),
      // The ASR result does not reveal the actual input to the aligner.
      'alignedTextHash': null,
      'primaryTextChanged': secondaryOnly ? null : changed,
      'secondaryOnly': secondaryOnly,
      // This flags fusion-related reasons only, not all possible timing risks.
      'needsRealignment': changed || secondaryOnly,
    };
  }

  static Map<String, dynamic> wrap(List<Map<String, dynamic>> entries) => {
    'version': version,
    'entries': entries,
  };

  /// Reject stale, ambiguous or malformed rows. Absence means unknown, never
  /// verified. The index, exact text and timing must all still match.
  static Map<int, Map<String, dynamic>> validatedEntries(
    LyricDocument document,
  ) {
    final raw = document.metadata[metadataKey];
    if (raw is! Map || raw['version'] != version || raw['entries'] is! List)
      return {};
    final result = <int, Map<String, dynamic>>{};
    final seen = <int>{};
    final duplicates = <int>{};
    final digest = RegExp(r'^[0-9a-f]{64}$');
    for (final item in raw['entries'] as List) {
      if (item is! Map || item['lineIndex'] is! int) continue;
      final index = item['lineIndex'] as int;
      if (!seen.add(index)) {
        duplicates.add(index);
        result.remove(index);
        continue;
      }
      if (index < 0 ||
          index >= document.lines.length ||
          item.keys.any((key) => key is! String))
        continue;
      final line = document.lines[index];
      final timed = item['timedTextHash'];
      final changed = item['primaryTextChanged'];
      final secondaryOnly = item['secondaryOnly'];
      if (item['finalTextHash'] != textHash(line.text) ||
          item['startMs'] != line.startTime.inMilliseconds ||
          item['endMs'] != line.endTime.inMilliseconds ||
          timed is! String ||
          !digest.hasMatch(timed) ||
          item['alignedTextHash'] != null ||
          secondaryOnly is! bool ||
          (secondaryOnly ? changed != null : changed is! bool) ||
          (secondaryOnly && timed != item['finalTextHash']) ||
          (!secondaryOnly && changed != (timed != item['finalTextHash'])) ||
          item['needsRealignment'] != (secondaryOnly || changed == true))
        continue;
      result[index] = Map<String, dynamic>.from(item);
    }
    for (final index in duplicates) {
      result.remove(index);
    }
    return result;
  }

  static Map<String, dynamic>? forLine(LyricDocument document, int index) =>
      validatedEntries(document)[index];
}
