import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/high_quality_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

import '../tool/asr_quality_report.dart' as quality;

const script = <String>[
  'we are dancing through the night',
  'sing a little song for me',
  'the morning light is breaking',
  'i hear the city waking',
  'hold my hand and follow',
  'we will find tomorrow',
  'every road is winding',
  'but our hearts are shining',
  'say you will remember',
  'this night in september',
  'nothing lasts forever',
  'so sing it all together',
];

List<LyricLine> referenceLines(int secondsPerLine) => [
  for (var i = 0; i < script.length; i++)
    LyricLine(
      text: script[i],
      startTime: Duration(milliseconds: i * secondsPerLine * 1000),
      endTime: Duration(milliseconds: (i + 1) * secondsPerLine * 1000),
      confidence: 95,
    ),
];

/// Splits [script] into equal-time fragments of [fragmentSeconds] each.
List<LyricLine> fragmented(int secondsPerLine, int fragmentSeconds, {required bool typo}) {
  final perLine = (secondsPerLine ~/ fragmentSeconds).clamp(1, 8);
  final lines = <LyricLine>[];
  for (var i = 0; i < script.length; i++) {
    final words = script[i].split(' ');
    final chunk = (words.length / perLine).ceil();
    for (var k = 0; k < perLine; k++) {
      final from = (k * chunk).clamp(0, words.length);
      final to = ((k + 1) * chunk).clamp(0, words.length);
      if (from >= to) continue;
      var text = words.sublist(from, to).join(' ');
      if (typo && k == perLine - 1 && text.length > 4) {
        text = text.substring(0, text.length - 1);
      }
      lines.add(
        LyricLine(
          text: text,
          startTime: Duration(
            milliseconds: (i * secondsPerLine + k * fragmentSeconds) * 1000,
          ),
          endTime: Duration(
            milliseconds:
                (i * secondsPerLine + (k + 1) * fragmentSeconds) * 1000,
          ),
          confidence: 95,
        ),
      );
    }
  }
  return lines;
}

class _Fake implements TranscriptionService {
  _Fake(this.result);
  final TranscriptionResult result;
  final StreamController<TranscriptionProgress> _progress =
      StreamController<TranscriptionProgress>.broadcast();

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
  Future<void> dispose() async => _progress.close();
}

TranscriptionResult _result(List<LyricLine> lines) => TranscriptionResult(
  lyrics: LyricDocument(
    language: 'en',
    lines: lines,
    metadata: const {'draft': true},
  ),
  normalizedAudioPath: 'normalized.wav',
  rawJsonPath: 'raw.json',
  detectedLanguage: 'en',
);

TranscriptionRequest _request(String dir, TranscriptionEngineOrder order) =>
    TranscriptionRequest(
      inputAudioPath: 'unused-by-fake.wav',
      normalizedInputAudioPath: 'already-normalized.wav',
      outputDirectory: dir,
      config: TranscriptionConfig(
        mode: TranscriptionMode.highestQuality,
        engineOrder: order,
        qwenExecutable: 'qwen3-asr',
        qwenModelPath: 'Qwen/Qwen3-ASR-1.7B',
        qwenAlignerModelPath: 'Qwen/Qwen3-ForcedAligner-0.6B',
        whisperExecutable: 'whisper-cli',
        modelPath: 'ggml-large-v3.bin',
      ),
    );

List<quality.QualityLine> toQuality(List<LyricLine> lines) => [
  for (final line in lines)
    quality.QualityLine(
      text: line.text,
      startMs: line.startTime.inMilliseconds,
      endMs: line.endTime.inMilliseconds,
    ),
];

String pct(Object? v) => v is num ? (v * 100).toStringAsFixed(1) + '%' : 'n/a';
String num2(Object? v) => v is num ? v.toStringAsFixed(2) : 'n/a';

void main() {
  test('fusion granularity probe', () async {
    final temp = await Directory.systemTemp.createTemp('probe_');
    // ignore: avoid_print
    print('PRIMARY_SEC | FRAG_SEC | TYPO | OUT | INSERTED | DUP_RATE | RECALL | PRECISION | RATIO');
    for (final combo in <List<int>>[
      [8, 8],
      [8, 4],
      [10, 3],
      [6, 6],
      [4, 10],
      [12, 3],
    ]) {
      for (final typo in <bool>[false, true]) {
        final primarySec = combo[0];
        final fragSec = combo[1];
        final reference = referenceLines(primarySec);
        final secondary = fragmented(primarySec, fragSec, typo: typo);
        for (final order in <TranscriptionEngineOrder>[
          TranscriptionEngineOrder.whisperPrimary,
          TranscriptionEngineOrder.qwenPrimary,
        ]) {
          // The service field names are engine-bound, not order-bound:
          // `primary` always runs the Qwen engine and `fallback` always runs
          // Whisper. `engineOrder` only decides which one is authoritative.
          final qwenDoc = secondary;
          final whisperDoc = reference;
          final service = HighQualityTranscriptionService(
            primary: _Fake(_result(qwenDoc)),
            fallback: _Fake(_result(whisperDoc)),
          );
          final result = await service.transcribe(_request(temp.path, order));
          final out = result.lyrics.lines;
          final score = quality.evaluateLyricQualityPair(
            songId: 'probe',
            engine: 'fused',
            reference: toQuality(reference),
            hypothesis: toQuality(out),
          );
          // ignore: avoid_print
          print(
            '$primarySec | $fragSec | $typo | ${out.length} | '
            '${result.lyrics.metadata['secondaryOnlyLineCount']} | '
            '${pct(score['duplicateLineRate'])} | ${pct(score['lineRecall'])} | '
            '${pct(score['linePrecision'])} | ${num2(score['lineCountRatio'])}'
            '   [${order == TranscriptionEngineOrder.whisperPrimary ? "whisperPrimary" : "qwenPrimary"}]',
          );
          if (combo[0] == 8 && combo[1] == 4 && !typo) {
            // ignore: avoid_print
            print('  qwen=${qwenDoc.length} whisper=${whisperDoc.length} applied=${result.lyrics.metadata['fallbackAppliedCount']}');
            for (final line in out.take(8)) {
              // ignore: avoid_print
              print('   OUT ${line.startTime.inMilliseconds}-${line.endTime.inMilliseconds} "${line.text}" c=${line.confidence}');
            }
          }
          await service.dispose();
        }
      }
    }
    await temp.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
