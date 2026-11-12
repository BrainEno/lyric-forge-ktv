import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_evidence_audio_verifier.dart';

import 'chunk_audit_fixtures.dart';

void main() {
  const verifier = AsrEvidenceAudioVerifier();
  late Directory directory;
  late File audio;
  final bytes = List<int>.generate(10000, (index) => index % 251);
  final hash = sha256.convert(bytes).toString();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chunk-audio-verifier-');
    audio = File('${directory.path}/song.wav');
    await audio.writeAsBytes(bytes);
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'complete chunk evidence matches full source bytes, not chunk WAV hash',
    () async {
      expect(
        await verifier.verify(
          rawEvidence: chunkAuditFixture(hash),
          currentAudioPath: audio.path,
        ),
        AsrEvidenceAudioStatus.audioMatches,
      );
      expect(
        await verifier.verify(
          rawEvidence: chunkAuditFixture(chunkAudioHash),
          currentAudioPath: audio.path,
        ),
        AsrEvidenceAudioStatus.audioChanged,
      );
    },
  );

  test(
    'different source contents and missing paths are distinguished',
    () async {
      final raw = chunkAuditFixture(hash);
      await audio.writeAsBytes(List<int>.filled(bytes.length, 1));
      expect(
        await verifier.verify(rawEvidence: raw, currentAudioPath: audio.path),
        AsrEvidenceAudioStatus.audioChanged,
      );
      expect(
        await verifier.verify(rawEvidence: raw, currentAudioPath: null),
        AsrEvidenceAudioStatus.audioUnavailable,
      );
      expect(
        await verifier.verify(rawEvidence: raw, currentAudioPath: ''),
        AsrEvidenceAudioStatus.audioUnavailable,
      );
      await audio.delete();
      expect(
        await verifier.verify(rawEvidence: raw, currentAudioPath: audio.path),
        AsrEvidenceAudioStatus.audioUnavailable,
      );
    },
  );

  test(
    'unverified, incomplete or malformed plans do not reach file hashing',
    () async {
      final mutations = <void Function(Map<String, dynamic>)>[
        (raw) => raw.remove('sourceAudioSha256'),
        (raw) => raw['sourceAudioSha256'] = null,
        (raw) => raw['sourceAudioSha256'] = 'not-a-hash',
        (raw) => (raw['chunks'] as List).removeLast(),
        (raw) => (raw['chunks'] as List)[1]['index'] = 99,
        (raw) => (raw['chunks'] as List)[1]['evidence'] = null,
        (raw) => raw['scope'] = 'chunk',
        (raw) => raw['schemaVersion'] = 999,
      ];
      for (final mutate in mutations) {
        final raw = chunkAuditFixture(hash);
        mutate(raw);
        expect(
          await verifier.verify(rawEvidence: raw, currentAudioPath: audio.path),
          AsrEvidenceAudioStatus.invalidEvidence,
        );
      }
    },
  );

  test(
    'source copies with identical bytes are verified independent of path',
    () async {
      final copy = File('${directory.path}/copy.wav');
      await copy.writeAsBytes(bytes);
      final raw = chunkAuditFixture(hash);
      expect(
        await verifier.verify(rawEvidence: raw, currentAudioPath: copy.path),
        AsrEvidenceAudioStatus.audioMatches,
      );
      await copy.writeAsBytes([1, 2]);
      expect(
        await verifier.verify(rawEvidence: raw, currentAudioPath: copy.path),
        AsrEvidenceAudioStatus.audioChanged,
      );
    },
  );

  test('chunk metadata cannot masquerade as single-input evidence', () async {
    final raw = chunkAuditFixture(hash);
    raw['scope'] = 'singleInput';
    expect(
      await verifier.verify(rawEvidence: raw, currentAudioPath: audio.path),
      AsrEvidenceAudioStatus.invalidEvidence,
    );
  });
}
