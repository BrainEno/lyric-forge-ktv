import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/independent_asr_evidence.dart';

const chunkAudioHash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, dynamic> chunkAuditFixture(String sourceHash) {
  Map<String, dynamic> pair(String primaryText, String secondaryText) =>
      IndependentAsrEvidence(
        capturedAt: DateTime.utc(2026, 11, 7),
        sourceAudioSha256: chunkAudioHash,
        primary: IndependentAsrTranscript(
          engine: 'qwen3-asr-1.7b',
          document: LyricDocument(language: 'en', lines: [
            LyricLine(text: primaryText, startTime: const Duration(milliseconds: 500), endTime: const Duration(milliseconds: 1500)),
          ]),
        ),
        secondary: IndependentAsrTranscript(
          engine: 'whisper.cpp-large-v3',
          document: LyricDocument(language: 'en', lines: [
            LyricLine(text: secondaryText, startTime: const Duration(milliseconds: 750), endTime: const Duration(milliseconds: 1750)),
          ]),
        ),
      ).toJson();
  return {
    'schemaVersion': 1,
    'scope': 'completeChunkPlan',
    'sourceAudioSha256': sourceHash,
    'durationMs': 4000,
    'chunkDurationMs': 3000,
    'overlapMs': 1000,
    'chunks': <dynamic>[
      <String, dynamic>{'index': 0, 'startMs': 0, 'endMs': 3000, 'evidence': pair('first primary', 'first secondary')},
      <String, dynamic>{'index': 1, 'startMs': 2000, 'endMs': 4000, 'evidence': pair('second primary', 'second secondary')},
    ],
  };
}
