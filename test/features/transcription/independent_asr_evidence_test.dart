import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/independent_asr_evidence.dart';

void main() {
  Map<String, dynamic> valid() {
    final document = LyricDocument(
      language: 'ko',
      globalOffset: const Duration(milliseconds: -100),
      lines: [
        const LyricLine(
          text: '안녕 🌙',
          startTime: Duration(milliseconds: 100),
          endTime: Duration(milliseconds: 900),
          confidence: 50,
          confidenceSource: LyricConfidenceSource.unscored,
          id: 'line-1',
          isChorus: true,
        ),
      ],
      metadata: const {'rawJsonPath': '/private/should-not-leak'},
    );
    return IndependentAsrEvidence(
      capturedAt: DateTime.utc(2026, 11, 7),
      primary: IndependentAsrTranscript(engine: 'qwen', document: document),
      secondary: IndependentAsrTranscript(
        engine: 'whisper',
        document: document,
      ),
    ).toJson();
  }

  test('round trips independent text, timing, confidence and offsets', () {
    final encoded = jsonEncode(valid());
    expect(encoded, isNot(contains('/private')));
    final result = IndependentAsrEvidence.tryParse(jsonDecode(encoded))!;
    expect(result.capturedAtUtc, DateTime.utc(2026, 11, 7));
    expect(result.primary.engine, 'qwen');
    expect(result.secondary.engine, 'whisper');
    final document = result.primary.toDocument();
    expect(document.language, 'ko');
    expect(document.globalOffset, const Duration(milliseconds: -100));
    expect(document.metadata, isEmpty);
    expect(document.lines.single.text, '안녕 🌙');
    expect(document.lines.single.startTime, const Duration(milliseconds: 100));
    expect(document.lines.single.endTime, const Duration(milliseconds: 900));
    expect(
      document.lines.single.confidenceSource,
      LyricConfidenceSource.unscored,
    );
    expect(document.lines.single.id, 'line-1');
    expect(document.lines.single.isChorus, isTrue);
    expect(() => document.lines.clear(), throwsUnsupportedError);
  });

  test('snapshots do not follow mutable input line lists', () {
    final lines = [
      const LyricLine(
        text: 'first',
        startTime: Duration.zero,
        endTime: Duration(seconds: 1),
      ),
    ];
    final snapshot = IndependentAsrTranscript(
      engine: 'x',
      document: LyricDocument(language: 'en', lines: lines),
    );
    lines.clear();
    expect(snapshot.lines.single.text, 'first');
    expect(() => snapshot.lines.clear(), throwsUnsupportedError);
  });

  test('rejects unknown schemas and incomplete or malformed evidence', () {
    final cases = <Map<String, dynamic> Function()>[
      () => valid()..['schemaVersion'] = 2,
      () => valid()..['scope'] = 'chunk',
      () => valid()..['capturedAtUtc'] = 'not-a-date',
      () => valid()..['sourceAudioSha256'] = 'not-a-digest',
      () => valid()..['sourceAudioSha256'] = 123,
      () => valid()..['capturedAtUtc'] = '2026-11-07T00:00:00',
      () => valid()..['secondary'] = null,
      () =>
          valid()
            ..['primary'] = {'engine': 'qwen', 'language': 'en', 'lines': []},
      () {
        final value = valid();
        final primary = value['primary'] as Map<String, dynamic>;
        (primary['lines'] as List).first['endTime'] = 0;
        return value;
      },
      () {
        final value = valid();
        final primary = value['primary'] as Map<String, dynamic>;
        (primary['lines'] as List).first['confidenceSource'] = 'unknown';
        return value;
      },
      () {
        final value = valid();
        final primary = value['primary'] as Map<String, dynamic>;
        (primary['lines'] as List).first['confidence'] = 101;
        return value;
      },
    ];
    expect(IndependentAsrEvidence.tryParse(null), isNull);
    for (final build in cases) {
      expect(IndependentAsrEvidence.tryParse(build()), isNull);
    }
  });
}
