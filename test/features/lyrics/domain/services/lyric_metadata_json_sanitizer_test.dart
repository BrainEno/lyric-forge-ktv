import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/timing_provenance.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_metadata_json_sanitizer.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

class _Opaque {
  @override
  String toString() => 'opaque value';
}

void main() {
  const sanitizer = LyricMetadataJsonSanitizer();

  group('values that are already JSON', () {
    test('return the same map so a normal save allocates nothing', () {
      final metadata = <String, dynamic>{
        'manuallyEditedLineIds': ['a', 'b'],
        'lyricReviewDecisions': {
          'a': {'fingerprint': '0011aabb', 'reviewedAt': '2026-11-28'},
        },
        'similarity': 0.82,
        'timed': true,
        'offsetMs': -120,
        'note': null,
      };

      expect(sanitizer.isJsonSafe(metadata), isTrue);
      expect(identical(sanitizer.sanitize(metadata), metadata), isTrue);
    });

    test('return the same document', () {
      const document = LyricDocument(
        language: 'zh',
        lines: [],
        metadata: {'source': 'reference-alignment'},
      );

      expect(identical(sanitizer.sanitizeDocument(document), document), isTrue);
    });
  });

  group('values without a JSON form', () {
    test('a set becomes a list in iteration order', () {
      final result = sanitizer.sanitize({
        'ids': <String>{'b', 'a'},
      });

      expect(result['ids'], ['b', 'a']);
      expect(() => jsonEncode(result), returnsNormally);
    });

    test('enums, durations and dates become their JSON spelling', () {
      final result = sanitizer.sanitize({
        'timingProvenance': {
          'line-1': LyricTimingProvenance.forcedAlignmentReference,
        },
        'offset': const Duration(milliseconds: 1500),
        'appliedAt': DateTime.utc(2026, 11, 28, 10, 30),
      });

      expect(result['timingProvenance'], {
        'line-1': 'forcedAlignmentReference',
      });
      expect(result['offset'], 1500);
      expect(result['appliedAt'], '2026-11-28T10:30:00.000Z');
      expect(() => jsonEncode(result), returnsNormally);
    });

    test('non-finite numbers are dropped, finite ones kept', () {
      final result = sanitizer.sanitize({
        'similarity': double.nan,
        'coverage': double.infinity,
        'scores': [0.5, double.negativeInfinity, 0.25],
        'kept': 0.75,
      });

      expect(result.containsKey('similarity'), isFalse);
      expect(result.containsKey('coverage'), isFalse);
      expect(result['scores'], [0.5, 0.25]);
      expect(result['kept'], 0.75);
      expect(() => jsonEncode(result), returnsNormally);
    });

    test('map keys become strings', () {
      final result = sanitizer.sanitize({
        'byIndex': {3: 'third', 7: 'seventh'},
      });

      expect(result['byIndex'], {'3': 'third', '7': 'seventh'});
    });

    test('any other object is kept readable as its text', () {
      final result = sanitizer.sanitize({'engine': _Opaque()});

      expect(result['engine'], 'opaque value');
      expect(() => jsonEncode(result), returnsNormally);
    });

    test('nested values are converted at any depth', () {
      final run = <String, dynamic>{
        'ids': <String>{'x'},
        'took': const Duration(seconds: 2),
      };

      final result = sanitizer.sanitize({
        'runs': [run],
      });

      final converted = (result['runs'] as List<dynamic>).single as Map;
      expect(converted['ids'], ['x']);
      expect(converted['took'], 2000);
    });

    test('a document keeps its lines and gets safe metadata', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [
          LyricLine(
            id: 'a',
            text: '月亮代表我的心',
            startTime: Duration.zero,
            endTime: const Duration(seconds: 3),
          ),
        ],
        metadata: {
          'ids': <String>{'a'},
        },
      );

      final sanitized = sanitizer.sanitizeDocument(document);

      expect(identical(sanitized, document), isFalse);
      expect(sanitized.lines, same(document.lines));
      expect(sanitized.metadata['ids'], ['a']);
      expect(() => jsonEncode(sanitized.toJson()), returnsNormally);
    });
  });
}
