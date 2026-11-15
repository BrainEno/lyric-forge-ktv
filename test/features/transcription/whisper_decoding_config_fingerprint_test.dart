import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_chunked_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

const _base = TranscriptionConfig(
  whisperExecutable: 'whisper-cli',
  modelPath: 'ggml-large-v3.bin',
  language: 'zh',
);

const _hints = RecognitionHints(songTitle: '旧街', artist: '测试乐队');

String _fingerprint(
  TranscriptionConfig config, {
  RecognitionHints hints = RecognitionHints.none,
}) => ResumableChunkedTranscriptionService.checkpointConfigFingerprint(
  config,
  hints: hints,
);

void main() {
  group('TranscriptionConfig Whisper decoding profile', () {
    test('defaults to the lyrics profile for new configurations', () {
      expect(_base.whisperDecodingProfile, WhisperDecodingProfile.lyrics);
    });

    test('round-trips both profiles through JSON', () {
      for (final profile in WhisperDecodingProfile.values) {
        final original = _base.copyWith(whisperDecodingProfile: profile);
        final json = original.toJson();
        expect(json['whisperDecodingProfile'], profile.name);
        expect(
          TranscriptionConfig.fromJson(json).whisperDecodingProfile,
          profile,
        );
      }
    });

    test('settings saved before the profile existed load as lyrics', () {
      final json = _base.toJson()..remove('whisperDecodingProfile');
      expect(
        TranscriptionConfig.fromJson(json).whisperDecodingProfile,
        WhisperDecodingProfile.lyrics,
      );
    });

    test('an unknown stored profile name falls back to lyrics', () {
      final json = _base.toJson()..['whisperDecodingProfile'] = 'turbo-v9';
      expect(
        TranscriptionConfig.fromJson(json).whisperDecodingProfile,
        WhisperDecodingProfile.lyrics,
      );
    });

    test('copyWith keeps the profile unless it is given', () {
      final standard = _base.copyWith(
        whisperDecodingProfile: WhisperDecodingProfile.standard,
      );
      expect(
        standard.copyWith(language: 'ja').whisperDecodingProfile,
        WhisperDecodingProfile.standard,
      );
    });
  });

  group('checkpoint fingerprint covers result-affecting decoding inputs', () {
    test('is deterministic for identical inputs', () {
      expect(
        _fingerprint(_base, hints: _hints),
        _fingerprint(_base, hints: _hints),
      );
    });

    test('changes when the decoding profile changes', () {
      final standard = _base.copyWith(
        whisperDecodingProfile: WhisperDecodingProfile.standard,
      );
      expect(
        _fingerprint(standard, hints: _hints),
        isNot(_fingerprint(_base, hints: _hints)),
      );
    });

    test('changes when the hints change the lyrics prompt', () {
      final renamed = _fingerprint(
        _base,
        hints: const RecognitionHints(songTitle: '新街', artist: '测试乐队'),
      );
      final withTerm = _fingerprint(
        _base,
        hints: const RecognitionHints(
          songTitle: '旧街',
          artist: '测试乐队',
          terms: ['阿凯'],
        ),
      );
      final reference = _fingerprint(_base, hints: _hints);
      expect(renamed, isNot(reference));
      expect(withTerm, isNot(reference));
      expect(_fingerprint(_base), isNot(reference));
    });

    test('changes when the language changes the prompt template', () {
      expect(
        _fingerprint(_base.copyWith(language: 'ja'), hints: _hints),
        isNot(_fingerprint(_base, hints: _hints)),
      );
    });

    test('standard profile ignores hints because it sends no prompt', () {
      // Old checkpoints made with the pre-#448 command line stay valid
      // whatever the project card says, since nothing about them changed.
      final standard = _base.copyWith(
        whisperDecodingProfile: WhisperDecodingProfile.standard,
      );
      expect(_fingerprint(standard, hints: _hints), _fingerprint(standard));
    });

    test('hints that sanitize to the same prompt share a fingerprint', () {
      // Whitespace and video-title noise never reach whisper, so they must
      // not invalidate finished chunks either.
      expect(
        _fingerprint(
          _base,
          hints: const RecognitionHints(
            songTitle: '  旧街 (Official Video) ',
            artist: '测试乐队 ',
          ),
        ),
        _fingerprint(_base, hints: _hints),
      );
    });
  });
}
