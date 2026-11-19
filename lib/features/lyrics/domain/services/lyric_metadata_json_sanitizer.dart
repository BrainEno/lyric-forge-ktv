import '../../../project/domain/models/lyric_document.dart';

/// Makes a lyric document's metadata safe to write as JSON.
///
/// Metadata is an open `Map<String, dynamic>` that many tools add to:
/// reference alignment, proofreading, tap sync, review decisions. Each tool is
/// meant to store plain JSON values, but nothing enforced it, and a single
/// `Set`, enum, `Duration` or non-finite number made `jsonEncode` throw when
/// the project was saved. The editor then reported a save failure after a
/// successful proofread, and the draft could never be written.
///
/// The sanitizer converts the values a tool is likely to leave behind into
/// their JSON form and drops what has no faithful one:
///
/// * `Set` and other iterables become lists, in iteration order;
/// * an enum becomes its `name`, a `Duration` its milliseconds and a
///   `DateTime` its ISO-8601 text;
/// * map keys become strings;
/// * `NaN` and infinities are removed, because JSON has no spelling for them;
/// * any other object becomes its `toString()`, so the save still succeeds
///   and the value stays readable.
///
/// Values that are already JSON are kept unchanged, and when nothing needs
/// converting the original map is returned, so a normal save allocates nothing.
class LyricMetadataJsonSanitizer {
  const LyricMetadataJsonSanitizer();

  /// [document] with JSON-safe metadata; [document] itself when it already is.
  LyricDocument sanitizeDocument(LyricDocument document) {
    final metadata = sanitize(document.metadata);
    if (identical(metadata, document.metadata)) return document;
    return document.copyWith(metadata: metadata);
  }

  /// JSON-safe copy of [metadata], or [metadata] itself when it already is.
  Map<String, dynamic> sanitize(Map<String, dynamic> metadata) {
    if (isJsonSafe(metadata)) return metadata;
    final converted = _convert(metadata);
    return converted is Map<String, dynamic> ? converted : <String, dynamic>{};
  }

  /// Whether [value] can be passed to `jsonEncode` as is.
  bool isJsonSafe(Object? value) {
    if (value == null || value is String || value is bool || value is int) {
      return true;
    }
    if (value is double) return value.isFinite;
    if (value is List) return value.every(isJsonSafe);
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String || !isJsonSafe(entry.value)) return false;
      }
      return true;
    }
    return false;
  }

  Object? _convert(Object? value) {
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    if (value is double) return value.isFinite ? value : _dropped;
    if (value is Enum) return value.name;
    if (value is Duration) return value.inMilliseconds;
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final converted = _convert(entry.value);
        if (identical(converted, _dropped)) continue;
        result[entry.key.toString()] = converted;
      }
      return result;
    }
    if (value is Iterable) {
      final result = <Object?>[];
      for (final item in value) {
        final converted = _convert(item);
        if (!identical(converted, _dropped)) result.add(converted);
      }
      return result;
    }
    return value.toString();
  }

  static const Object _dropped = _Dropped();
}

/// Marks a value that has no JSON form and is left out.
class _Dropped {
  const _Dropped();
}
