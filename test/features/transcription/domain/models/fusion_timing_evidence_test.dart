import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/fusion_timing_evidence.dart';

void main() {
  const line = LyricLine(text: 'abc', startTime: Duration.zero, endTime: Duration(seconds: 1));
  test('uses exact UTF-8 SHA-256, not normalization', () {
    expect(FusionTimingEvidence.textHash('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(FusionTimingEvidence.textHash('歌！'), isNot(FusionTimingEvidence.textHash('歌!')));
  });
  test('rejects ambiguous, malformed and stale snapshots', () {
    final valid = FusionTimingEvidence.entry(lineIndex: 0, result: line, timedText: 'before', secondaryOnly: false);
    LyricDocument document(Object raw) => LyricDocument(language: 'en', lines: const [line], metadata: {FusionTimingEvidence.metadataKey: raw});
    expect(FusionTimingEvidence.forLine(document(FusionTimingEvidence.wrap([valid])), 0), isNotNull);
    expect(FusionTimingEvidence.forLine(document(FusionTimingEvidence.wrap([valid, valid])), 0), isNull);
    expect(FusionTimingEvidence.forLine(document(FusionTimingEvidence.wrap([{...valid, 'needsRealignment': false}])), 0), isNull);
    expect(FusionTimingEvidence.forLine(document(FusionTimingEvidence.wrap([{...valid, 'alignedTextHash': 'unverified'}])), 0), isNull);
    expect(FusionTimingEvidence.forLine(document({'version': 99, 'entries': [valid]}), 0), isNull);
    expect(FusionTimingEvidence.forLine(document(FusionTimingEvidence.wrap([valid])).copyWith(lines: const [LyricLine(text: 'abc', startTime: Duration(milliseconds: 1), endTime: Duration(seconds: 1))]), 0), isNull);
  });
}
