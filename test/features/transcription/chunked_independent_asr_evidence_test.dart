import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/chunked_independent_asr_evidence.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/independent_asr_evidence.dart';

const sourceHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const chunkHash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

LyricLine line(String text, int start, int end) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: start),
  endTime: Duration(milliseconds: end),
);

Map<String, dynamic> pair({
  String? hash = chunkHash,
  String primaryEngine = 'qwen3-asr-1.7b',
  String secondaryEngine = 'whisper.cpp-large-v3',
  String primaryLanguage = 'en',
  String secondaryLanguage = 'en',
  List<LyricLine>? primary,
  List<LyricLine>? secondary,
  Duration? offset,
}) => IndependentAsrEvidence(
  capturedAt: DateTime.utc(2026, 11, 7),
  sourceAudioSha256: hash,
  primary: IndependentAsrTranscript(
    engine: primaryEngine,
    document: LyricDocument(language: primaryLanguage, lines: primary ?? [line('primary', 0, 1000)], globalOffset: offset),
  ),
  secondary: IndependentAsrTranscript(
    engine: secondaryEngine,
    document: LyricDocument(language: secondaryLanguage, lines: secondary ?? [line('secondary', 500, 1500)]),
  ),
).toJson();

Map<String, dynamic> fixture() => {
  'schemaVersion': 1,
  'scope': 'completeChunkPlan',
  'sourceAudioSha256': sourceHash,
  'durationMs': 4000,
  'chunkDurationMs': 3000,
  'overlapMs': 1000,
  'chunks': [
    {'index': 0, 'startMs': 0, 'endMs': 3000, 'evidence': pair()},
    {'index': 1, 'startMs': 2000, 'endMs': 4000, 'evidence': pair()},
  ],
};

Map<String, dynamic> clone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

List<dynamic> chunks(Map<String, dynamic> raw) => raw['chunks'] as List;
Map<String, dynamic> chunk(Map<String, dynamic> raw, int i) => chunks(raw)[i] as Map<String, dynamic>;
Map<String, dynamic> evidence(Map<String, dynamic> raw, int i) => chunk(raw, i)['evidence'] as Map<String, dynamic>;

