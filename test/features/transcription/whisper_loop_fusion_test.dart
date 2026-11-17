import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/secondary_only_suggestion.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/high_quality_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

import 'domain/whisper_loop_fixtures.dart';

TranscriptionResult _result(List<LyricLine> lines) => TranscriptionResult(
  lyrics: LyricDocument(
    language: 'en',
    lines: lines,
    metadata: const {'draft': true},
  ),
  normalizedAudioPath: 'normalized.wav',
  rawJsonPath: 'result.json',
  detectedLanguage: 'en',
);

TranscriptionRequest _request(
  String outputDirectory,
  TranscriptionEngineOrder order,
) => TranscriptionRequest(
  inputAudioPath: 'unused-by-fake.wav',
  normalizedInputAudioPath: 'already-normalized.wav',
  outputDirectory: outputDirectory,
  config: TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    engineOrder: order,
    qwenExecutable: 'qwen3-asr',
    qwenModelPath: 'Qwen/Qwen3-ASR-0.6B',
    qwenAlignerModelPath: 'Qwen/Qwen3-ForcedAligner-0.6B',
    whisperExecutable: 'whisper-cli',
    modelPath: 'ggml-large-v3.bin',
  ),
);

Future<LyricDocument> _fuse(
  Directory directory, {
  required TranscriptionService qwen,
  required TranscriptionService whisper,
  required TranscriptionEngineOrder order,
}) async {
  final service = HighQualityTranscriptionService(
    primary: qwen,
    fallback: whisper,
  );
  try {
    final result = await service.transcribe(_request(directory.path, order));
    // Round-trip like a saved project, so the test sees what disk holds.
    return LyricDocument.fromJson(
      jsonDecode(jsonEncode(result.lyrics.toJson())) as Map<String, dynamic>,
    );
  } finally {
    await service.dispose();
  }
}

List<Map<String, dynamic>> _candidates(LyricDocument document) => [
  for (final value in document.metadata['fallbackCandidates'] as List? ?? [])
    Map<String, dynamic>.from(value as Map),
];

int _count(LyricDocument document, String text) =>
    document.lines.where((line) => line.text == text).length;

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whisper_loop_fusion');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('Whisper-primary: a disproved loop becomes Qwen\'s rows, queued '
      'for review', () async {
    final document = await _fuse(
      directory,
      qwen: _Fake(_result(qwenOverLoopedSong())),
      whisper: _Fake(_result(whisperLoopedSong())),
      order: TranscriptionEngineOrder.whisperPrimary,
    );

    expect(_count(document, loopVerse), 0);
    expect(_count(document, loopChant), 0);
    expect(
      _count(document, 'Oh, but the people you know, they say what they want to'),
      1,
    );
    // Qwen rows standing in for the loop are not inserted a second time.
    expect(
      _count(document, 'Oh, and the lanterns that you hold, we never mean to fold'),
      1,
    );
    expect(document.lines, hasLength(11));

    final loopCandidates = _candidates(document)
        .where(
          (candidate) =>
              candidate['reason'] ==
              'whisper_cross_segment_loop_replaced_by_qwen',
        )
        .toList();
    expect(loopCandidates, hasLength(5));
    for (final candidate in loopCandidates) {
      final index = candidate['lineIndex'] as int;
      expect(candidate['alternativeText'], document.lines[index].text);
      expect(candidate['primaryText'], '$loopChant / $loopVerse');
      expect(candidate['selected'], 'qwen');
      expect((candidate['whisperLoop'] as Map)['repeats'], 11);
    }

    final arbitration =
        document.metadata[HighQualityTranscriptionService
                .whisperLoopArbitrationKey]
            as List;
    expect((arbitration.single as Map)['verdict'], 'replacedBySecondary');
    expect(SecondaryOnlySuggestion.resolve(document), isEmpty);
  });

  test('Qwen-primary: Whisper\'s loop no longer floods the suggestions', () async {
    final document = await _fuse(
      directory,
      qwen: _Fake(_result(qwenOverLoopedSong())),
      whisper: _Fake(_result(whisperLoopedSong())),
      order: TranscriptionEngineOrder.qwenPrimary,
    );

    expect(_count(document, loopVerse), 0);
    expect(document.lines, hasLength(qwenOverLoopedSong().length + 1));
    final arbitration =
        document.metadata[HighQualityTranscriptionService
                .whisperLoopArbitrationKey]
            as List;
    expect((arbitration.single as Map)['verdict'], 'replacedBySecondary');
  });

  test('Qwen second opinion failed: a strong loop is cut down and flagged', () async {
    final document = await _fuse(
      directory,
      qwen: _Failing(),
      whisper: _Fake(_result(whisperLoopedSong())),
      order: TranscriptionEngineOrder.whisperPrimary,
    );

    expect(_count(document, loopVerse), 1);
    expect(document.lines, hasLength(whisperLoopedSong().length - 20));
    final candidates = _candidates(document);
    expect(candidates, hasLength(2));
    expect(
      candidates.map((candidate) => candidate['reason']).toSet(),
      {'whisper_cross_segment_loop_collapsed'},
    );
    expect(document.metadata['fallbackCandidateCount'], 2);
    expect(document.metadata['fallbackStatus'], 'failed');
  });

  test('a sung repetition both engines hear stays as it is', () async {
    final whisper = [
      loopLine('verse line one', 0, 4000),
      for (var i = 0; i < 6; i++)
        loopLine('we will rise again', 4000 + i * 2500, 6500 + i * 2500),
      loopLine('outro line', 19000, 23000),
    ];
    final qwen = [
      loopLine('verse line one', 0, 4000),
      loopLine('We will rise again, we will rise again.', 4000, 9000),
      loopLine('We will rise again, we will rise again,', 9000, 14000),
      loopLine('we will rise again, we will rise again', 14000, 19000),
      loopLine('outro line', 19000, 23000),
    ];
    final document = await _fuse(
      directory,
      qwen: _Fake(_result(qwen)),
      whisper: _Fake(_result(whisper)),
      order: TranscriptionEngineOrder.whisperPrimary,
    );

    expect(_count(document, 'we will rise again'), 6);
    expect(
      _candidates(document).where(
        (candidate) => '${candidate['reason']}'.startsWith('whisper_cross'),
      ),
      isEmpty,
    );
  });
}

class _Fake implements TranscriptionService {
  final TranscriptionResult result;
  final StreamController<TranscriptionProgress> _progress =
      StreamController<TranscriptionProgress>.broadcast();

  _Fake(this.result);

  @override
  bool get isRunning => false;

  @override
  Stream<TranscriptionProgress> get progressStream => _progress.stream;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async =>
      result;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _progress.close();
}

class _Failing implements TranscriptionService {
  final StreamController<TranscriptionProgress> _progress =
      StreamController<TranscriptionProgress>.broadcast();

  @override
  bool get isRunning => false;

  @override
  Stream<TranscriptionProgress> get progressStream => _progress.stream;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async =>
      throw const TranscriptionException.environment('Qwen runtime crashed');

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _progress.close();
}
