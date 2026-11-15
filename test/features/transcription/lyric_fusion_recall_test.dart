import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/secondary_only_suggestion.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/high_quality_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/whisper_cpp_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

LyricLine _line(String text, int startMs, int endMs, {int confidence = 90}) =>
    LyricLine(
      text: text,
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
      confidence: confidence,
      confidenceSource: LyricConfidenceSource.model,
    );

TranscriptionResult _result(
  List<LyricLine> lines, {
  Map<String, dynamic> metadata = const {'draft': true},
}) => TranscriptionResult(
  lyrics: LyricDocument(language: 'en', lines: lines, metadata: metadata),
  normalizedAudioPath: 'normalized.wav',
  rawJsonPath: 'result.json',
  detectedLanguage: 'en',
);

TranscriptionRequest _request(
  String outputDirectory, {
  TranscriptionEngineOrder order = TranscriptionEngineOrder.qwenPrimary,
  RecognitionHints hints = RecognitionHints.none,
}) => TranscriptionRequest(
  inputAudioPath: 'unused-by-fake.wav',
  normalizedInputAudioPath: 'already-normalized.wav',
  outputDirectory: outputDirectory,
  recognitionHints: hints,
  config: TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    engineOrder: order,
    qwenExecutable: 'qwen3-asr',
    qwenModelPath: order == TranscriptionEngineOrder.whisperPrimary
        ? 'Qwen/Qwen3-ASR-0.6B'
        : 'Qwen/Qwen3-ASR-1.7B',
    qwenAlignerModelPath: 'Qwen/Qwen3-ForcedAligner-0.6B',
    whisperExecutable: 'whisper-cli',
    modelPath: 'ggml-large-v3.bin',
  ),
);