void main() {
  group('complete chunk snapshot schema', () {
    test('round-trips a complete plan with original local timestamps', () {
      final raw = fixture();
      final parsed = ChunkedIndependentAsrEvidence.tryParse(raw)!;
      expect(parsed.sourceAudioSha256, sourceHash);
      expect(parsed.duration, const Duration(seconds: 4));
      expect(parsed.chunkDuration, const Duration(seconds: 3));
      expect(parsed.overlap, const Duration(seconds: 1));
      expect(parsed.chunks, hasLength(2));
      expect(parsed.chunks.first.start, Duration.zero);
      expect(parsed.chunks.last.start, const Duration(seconds: 2));
      expect(parsed.chunks.last.end, const Duration(seconds: 4));
      expect(parsed.toJson(), raw);
      expect(() => parsed.chunks.clear(), throwsUnsupportedError);
      expect(() => parsed.chunks.first.evidence.primary.lines.clear(), throwsUnsupportedError);
    });

    test('shifts each original transcript independently without deduplication', () {
      final raw = fixture();
      final parsed = ChunkedIndependentAsrEvidence.tryParse(raw)!;
      final second = parsed.chunks.last;
      final original = second.evidence.secondary.lines.single;
      final shifted = second.globalTranscript(primary: false).lines.single;
      expect(original.startTime, const Duration(milliseconds: 500));
      expect(original.endTime, const Duration(milliseconds: 1500));
      expect(shifted.startTime, const Duration(milliseconds: 2500));
      expect(shifted.endTime, const Duration(milliseconds: 3500));
      expect(shifted.text, original.text);
      expect(second.globalTranscript(primary: true).lines.single.startTime, const Duration(seconds: 2));
      expect(parsed.chunks.first.globalTranscript(primary: false).lines.single.startTime, const Duration(milliseconds: 500));
      expect(parsed.toJson(), raw);
    });

    test('permits either independent engine order consistently', () {
      final raw = fixture();
      for (final item in chunks(raw)) {
        (item as Map)['evidence'] = pair(primaryEngine: 'whisper.cpp-large-v3', secondaryEngine: 'qwen3-asr-1.7b');
      }
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNotNull);
    });

    test('rejects malformed headers and unknown schema or scope', () {
      final mutations = <void Function(Map<String, dynamic>)>[
        (r) => r.remove('schemaVersion'),
        (r) => r['schemaVersion'] = 2,
        (r) => r['scope'] = 'singleInput',
        (r) => r['scope'] = 'chunk',
        (r) => r.remove('scope'),
        (r) => r['sourceAudioSha256'] = null,
        (r) => r['sourceAudioSha256'] = 'A' * 64,
        (r) => r['sourceAudioSha256'] = 'bad',
        (r) => r['durationMs'] = 4000.0,
        (r) => r['durationMs'] = 0,
        (r) => r['chunkDurationMs'] = 0,
        (r) => r['chunkDurationMs'] = 4000,
        (r) => r['overlapMs'] = -1,
        (r) => r['overlapMs'] = 3000,
        (r) => r['chunks'] = null,
        (r) => r['chunks'] = [],
      ];
      expect(ChunkedIndependentAsrEvidence.tryParse(null), isNull);
      expect(ChunkedIndependentAsrEvidence.tryParse([]), isNull);
      for (var i = 0; i < mutations.length; i++) {
        final raw = fixture();
        mutations[i](raw);
        expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull, reason: 'header mutation $i');
      }
    });

    test('rejects missing, reordered, duplicated, extra, or malformed chunks', () {
      final variants = [
        (Map<String, dynamic> r) => chunks(r).removeLast(),
        (Map<String, dynamic> r) => chunks(r).removeAt(0),
        (Map<String, dynamic> r) => chunks(r).insert(0, chunks(r).last),
        (Map<String, dynamic> r) => chunks(r).add(clone(chunk(r, 1))),
        (Map<String, dynamic> r) => chunks(r)[0] = null,
        (Map<String, dynamic> r) => chunk(r, 1)['index'] = 0,
        (Map<String, dynamic> r) => chunk(r, 0)['index'] = '0',
        (Map<String, dynamic> r) => chunk(r, 1)['startMs'] = 2001,
        (Map<String, dynamic> r) => chunk(r, 1)['startMs'] = 3000,
        (Map<String, dynamic> r) => chunk(r, 0)['endMs'] = 2999,
        (Map<String, dynamic> r) => chunk(r, 1)['endMs'] = 3999,
        (Map<String, dynamic> r) => chunk(r, 1)['endMs'] = 4001,
      ];
      for (var i = 0; i < variants.length; i++) {
        final raw = fixture();
        variants[i](raw);
        expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull, reason: 'plan mutation $i');
      }
    });

    test('accepts touching chunks when configured overlap is zero', () {
      final raw = fixture();
      raw['overlapMs'] = 0;
      chunk(raw, 1)['startMs'] = 3000;
      chunk(raw, 1)['evidence'] = pair(secondary: [line('last', 0, 1000)]);
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNotNull);
    });

    test('retains repeated overlap lines as separate invocations', () {
      final raw = fixture();
      chunk(raw, 0)['evidence'] = pair(primary: [line('repeat', 2000, 3000)]);
      chunk(raw, 1)['evidence'] = pair(primary: [line('repeat', 0, 1000)]);
      final parsed = ChunkedIndependentAsrEvidence.tryParse(raw)!;
      final first = parsed.chunks.first.globalTranscript(primary: true).lines.single;
      final second = parsed.chunks.last.globalTranscript(primary: true).lines.single;
      expect(first.startTime, second.startTime);
      expect(first.endTime, second.endTime);
      expect(parsed.chunks, hasLength(2));
    });

    test('rejects absent chunk audio hashes and malformed evidence', () {
      final variants = [
        (Map<String, dynamic> r) => evidence(r, 0).remove('sourceAudioSha256'),
        (Map<String, dynamic> r) => evidence(r, 1)['sourceAudioSha256'] = 'invalid',
        (Map<String, dynamic> r) => chunk(r, 0)['evidence'] = null,
        (Map<String, dynamic> r) => evidence(r, 0)['scope'] = 'completeChunkPlan',
        (Map<String, dynamic> r) => evidence(r, 1)['schemaVersion'] = 99,
        (Map<String, dynamic> r) => evidence(r, 0)['capturedAtUtc'] = 'invalid',
      ];
      for (var i = 0; i < variants.length; i++) {
        final raw = fixture();
        variants[i](raw);
        expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull, reason: 'evidence mutation $i');
      }
    });

    test('rejects same, unknown, malformed or inconsistent engines', () {
      final cases = [
        pair(primaryEngine: 'qwen3-asr-1.7b', secondaryEngine: 'qwen3-asr-1.7b'),
        pair(primaryEngine: 'unknown', secondaryEngine: 'whisper.cpp-large-v3'),
        pair(primaryEngine: 'qwen3-asr-/path', secondaryEngine: 'whisper.cpp-large-v3'),
        pair(primaryEngine: 'qwen3-asr-1.7b', secondaryEngine: 'whisper.cpp-tiny'),
        pair(primaryEngine: 'whisper.cpp-large-v3', secondaryEngine: 'qwen3-asr-1.7b'),
      ];
      for (final replacement in cases) {
        final raw = fixture();
        chunk(raw, 1)['evidence'] = replacement;
        expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
      }
    });

    test('rejects language changes and nonzero transcript offsets', () {
      for (final replacement in [
        pair(primaryLanguage: 'zh'),
        pair(secondaryLanguage: 'zh'),
        pair(offset: const Duration(milliseconds: 1)),
        pair(offset: const Duration(milliseconds: -1)),
      ]) {
        final raw = fixture();
        chunk(raw, 1)['evidence'] = replacement;
        expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
      }
    });

    test('rejects out-of-bounds, blank, unordered and invalid lines', () {
      final replacements = [
        pair(primary: [line('beyond', 0, 2001)]),
        pair(secondary: [line('beyond', 0, 2001)]),
        pair(primary: [line('blank', 1000, 1500), line('earlier', 0, 500)]),
        pair(primary: [line('  ', 0, 500)]),
        pair(primary: [line('negative', -1, 100)]),
        pair(primary: [line('zero', 10, 10)]),
        pair(primary: []),
        pair(secondary: []),
      ];
      for (final replacement in replacements) {
        final raw = fixture();
        chunk(raw, 1)['evidence'] = replacement;
        expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
      }
    });

    test('accepts a segment ending exactly at its chunk boundary', () {
      final raw = fixture();
      chunk(raw, 1)['evidence'] = pair(primary: [line('last', 1000, 2000)]);
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNotNull);
    });

    test('rejects excessive per-transcript lines before emitting any evidence', () {
      final raw = fixture();
      final tooMany = List.generate(ChunkedIndependentAsrEvidence.maxLinesPerTranscript + 1, (i) => line('x', 0, 1));
      chunk(raw, 1)['evidence'] = pair(primary: tooMany);
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
    });

    test('rejects excessive chunk counts before walking content', () {
      final raw = fixture();
      raw['chunks'] = List.filled(ChunkedIndependentAsrEvidence.maxChunks + 1, null);
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
    });

    test('parsing detaches results from later JSON mutation', () {
      final raw = fixture();
      final result = ChunkedIndependentAsrEvidence.tryParse(raw)!;
      final initial = result.toJson();
      chunk(raw, 0)['startMs'] = 123;
      evidence(raw, 0)['primary']['lines'][0]['text'] = 'changed';
      expect(result.toJson(), initial);
    });

    test('three-chunk plan retains every original invocation', () {
      final raw = fixture();
      raw['durationMs'] = 6000;
      chunk(raw, 1)['endMs'] = 5000;
      chunks(raw).add({'index': 2, 'startMs': 4000, 'endMs': 6000, 'evidence': pair()});
      final parsed = ChunkedIndependentAsrEvidence.tryParse(raw)!;
      expect(parsed.chunks.map((item) => item.start.inMilliseconds), [0, 2000, 4000]);
      expect(parsed.chunks.map((item) => item.end.inMilliseconds), [3000, 5000, 6000]);
      expect(parsed.chunks.last.globalTranscript(primary: true).lines.single.startTime, const Duration(seconds: 4));
    });

    test('extra chunk after the final boundary is rejected', () {
      final raw = fixture();
      chunks(raw).add({'index': 2, 'startMs': 4000, 'endMs': 4000, 'evidence': pair()});
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
    });

    test('partial tail is never treated as a complete plan', () {
      final raw = fixture();
      raw['durationMs'] = 5000;
      chunk(raw, 1)['endMs'] = 5000;
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNotNull);
      raw['durationMs'] = 5001;
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
    });

    test('numeric lookalikes cannot masquerade as integer plan fields', () {
      for (final name in ['index', 'startMs', 'endMs']) {
        final raw = fixture();
        chunk(raw, 0)[name] = (chunk(raw, 0)[name] as int).toDouble();
        expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull, reason: name);
      }
      final raw = fixture()..['schemaVersion'] = 1.0;
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
    });

    test('unreasonably long source duration is rejected before math', () {
      final raw = fixture()..['durationMs'] = ChunkedIndependentAsrEvidence.maxDurationMs + 1;
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
    });

    test('text size limit counts Unicode code points, not UTF-16 units', () {
      final raw = fixture();
      final n = ChunkedIndependentAsrEvidence.maxTextRunesPerLine;
      chunk(raw, 1)['evidence'] = pair(primary: [line('🎵' * n, 0, 1)]);
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNotNull);
      chunk(raw, 1)['evidence'] = pair(primary: [line('🎵' * (n + 1), 0, 1)]);
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
    });

    test('secondary offset is also rejected', () {
      final raw = fixture();
      final rawSecondary = evidence(raw, 1)['secondary'] as Map;
      rawSecondary['globalOffsetMs'] = 100;
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
    });

    test('total line budget applies across the entire plan', () {
      final raw = fixture();
      raw['durationMs'] = 14000;
      chunks(raw).clear();
      final many = List.generate(1800, (i) => line('x', 0, 1));
      for (var i = 0; i < 7; i++) {
        chunks(raw).add({
          'index': i,
          'startMs': i * 2000,
          'endMs': i == 6 ? 14000 : i * 2000 + 3000,
          'evidence': pair(primary: many, secondary: many),
        });
      }
      expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
    });

    test('global conversion preserves confidence, IDs and chorus labels', () {
      final raw = fixture();
      final special = LyricLine(
        id: 'stable', text: 'word', startTime: Duration.zero,
        endTime: const Duration(seconds: 1), isChorus: true,
        confidence: 42, confidenceSource: LyricConfidenceSource.heuristic,
      );
      chunk(raw, 1)['evidence'] = pair(primary: [special]);
      final shifted = ChunkedIndependentAsrEvidence.tryParse(raw)!
          .chunks.last.globalTranscript(primary: true).lines.single;
      expect(shifted.id, 'stable');
      expect(shifted.isChorus, isTrue);
      expect(shifted.confidence, 42);
      expect(shifted.confidenceSource, LyricConfidenceSource.heuristic);
      expect(shifted.startTime, const Duration(seconds: 2));
      expect(shifted.endTime, const Duration(seconds: 3));
    });

    test('all small complete plans have a strict exact boundary representation', () {
      for (final overlap in [0, 250, 500]) {
        for (final duration in [2001, 2500, 4000, 5500]) {
          const length = 2000;
          final step = length - overlap;
          final items = <Map<String, dynamic>>[];
          for (var start = 0; start < duration; start += step) {
            final end = start + length < duration ? start + length : duration;
            items.add({'index': items.length, 'startMs': start, 'endMs': end,
              'evidence': pair(primary: [line('a', 0, 1)], secondary: [line('b', 0, 1)])});
            if (end == duration) break;
          }
          final raw = fixture()
            ..['durationMs'] = duration
            ..['chunkDurationMs'] = length
            ..['overlapMs'] = overlap
            ..['chunks'] = items;
          final parsed = ChunkedIndependentAsrEvidence.tryParse(raw);
          expect(parsed, isNotNull, reason: 'duration=$duration overlap=$overlap');
          expect(parsed!.chunks.last.end.inMilliseconds, duration);
          chunk(raw, items.length - 1)['endMs'] = duration - 1;
          expect(ChunkedIndependentAsrEvidence.tryParse(raw), isNull);
        }
      }
    });
  });
}
