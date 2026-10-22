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

    test('surfaces Ashin versus passion as a review candidate without auto-applying', () async {
      final primaryResult = _result(
        LyricLine(
          text: 'Ashin lady',
          startTime: const Duration(seconds: 10),
          endTime: const Duration(seconds: 13),
          confidence: 92,
        ),
      );
      final fallbackResult = _result(
        LyricLine(
          text: 'passion lady',
          startTime: const Duration(milliseconds: 10100),
          endTime: const Duration(milliseconds: 12900),
          confidence: 92,
        ),
      );
      final service = HighQualityTranscriptionService(
        primary: _FakeTranscriptionService(result: primaryResult),
        fallback: _FakeTranscriptionService(result: fallbackResult),
      );

      final result = await service.transcribe(_request(tempDirectory.path));
      final metadata = result.lyrics.metadata;
      final candidates = metadata['fallbackCandidates'] as List;
      final candidate = Map<String, dynamic>.from(candidates.single as Map);

      expect(result.lyrics.lines.single.text, 'Ashin lady');
      expect(metadata['fallbackCandidateCount'], 1);
      expect(metadata['fallbackAppliedCount'], 0);
      expect(candidate['alternativeText'], 'passion lady');
      expect(candidate['reason'], 'engine_disagreement_review');
      expect(candidate['similarity'], closeTo(8 / 11, 0.001));

      await service.dispose();
    });

    test('surfaces the same disagreement when Whisper is primary', () async {
      final whisperResult = _result(
        LyricLine(
          text: 'passion lady',
          startTime: const Duration(seconds: 10),
          endTime: const Duration(seconds: 13),
          confidence: 92,
        ),
      );
      final qwenResult = _result(
        LyricLine(
          text: 'Ashin lady',
          startTime: const Duration(milliseconds: 10100),
          endTime: const Duration(milliseconds: 12900),
          confidence: 92,
        ),
      );
      final service = HighQualityTranscriptionService(
        primary: _FakeTranscriptionService(result: qwenResult),
        fallback: _FakeTranscriptionService(result: whisperResult),
      );

      final result = await service.transcribe(
        _request(
          tempDirectory.path,
          engineOrder: TranscriptionEngineOrder.whisperPrimary,
        ),
      );
      final metadata = result.lyrics.metadata;
      final candidates = metadata['fallbackCandidates'] as List;
      final candidate = Map<String, dynamic>.from(candidates.single as Map);

      expect(result.lyrics.lines.single.text, 'passion lady');
      expect(metadata['fallbackCandidateCount'], 1);
      expect(metadata['fallbackAppliedCount'], 0);
      expect(candidate['alternativeText'], 'Ashin lady');
      expect(candidate['reason'], 'engine_disagreement_review');

      await service.dispose();
    });

    test('uses Whisper primary and Qwen second opinion on Intel Mac',
        () async {
      final qwenResult = _result(
        LyricLine(
          text: 'yellow submarine',
          startTime: const Duration(milliseconds: 10100),
          endTime: const Duration(milliseconds: 12900),
          confidence: 92,
        ),
      );

      final whisperResult = _result(
        LyricLine(
          text: 'hello hello hello hello',
          startTime: const Duration(seconds: 10),
          endTime: const Duration(seconds: 13),
          confidence: 35,
        ),
      );

      final service = HighQualityTranscriptionService(
        primary: _FakeTranscriptionService(result: qwenResult),
        fallback: _FakeTranscriptionService(result: whisperResult),
      );

      final result = await service.transcribe(
        _request(
          tempDirectory.path,
          engineOrder: TranscriptionEngineOrder.whisperPrimary,
        ),
      );

      final line = result.lyrics.lines.single;
      expect(line.text, 'yellow submarine');
      expect(line.startTime, const Duration(seconds: 10));
      expect(line.endTime, const Duration(seconds: 13));
      expect(result.lyrics.metadata['primaryEngine'], 'whisper.cpp-large-v3');
      expect(result.lyrics.metadata['fallbackEngine'], 'qwen3-asr-0.6b');
      expect(result.lyrics.metadata['fallbackAppliedCount'], 1);

      await service.dispose();
    });

  });
}

TranscriptionRequest _request(
  String outputDirectory, {
  TranscriptionEngineOrder engineOrder = TranscriptionEngineOrder.qwenPrimary,
}) {
  return TranscriptionRequest(
    inputAudioPath: 'unused-by-fake.wav',
    outputDirectory: outputDirectory,
    config: TranscriptionConfig(
      mode: TranscriptionMode.highestQuality,
      engineOrder: engineOrder,
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
