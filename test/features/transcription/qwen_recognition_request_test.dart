import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen3_asr_native_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/qwen_decode_budget.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/qwen_recognition_context.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/whisper_decoding_policy.dart';

void main() {
  group('qwenRecognitionContext', () {
    test('never sends the title, artist or album', () {
      // Qwen copies its context into the transcript over instrumental parts;
      // a title that is also the hook then fills the song.
      const hints = RecognitionHints(
        songTitle: 'Riders on the Storm',
        artist: 'The Doors',
        album: 'L.A. Woman',
      );
      expect(qwenRecognitionContext(hints), isEmpty);
    });

    test('sends the user terms as a plain list', () {
      const hints = RecognitionHints(
        songTitle: 'Song',
        terms: ['  Avercage ', 'Peyote', 'avercage', '', 'Ridg  way'],
      );
      expect(qwenRecognitionTerms(hints), ['Avercage', 'Peyote', 'Ridg way']);
      expect(qwenRecognitionContext(hints), 'Avercage, Peyote, Ridg way');
    });

    test('drops sentence-length entries and caps the count', () {
      final hints = RecognitionHints(
        terms: [
          'this is a whole sentence that is far too long to be a name',
          for (var i = 0; i < 20; i++) 'term$i',
        ],
      );
      final terms = qwenRecognitionTerms(hints);
      expect(terms, hasLength(maxQwenContextTerms));
      expect(terms.first, 'term0');
    });
  });

  group('transcribeRequestBody', () {
    test('always asks for short chunks with a one-chunk budget', () {
      final body = Qwen3AsrNativeTranscriptionService.transcribeRequestBody(
        audioPath: '/tmp/in.wav',
        language: 'English',
        context: '',
        chunk: qwenRecognitionChunk,
        maxNewTokens: qwenMaxNewTokensFor(const Duration(minutes: 7)),
      );
      expect(body['chunk_max_sec'], 30);
      expect(body['max_new_tokens'], 368);
      expect(body['return_timestamps'], isTrue);
      expect(body['language'], 'English');
      expect(body.containsKey('context'), isFalse);
    });

    test('sends a context only when there is one, and omits auto language', () {
      final body = Qwen3AsrNativeTranscriptionService.transcribeRequestBody(
        audioPath: '/tmp/in.wav',
        language: null,
        context: ' Avercage ',
        chunk: const Duration(minutes: 30),
        maxNewTokens: 1568,
      );
      expect(body['context'], 'Avercage');
      expect(body.containsKey('language'), isFalse);
      expect(body['chunk_max_sec'], 180);
    });
  });

  group('isUnalignableChunkFailure', () {
    test('recognises the runtime aligner rejecting a punctuation chunk', () {
      const error = TranscriptionException(
        'Qwen3-ASR 返回 HTTP 500',
        details: '{"error":"tokenized word_list is empty"}',
        kind: TranscriptionFailureKind.environment,
      );
      expect(
        Qwen3AsrNativeTranscriptionService.isUnalignableChunkFailure(error),
        isTrue,
      );
    });

    test('other failures and cancellation are not retried', () {
      expect(
        Qwen3AsrNativeTranscriptionService.isUnalignableChunkFailure(
          const TranscriptionException.environment(
            'Qwen3-ASR 返回 HTTP 500',
            details: 'out of memory',
          ),
        ),
        isFalse,
      );
      expect(
        Qwen3AsrNativeTranscriptionService.isUnalignableChunkFailure(
          const TranscriptionException.cancelled(
            '歌词识别已取消',
            details: 'word_list is empty',
          ),
        ),
        isFalse,
      );
    });
  });
}
