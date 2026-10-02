import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/high_quality_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

void main() {
  group('HighQualityTranscriptionService', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('lyric_forge_asr_');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('keeps Qwen result when Whisper second opinion fails', () async {
      final primaryResult = _result(
        LyricLine(
          text: '你好世界',
          startTime: const Duration(seconds: 1),
          endTime: const Duration(seconds: 3),
          confidence: 92,
        ),
      );

      final service = HighQualityTranscriptionService(
        primary: _FakeTranscriptionService(result: primaryResult),
        fallback: _FakeTranscriptionService(
          error: const TranscriptionException('Whisper unavailable'),
        ),
      );

      final result = await service.transcribe(
        _request(tempDirectory.path),
      );

      expect(result.lyrics.lines.single.text, '你好世界');
      expect(result.lyrics.metadata['fallbackStatus'], 'failed');
      expect(
        result.lyrics.metadata['fallbackError'],
        contains('Whisper unavailable'),
      );

      await service.dispose();
    });

    test('replaces only clearly weak Qwen text and preserves Qwen timing',
        () async {
      final primaryResult = _result(
        LyricLine(
          text: 'hello hello hello hello',
          startTime: const Duration(seconds: 10),
          endTime: const Duration(seconds: 13),
          confidence: 35,
        ),
      );

      final fallbackResult = _result(
        LyricLine(
          text: 'yellow submarine',
          startTime: const Duration(milliseconds: 10100),
          endTime: const Duration(milliseconds: 12900),
          confidence: 92,
        ),
      );

      final service = HighQualityTranscriptionService(
        primary: _FakeTranscriptionService(result: primaryResult),
        fallback: _FakeTranscriptionService(result: fallbackResult),
      );

      final result = await service.transcribe(
        _request(tempDirectory.path),
      );

      final line = result.lyrics.lines.single;
      expect(line.text, 'yellow submarine');
      expect(line.startTime, const Duration(seconds: 10));
      expect(line.endTime, const Duration(seconds: 13));
      expect(result.lyrics.metadata['fallbackStatus'], 'completed');
      expect(result.lyrics.metadata['fallbackAppliedCount'], 1);

      await service.dispose();
    });
  });
}

TranscriptionRequest _request(String outputDirectory) {
  return TranscriptionRequest(
    inputAudioPath: 'unused-by-fake.wav',
    outputDirectory: outputDirectory,
    config: const TranscriptionConfig(
      mode: TranscriptionMode.highestQuality,
      qwenExecutable: 'qwen3-asr',
      whisperExecutable: 'whisper-cli',
      modelPath: 'ggml-large-v3.bin',
    ),
  );
}

TranscriptionResult _result(LyricLine line) {
  return TranscriptionResult(
    lyrics: LyricDocument(
      language: 'auto',
      lines: [line],
      metadata: const {'draft': true},
    ),
    normalizedAudioPath: 'normalized.wav',
    rawJsonPath: 'result.json',
    detectedLanguage: 'auto',
  );
}

class _FakeTranscriptionService implements TranscriptionService {
  final TranscriptionResult? result;
  final TranscriptionException? error;
  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();

  _FakeTranscriptionService({
    this.result,
    this.error,
  });

  @override
  bool get isRunning => false;

  @override
  Stream<TranscriptionProgress> get progressStream =>
      _progressController.stream;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    final failure = error;
    if (failure != null) throw failure;

    final value = result;
    if (value == null) {
      throw const TranscriptionException('Fake result not configured');
    }
    return value;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    await _progressController.close();
  }
}
