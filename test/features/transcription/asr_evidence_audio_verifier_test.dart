import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_evidence_audio_verifier.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/independent_asr_evidence.dart';

void main() {
  const verifier = AsrEvidenceAudioVerifier();
  late Directory directory;
  late File audio;
  final original = List<int>.generate(100000, (i) => i % 256);

  Map<String, dynamic> evidence({String? hash}) {
    const document = LyricDocument(
      language: 'en',
      lines: [
        LyricLine(
          text: 'lyric',
          startTime: Duration.zero,
          endTime: Duration(seconds: 1),
        ),
      ],
    );
    return IndependentAsrEvidence(
      capturedAt: DateTime.utc(2026, 11, 7),
      sourceAudioSha256: hash,
      primary: IndependentAsrTranscript(engine: 'primary', document: document),
      secondary: IndependentAsrTranscript(
        engine: 'secondary',
        document: document,
      ),
    ).toJson();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('asr-audio-evidence-');
    audio = File('${directory.path}/song.wav');
    await audio.writeAsBytes(original);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('matches content and detects changed bytes even at same size', () async {
    final raw = evidence(hash: sha256.convert(original).toString());
    expect(
      await verifier.verify(rawEvidence: raw, currentAudioPath: audio.path),
      AsrEvidenceAudioStatus.audioMatches,
    );
    final changed = List<int>.of(original);
    changed[500] ^= 1;
    await audio.writeAsBytes(changed);
    expect(
      await verifier.verify(rawEvidence: raw, currentAudioPath: audio.path),
      AsrEvidenceAudioStatus.audioChanged,
    );
    final copy = File('${directory.path}/moved.wav');
    await copy.writeAsBytes(original);
    expect(
      await verifier.verify(rawEvidence: raw, currentAudioPath: copy.path),
      AsrEvidenceAudioStatus.audioMatches,
    );
  });

  test(
    'distinguishes old, absent, malformed and unavailable evidence',
    () async {
      final hash = sha256.convert(original).toString();
      expect(
        await verifier.verify(rawEvidence: null, currentAudioPath: audio.path),
        AsrEvidenceAudioStatus.missingEvidence,
      );
      expect(
        await verifier.verify(
          rawEvidence: {'schemaVersion': 99},
          currentAudioPath: audio.path,
        ),
        AsrEvidenceAudioStatus.invalidEvidence,
      );
      expect(
        await verifier.verify(
          rawEvidence: evidence(),
          currentAudioPath: audio.path,
        ),
        AsrEvidenceAudioStatus.unverified,
      );
      expect(
        await verifier.verify(
          rawEvidence: evidence(hash: hash),
          currentAudioPath: null,
        ),
        AsrEvidenceAudioStatus.audioUnavailable,
      );
      await audio.delete();
      expect(
        await verifier.verify(
          rawEvidence: evidence(hash: hash),
          currentAudioPath: audio.path,
        ),
        AsrEvidenceAudioStatus.audioUnavailable,
      );
      expect(
        await verifier.verify(
          rawEvidence: evidence(hash: 'not-a-hash'),
          currentAudioPath: audio.path,
        ),
        AsrEvidenceAudioStatus.invalidEvidence,
      );
    },
  );

  test('rejects a file modified while it is being hashed', () async {
    var changed = false;
    await expectLater(
      hashAsrAudioFile(
        audio.path,
        onChunk: () {
          if (changed) return;
          changed = true;
          audio.writeAsBytesSync([1, 2, 3]);
        },
      ),
      throwsA(isA<AsrAudioChangedDuringHashException>()),
    );
  });

  test(
    'streamed hashing supports interruption without hiding its error',
    () async {
      final interrupted = StateError('stop');
      await expectLater(
        hashAsrAudioFile(audio.path, onChunk: () => throw interrupted),
        throwsA(same(interrupted)),
      );
    },
  );
}
