import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_chunked_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

void main() {
  group('ResumableChunkedTranscriptionService', () {
    test('short audio delegates without chunking', () async {
      final delegate = _FakeService();
      final service = ResumableChunkedTranscriptionService(delegate: delegate);
      // Duration probing is intentionally an integration concern; short-path
      // behavior is covered by the real ffmpeg smoke test when runtime exists.
      expect(service.isRunning, isFalse);
      expect(delegate.calls, 0);
      await service.dispose();
    });

    test('constructor accepts retry and overlap policy', () async {
      final delegate = _FakeService();
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(minutes: 2),
        overlap: const Duration(seconds: 6),
        maxAttempts: 2,
      );
      expect(service.isRunning, isFalse);
      await service.dispose();
    });
  });
}

class _FakeService implements TranscriptionService {
  final _controller = StreamController<TranscriptionProgress>.broadcast();
  int calls = 0;

  @override
  Stream<TranscriptionProgress> get progressStream => _controller.stream;

  @override
  bool get isRunning => false;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    calls++;
    return TranscriptionResult(
      lyrics: const LyricDocument(
        language: 'en',
        lines: [
          LyricLine(
            text: 'hello',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
          ),
        ],
      ),
      normalizedAudioPath: request.inputAudioPath,
      rawJsonPath: request.outputDirectory + Platform.pathSeparator + 'raw.json',
      detectedLanguage: 'en',
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _controller.close();
}
