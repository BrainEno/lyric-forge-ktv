// Deterministic before/after evidence for the dual-engine fusion step.
//
// The fixtures under test/fixtures/asr_quality/ are hand-written engine
// outputs (original lyric text, no audio, no model inference). This test feeds
// them through the production HighQualityTranscriptionService exactly as the
// app does, then scores the fused document with tool/asr_quality_report.dart.
//
// It deliberately uses only APIs that already existed at the baseline commit,
// so CI can copy this file, the fixtures and the report tool into a baseline
// checkout and produce the "before" report with identical inputs:
//
//   LYRIC_FUSION_EVAL_BASELINE=1 \
//   LYRIC_FUSION_EVAL_OUT=build/fusion_before.json \
//     flutter test test/tool/asr_fusion_fixture_eval_test.dart
//
// Without LYRIC_FUSION_EVAL_BASELINE the current invariants are asserted.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/high_quality_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

import '../../tool/asr_quality_report.dart' as quality;

const String _fixtureRoot = 'test/fixtures/asr_quality';

List<LyricLine> _engineLines(String path) {
  final decoded =
      jsonDecode(File('$_fixtureRoot/$path').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final raw in decoded['lines'] as List)
      LyricLine(
        text: (raw as Map)['text'] as String,
        startTime: Duration(milliseconds: raw['startMs'] as int),
        endTime: Duration(milliseconds: raw['endMs'] as int),
        confidence: raw['confidence'] as int,
        confidenceSource: LyricConfidenceSource.model,
      ),
  ];
}

Map<String, Object?> _asCandidate(String engine, LyricDocument document) {
  final indices = document.metadata['secondaryOnlyLineIndices'];
  final flagged = <int>{
    if (indices is List)
      for (final value in indices)
        if (value is int) value,
  };
  return {
    'engine': engine,
    'lines': [
      for (var index = 0; index < document.lines.length; index++)
        {
          'text': document.lines[index].text,
          'startMs': document.lines[index].startTime.inMilliseconds,
          'endMs': document.lines[index].endTime.inMilliseconds,
          if (flagged.contains(index)) 'secondaryOnly': true,
        },
    ],
  };
}

Future<LyricDocument> _fuse(
  List<LyricLine> qwen,
  List<LyricLine> whisper,
  String language,
) async {
  final service = HighQualityTranscriptionService(
    primary: _FixtureEngine(qwen, language),
    fallback: _FixtureEngine(whisper, language),
  );
  final output = await Directory.systemTemp.createTemp('fusion_fixture');
  try {
    final result = await service.transcribe(
      TranscriptionRequest(
        inputAudioPath: 'fixture.wav',
        normalizedInputAudioPath: 'fixture-normalized.wav',
        outputDirectory: output.path,
        config: TranscriptionConfig(
          mode: TranscriptionMode.highestQuality,
          engineOrder: TranscriptionEngineOrder.qwenPrimary,
          qwenExecutable: 'qwen3-asr',
          qwenModelPath: 'Qwen/Qwen3-ASR-1.7B',
          qwenAlignerModelPath: 'Qwen/Qwen3-ForcedAligner-0.6B',
          whisperExecutable: 'whisper-cli',
          modelPath: 'ggml-large-v3.bin',
          language: language,
        ),
      ),
    );
    return result.lyrics;
  } finally {
    await service.dispose();
    await output.delete(recursive: true);
  }
}

void main() {
  test('fixture fusion report', () async {
    final manifest =
        jsonDecode(
              File('$_fixtureRoot/fusion_manifest.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final corpusSongs = <Map<String, Object?>>[];
    for (final raw in manifest['songs'] as List) {
      final song = raw as Map<String, dynamic>;
      final language = song['language'] as String;
      final qwen = _engineLines(song['qwen'] as String);
      final whisper = _engineLines(song['whisper'] as String);
      final fused = await _fuse(qwen, whisper, language);
      corpusSongs.add({
        'id': song['id'],
        'language': language,
        'reference': {
          'text': File('$_fixtureRoot/${song['reference']}').readAsStringSync(),
          'reviewed': true,
        },
        'candidates': [
          _asCandidate(
            'qwen-only',
            LyricDocument(language: language, lines: qwen),
          ),
          _asCandidate(
            'whisper-only',
            LyricDocument(language: language, lines: whisper),
          ),
          _asCandidate('fused', fused),
        ],
        'secondaryRetention': {
          'primary': 'qwen-only',
          'secondary': 'whisper-only',
          'fused': 'fused',
        },
      });
    }

    final report = quality.evaluateQualityCorpus(
      jsonEncode({'schemaVersion': 1, 'songs': corpusSongs}),
    );
    final outPath = Platform.environment['LYRIC_FUSION_EVAL_OUT'];
    if (outPath != null && outPath.isNotEmpty) {
      File(outPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
      File(
        outPath.replaceFirst(RegExp(r'\.json$'), '.md'),
      ).writeAsStringSync(quality.formatQualityReport(report));
    }
    if (Platform.environment['LYRIC_FUSION_EVAL_BASELINE'] == '1') return;

    final byEngine = report['overallByEngine']! as Map<String, Object?>;
    final fusedSummary = byEngine['fused']! as Map<String, Object?>;
    final qwenSummary = byEngine['qwen-only']! as Map<String, Object?>;
    final retention = report['secondaryRetention']! as Map<String, Object?>;

    // Every true line only Whisper heard is still in the draft, and marked.
    expect(retention['secondaryOnlyReferenceLineCount'], 4);
    expect(retention['retentionRate'], 1.0);
    expect(retention['retainedAsSuggestionCount'], 4);
    // Fusion recovers what the primary engine missed.
    expect(fusedSummary['lineRecall'], 1.0);
    expect(
      fusedSummary['lineRecall']! as double,
      greaterThan(qwenSummary['lineRecall']! as double),
    );
    // Re-segmented rows are no longer inserted as duplicates; the remaining
    // extra rows are the two genuine ad-libs, kept for review.
    expect(fusedSummary['duplicateLineCount'], 0);
    expect(fusedSummary['hypothesisLineCount'], 23);
    expect(fusedSummary['secondaryOnlyLineCount'], 6);
    expect(fusedSummary['secondaryOnlyMatchedCount'], 4);
  });
}

class _FixtureEngine implements TranscriptionService {
  final List<LyricLine> lines;
  final String language;
  final StreamController<TranscriptionProgress> _progress =
      StreamController<TranscriptionProgress>.broadcast();

  _FixtureEngine(this.lines, this.language);

  @override
  bool get isRunning => false;

  @override
  Stream<TranscriptionProgress> get progressStream => _progress.stream;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async =>
      TranscriptionResult(
        lyrics: LyricDocument(
          language: language,
          lines: lines,
          metadata: const {'draft': true},
        ),
        normalizedAudioPath: 'fixture-normalized.wav',
        rawJsonPath: 'fixture.json',
        detectedLanguage: language,
      );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _progress.close();
}
