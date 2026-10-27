import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_model_identity.dart';

void main() {
  group('TranscriptionModelIdentity', () {
    test('recognizes Qwen ASR variants from Hugging Face model IDs', () {
      expect(
        TranscriptionModelIdentity.qwenAsrEngine('Qwen/Qwen3-ASR-1.7B'),
        'qwen3-asr-1.7b',
      );
      expect(
        TranscriptionModelIdentity.qwenAsrEngine('Qwen/Qwen3-ASR-0.6B'),
        'qwen3-asr-0.6b',
      );
      expect(
        TranscriptionModelIdentity.qwenAsrLabel('Qwen/Qwen3-ASR-1.7B'),
        'Qwen3-ASR 1.7B',
      );
    });

    test(
      'recognizes configured ForcedAligner revision rather than assuming 0.6B',
      () {
        expect(
          TranscriptionModelIdentity.qwenAlignerEngine(
            'D:\\models\\Qwen3-ForcedAligner-1.5B',
          ),
          'qwen3-forced-aligner-1.5b',
        );
        expect(
          TranscriptionModelIdentity.qwenAlignerLabel(
            'D:\\models\\Qwen3-ForcedAligner-1.5B',
          ),
          'Qwen3-ForcedAligner 1.5B',
        );
      },
    );

    test('maps the actual Whisper model filename to an engine identity', () {
      expect(
        TranscriptionModelIdentity.whisperEngine(r'D:\models\ggml-medium.bin'),
        'whisper.cpp-medium',
      );
      expect(
        TranscriptionModelIdentity.whisperLabel(r'D:\models\ggml-large-v3.bin'),
        'Whisper large-v3',
      );
    });

    test('retains custom model names without persisting absolute paths', () {
      expect(
        TranscriptionModelIdentity.qwenAsrEngine(
          r'C:\private\models\my-custom-qwen',
        ),
        'qwen3-asr-my-custom-qwen',
      );
      expect(
        TranscriptionModelIdentity.qwenAsrLabel(
          r'C:\private\models\Qwen3-ASR-1.7B',
        ),
        'Qwen3-ASR 1.7B',
      );
      expect(TranscriptionModelIdentity.qwenAsrLabel(''), 'Qwen3-ASR 1.7B');
    });
  });
}