/// Runs one dual-engine fusion. `qwen` and `whisper` are the two engines'
/// rows; [order] decides which one is primary.
Future<({LyricDocument document, _Fake qwen, _Fake whisper})> _fuse(
  Directory directory, {
  required List<LyricLine> qwen,
  required List<LyricLine> whisper,
  TranscriptionEngineOrder order = TranscriptionEngineOrder.qwenPrimary,
  RecognitionHints hints = RecognitionHints.none,
  Map<String, dynamic> whisperMetadata = const {'draft': true},
}) async {
  final qwenService = _Fake(_result(qwen));
  final whisperService = _Fake(_result(whisper, metadata: whisperMetadata));
  final service = HighQualityTranscriptionService(
    primary: qwenService,
    fallback: whisperService,
  );
  try {
    final result = await service.transcribe(
      _request(directory.path, order: order, hints: hints),
    );
    // Round-trip like a saved project, so the editor sees what disk holds.
    final document = LyricDocument.fromJson(
      jsonDecode(jsonEncode(result.lyrics.toJson())) as Map<String, dynamic>,
    );
    return (document: document, qwen: qwenService, whisper: whisperService);
  } finally {
    await service.dispose();
  }
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lyric_fusion_recall');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('secondary-only suggestions', () {
    for (final order in [
      TranscriptionEngineOrder.qwenPrimary,
      TranscriptionEngineOrder.whisperPrimary,
    ]) {
      test('a genuinely missing line becomes a resolvable suggestion '
          '(${order.name})', () async {
        final shared = [
          _line('city lights are calling', 0, 3000),
          _line('we run until the morning', 8000, 11000),
        ];
        final missing = _line('every window burning gold', 4000, 7000);
        final qwenPrimary = order == TranscriptionEngineOrder.qwenPrimary;
        final fused = await _fuse(
          directory,
          order: order,
          qwen: qwenPrimary ? shared : [...shared, missing],
          whisper: qwenPrimary ? [...shared, missing] : shared,
        );
        final document = fused.document;

        expect(document.lines.map((line) => line.text), [
          'city lights are calling',
          'every window burning gold',
          'we run until the morning',
        ]);
        final suggestions = SecondaryOnlySuggestion.resolve(document);
        expect(suggestions.keys, [1]);
        final suggestion = suggestions[1]!;
        expect(suggestion.text, 'every window burning gold');
        expect(suggestion.startMs, 4000);
        expect(suggestion.endMs, 7000);
        expect(suggestion.engine, isNotNull);
        expect(
          suggestion.engine!.toLowerCase(),
          contains(qwenPrimary ? 'whisper' : 'qwen'),
        );
        // The engine's own score is kept separately from the capped row value.
        expect(suggestion.engineConfidence, 90);
        expect(document.lines[1].confidence, lessThanOrEqualTo(60));
        expect(
          document.lines[1].confidenceSource,
          LyricConfidenceSource.heuristic,
        );
        expect(document.metadata['secondaryOnlyLineIndices'], [1]);
      });
    }

    test('a harmony inside a long primary row is kept, not merged', () async {
      final fused = await _fuse(
        directory,
        qwen: [_line('hold on to the night we made', 0, 6000)],
        whisper: [
          _line('hold on to the night we made', 0, 6000),
          _line('ooh yeah', 2500, 3500),
        ],
      );
      expect(fused.document.lines.map((line) => line.text), [
        'hold on to the night we made',
        'ooh yeah',
      ]);
      expect(SecondaryOnlySuggestion.resolve(fused.document).keys, [1]);
    });

    test(
      'a repeated chorus missing once is suggested once, at its time',
      () async {
        final chorus = 'sing it back to me';
        final fused = await _fuse(
          directory,
          qwen: [
            _line(chorus, 0, 3000),
            _line('bridge words in between', 3000, 6000),
            _line(chorus, 12000, 15000),
          ],
          whisper: [
            _line(chorus, 0, 3000),
            _line('bridge words in between', 3000, 6000),
            _line(chorus, 7000, 10000),
            _line(chorus, 12000, 15000),
          ],
        );
        final lines = fused.document.lines;
        expect(lines.map((line) => line.text), [
          chorus,
          'bridge words in between',
          chorus,
          chorus,
        ]);
        final suggestions = SecondaryOnlySuggestion.resolve(fused.document);
        // Text alone would match three rows; the timestamps pin it to one.
        expect(suggestions.keys, [2]);
        expect(lines[2].startTime, const Duration(seconds: 7));
      },
    );

    test('suggestion records survive a JSON round trip unchanged', () async {
      final fused = await _fuse(
        directory,
        qwen: [_line('first', 0, 2000)],
        whisper: [_line('first', 0, 2000), _line('only here', 5000, 6000)],
      );
      final stored =
          fused.document.metadata[SecondaryOnlySuggestion.metadataKey]
              as Map<String, dynamic>;
      expect(stored['version'], SecondaryOnlySuggestion.version);
      expect(
        SecondaryOnlySuggestion.read(fused.document.metadata),
        hasLength(1),
      );
    });
  });

  group('segmentation differences', () {
    test(
      'a secondary row that re-cuts two primary rows is not inserted twice',
      () async {
        final fused = await _fuse(
          directory,
          qwen: [
            _line('I walk the line', 0, 3000),
            _line('under neon light', 3000, 6000),
          ],
          whisper: [
            _line('I walk', 0, 1500),
            _line('the line under neon', 1500, 4500),
            _line('light', 4500, 6000),
          ],
        );
        final document = fused.document;
        expect(document.lines.map((line) => line.text), [
          'I walk the line',
          'under neon light',
        ]);
        expect(SecondaryOnlySuggestion.resolve(document), isEmpty);
        expect(document.metadata['segmentationOnlySecondaryCount'], 1);
        final recorded = document.metadata['segmentationOnlySecondary'] as List;
        expect((recorded.single as Map)['text'], 'the line under neon');
        expect((recorded.single as Map)['coveredByPrimaryLineIndices'], [0, 1]);
      },
    );

    test('a straddling row with a new word is still suggested', () async {
      final fused = await _fuse(
        directory,
        qwen: [
          _line('I walk the line', 0, 3000),
          _line('under neon light', 3000, 6000),
        ],
        whisper: [
          _line('I walk the line', 0, 3000),
          _line('the line beneath neon', 1500, 4500),
          _line('under neon light', 3000, 6000),
        ],
      );
      expect(
        SecondaryOnlySuggestion.resolve(fused.document).values.single.text,
        'the line beneath neon',
      );
      expect(fused.document.metadata['segmentationOnlySecondaryCount'], 0);
    });

    test('only fragments of four or more runes can count as covered', () async {
      final fused = await _fuse(
        directory,
        qwen: [_line('go now', 0, 2000), _line('oh go', 2000, 4000)],
        whisper: [
          _line('go now', 0, 2000),
          _line('now oh', 1500, 2500),
          _line('oh go', 2000, 4000),
        ],
      );
      // "nowoh" (5 runes) appears across the boundary, so it is covered.
      expect(fused.document.metadata['segmentationOnlySecondaryCount'], 1);

      final short = await _fuse(
        directory,
        qwen: [_line('go now', 0, 2000), _line('oh go', 2000, 4000)],
        whisper: [
          _line('go now', 0, 2000),
          _line('wo', 1800, 2200),
          _line('oh go', 2000, 4000),
        ],
      );
      expect(short.document.metadata['segmentationOnlySecondaryCount'], 0);
    });

    test(
      'a row that only grazes the next primary row is not covered',
      () async {
        // The words straddle the text boundary, but 98% of the time span sits
        // inside row 0: that is not a re-cut of both rows, so it stays a
        // suggestion for a person to judge.
        final fused = await _fuse(
          directory,
          qwen: [
            _line('one two three four five six seven', 0, 6000),
            _line('eight nine', 6000, 9000),
          ],
          whisper: [
            _line('one two three four five six seven', 0, 6000),
            _line('seven eight', 1000, 6100),
            _line('eight nine', 6000, 9000),
          ],
        );
        expect(fused.document.metadata['segmentationOnlySecondaryCount'], 0);
        expect(
          SecondaryOnlySuggestion.resolve(fused.document).values.single.text,
          'seven eight',
        );
      },
    );
  });

  group('recognition hints and diagnostics', () {
    test('hints reach both engines in highest quality mode', () async {
      const hints = RecognitionHints(songTitle: 'Neon Harbor', artist: 'Mira');
      final fused = await _fuse(
        directory,
        hints: hints,
        qwen: [_line('a line', 0, 2000)],
        whisper: [_line('a line', 0, 2000)],
      );
      expect(fused.qwen.requests.single.recognitionHints, same(hints));
      expect(fused.whisper.requests.single.recognitionHints, same(hints));
    });

    test(
      'Whisper decoding metadata is carried into the fused document',
      () async {
        final decoding = {
          'requestedProfile': 'whisper-lyrics-v1',
          'effectiveProfile': 'whisper-lyrics-v1',
        };
        final fused = await _fuse(
          directory,
          qwen: [_line('a line', 0, 2000)],
          whisper: [_line('a line', 0, 2000)],
          whisperMetadata: {
            'draft': true,
            kWhisperDecodingMetadataKey: decoding,
          },
        );
        expect(fused.document.metadata[kWhisperDecodingMetadataKey], decoding);
      },
    );
  });
}

class _Fake implements TranscriptionService {
  final TranscriptionResult result;
  final List<TranscriptionRequest> requests = [];
  final StreamController<TranscriptionProgress> _progress =
      StreamController<TranscriptionProgress>.broadcast();

  _Fake(this.result);

  @override
  bool get isRunning => false;

  @override
  Stream<TranscriptionProgress> get progressStream => _progress.stream;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    requests.add(request);
    return result;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _progress.close();
}
