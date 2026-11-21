import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/file_batch_transcription_queue.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

// D-049: a running queue item shows the step of the run before the engine's
// message, and the run's own forward-only progress.

void main() {
  test('a tagged event reads as its step', () {
    const event = TranscriptionProgress(
      stage: TranscriptionStage.transcribing,
      progress: 0.1,
      message: 'Whisper 识别中',
      step: TranscriptionRunStep.recognizing,
      overall: 0.31,
    );
    expect(queueProgressMessage(event), '第 3/6 步 · 识别歌词：Whisper 识别中');
    expect(event.displayFraction, 0.31);
  });

  test('a tagged event without a message still names the step', () {
    const event = TranscriptionProgress(
      stage: TranscriptionStage.parsing,
      progress: 0,
      message: '',
      step: TranscriptionRunStep.saving,
      overall: 0.98,
    );
    expect(queueProgressMessage(event), '第 6/6 步 · 保存');
  });

  test('an untagged event is shown as it is', () {
    const event = TranscriptionProgress(
      stage: TranscriptionStage.transcribing,
      progress: 0.5,
      message: 'fake progress',
    );
    expect(queueProgressMessage(event), 'fake progress');
    expect(event.displayFraction, 0.5);
  });
}
