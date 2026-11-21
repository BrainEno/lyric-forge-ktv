import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_span_rerecognition.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_transcription_vocal_gap_fill.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_gap_fill_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_vocal_gap_fill.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/vocal_gap_filler.dart';

Duration _ms(int value) => Duration(milliseconds: value);

const _config = TranscriptionConfig(
  whisperExecutable: 'whisper',
  modelPath: 'model',
  ffmpegExecutable: 'my-ffmpeg',
);

const _gap = LyricVocalCheckSpan(Duration(seconds: 8), Duration(seconds: 11));
const _later = LyricVocalCheckSpan(
  Duration(seconds: 14),
  Duration(seconds: 17),
);

LyricDocument _draft(List<LyricVocalCheckSpan> spans) => LyricDocument(
  language: 'zh',
  lines: const [
    LyricLine(
      text: '第一句',
      startTime: Duration.zero,
      endTime: Duration(seconds: 4),
      id: 'a',
    ),
    LyricLine(
      text: '最后一句',
      startTime: Duration(seconds: 20),
      endTime: Duration(seconds: 24),
      id: 'b',
    ),
  ],
  metadata: LyricVocalCheckRecord(uncoveredSpans: spans).writeTo(const {}),
);

class _Cut {
  final String ffmpeg;
  final String input;
  final String output;
  final Duration start;
  final Duration length;

  const _Cut(this.ffmpeg, this.input, this.output, this.start, this.length);
}

/// A recogniser that answers each clip with [answers] in order; a row's
/// times are relative to the clip.
class _Adapter implements TranscriptionService {
  _Adapter(this.answers);

  final List<Object> answers;
  final requests = <TranscriptionRequest>[];
  bool running = false;
  int cancels = 0;
  int disposals = 0;
  Completer<void>? hold;

  /// Called when a request starts waiting on [hold].
  void Function()? onHold;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    requests.add(request);
    final gate = hold;
    if (gate != null) {
      onHold?.call();
      await gate.future;
    }
    final index = requests.length - 1;
    final answer = index < answers.length
        ? answers[index]
        : const <LyricLine>[];
    if (answer is Exception) throw answer;
    return TranscriptionResult(
      lyrics: LyricDocument(language: 'zh', lines: answer as List<LyricLine>),
      normalizedAudioPath: request.inputAudioPath,
      rawJsonPath: '',
      detectedLanguage: 'zh',
    );
  }

  @override
  Stream<TranscriptionProgress> get progressStream => const Stream.empty();
  @override
  bool get isRunning => running;
  @override
  Future<void> cancel() async {
    cancels++;
    final gate = hold;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  @override
  Future<void> dispose() async => disposals++;
}

class _Harness {
  _Harness({_Adapter? qwen, _Adapter? whisper, this.cutError})
    : qwen = qwen ?? _Adapter(const []),
      whisper = whisper ?? _Adapter(const []);

  final _Adapter qwen;
  final _Adapter whisper;
  final Object? cutError;
  final cuts = <_Cut>[];
  int whisperCreated = 0;
  int qwenCreated = 0;
  Directory? work;

  LocalTranscriptionVocalGapFill build({bool shareQwen = true}) =>
      LocalTranscriptionVocalGapFill(
        sharedQwen: shareQwen ? qwen : null,
        createQwen: () {
          qwenCreated++;
          return qwen;
        },
        createWhisper: () {
          whisperCreated++;
          return whisper;
        },
        cutClip:
            ({
              required ffmpegExecutable,
              required inputPath,
              required outputPath,
              required start,
              required length,
              required onProcess,
            }) async {
              cuts.add(
                _Cut(ffmpegExecutable, inputPath, outputPath, start, length),
              );
              final error = cutError;
              if (error != null) throw error;
            },
        createWorkDirectory: () async {
          final directory = await Directory.systemTemp.createTemp(
            'gapfill-test-',
          );
          work = directory;
          return directory;
        },
      );
}

VocalGapFillRequest _request(
  List<LyricSpanEngine> engines, {
  void Function(TranscriptionProgress progress)? onProgress,
}) => VocalGapFillRequest(
  audioPath: '/song/vocals.wav',
  config: _config,
  engines: engines,
  hints: const RecognitionHints(songTitle: '夜航'),
  onProgress: onProgress,
);

LyricLine _clipRow(String text, int start, int end) =>
    LyricLine(text: text, startTime: _ms(start), endTime: _ms(end));

void main() {
  test('cuts each stretch from the vocal and moves rows back', () async {
    final harness = _Harness(
      qwen: _Adapter([
        [_clipRow('漏句', 400, 3000)],
      ]),
    );
    final result = await harness.build().fill(
      _draft(const [_gap]),
      _request(const [LyricSpanEngine.qwen]),
    );

    final cut = harness.cuts.single;
    expect(cut.ffmpeg, 'my-ffmpeg');
    expect(cut.input, '/song/vocals.wav');
    expect(cut.start, _ms(7700));
    expect(cut.length, _ms(3600));
    final request = harness.qwen.requests.single;
    expect(request.inputAudioPath, cut.output);
    expect(request.normalizedInputAudioPath, cut.output);
    expect(request.recognitionHints.songTitle, '夜航');
    expect(request.config.ffmpegExecutable, 'my-ffmpeg');

    // 7.7 s + 0.4 s.
    expect(result.document.lines[1].text, '漏句');
    expect(result.document.lines[1].startTime, _ms(8100));
    expect(result.document.lines[1].endTime, _ms(10700));
    expect(result.report.filledSpans, 1);
  });

  test('the shared Qwen adapter is reused and never disposed', () async {
    final harness = _Harness();
    await harness.build().fill(
      _draft(const [_gap, _later]),
      _request(const [LyricSpanEngine.qwen]),
    );
    expect(harness.qwen.requests, hasLength(2));
    expect(harness.qwenCreated, 0);
    expect(harness.qwen.disposals, 0);
  });

  test('other adapters are created once and disposed at the end', () async {
    final harness = _Harness();
    await harness
        .build(shareQwen: false)
        .fill(
          _draft(const [_gap, _later]),
          _request(const [LyricSpanEngine.qwen, LyricSpanEngine.whisper]),
        );
    expect(harness.qwenCreated, 1);
    expect(harness.whisperCreated, 1);
    // Both engines heard nothing in both stretches.
    expect(harness.qwen.requests, hasLength(2));
    expect(harness.whisper.requests, hasLength(2));
    expect(harness.qwen.disposals, 1);
    expect(harness.whisper.disposals, 1);
  });

  test('the temporary clips are deleted afterwards', () async {
    final harness = _Harness();
    await harness.build().fill(
      _draft(const [_gap]),
      _request(const [LyricSpanEngine.whisper]),
    );
    expect(harness.work, isNotNull);
    expect(await harness.work!.exists(), isFalse);
  });

  test('a failed cut fails the engine, and the next one is tried', () async {
    final harness = _Harness(
      cutError: const TranscriptionException.input('FFmpeg 未能裁剪出这一段音频'),
    );
    final result = await harness.build().fill(
      _draft(const [_gap]),
      _request(const [LyricSpanEngine.qwen, LyricSpanEngine.whisper]),
    );
    expect(harness.cuts, hasLength(2));
    expect(result.report.spans.single.outcome, VocalGapFillOutcome.failed);
    expect(result.report.spans.single.error, 'FFmpeg 未能裁剪出这一段音频');
    expect(result.document.lines, hasLength(2));
  });

  test('a busy recogniser ends the step', () async {
    final harness = _Harness()..qwen.running = true;
    final result = await harness.build().fill(
      _draft(const [_gap, _later]),
      _request(const [LyricSpanEngine.qwen, LyricSpanEngine.whisper]),
    );
    expect(result.report.stopReason, VocalGapFillStopReason.busy);
    expect(harness.whisper.requests, isEmpty);
  });

  test('a busy runtime reported by the adapter ends the step', () async {
    final harness = _Harness(
      whisper: _Adapter(const [TranscriptionException.busy('GPU 正忙')]),
    );
    final result = await harness.build().fill(
      _draft(const [_gap, _later]),
      _request(const [LyricSpanEngine.whisper]),
    );
    expect(result.report.stopReason, VocalGapFillStopReason.busy);
    expect(harness.whisper.requests, hasLength(1));
  });

  test('cancel stops the running clip and returns what was found', () async {
    final harness = _Harness(
      qwen: _Adapter([
        [_clipRow('先找到的', 400, 3000)],
        const TranscriptionException.cancelled('已取消'),
      ]),
    );
    final fill = harness.build();
    final progress = <TranscriptionProgress>[];
    final waiting = Completer<void>();
    harness.qwen.onHold = waiting.complete;
    final running = fill.fill(
      _draft(const [_gap, _later]),
      _request(
        const [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
        onProgress: (value) {
          progress.add(value);
          // Hold the second stretch until cancel releases it.
          if (value.message.startsWith('正在补全漏句 2/2')) {
            harness.qwen.hold = Completer<void>();
          }
        },
      ),
    );
    await waiting.future;
    expect(fill.isRunning, isTrue);
    await fill.cancel();
    final result = await running;

    expect(harness.qwen.cancels, 1);
    expect(result.report.stopReason, VocalGapFillStopReason.cancelled);
    expect(result.report.filledSpans, 1);
    expect(result.document.lines[1].text, '先找到的');
    // No fallback after a cancel.
    expect(harness.whisper.requests, isEmpty);
    expect(fill.isRunning, isFalse);
  });

  test('a second fill while one runs is refused', () async {
    final harness = _Harness();
    harness.whisper.hold = Completer<void>();
    final waiting = Completer<void>();
    harness.whisper.onHold = waiting.complete;
    final fill = harness.build();
    final first = fill.fill(
      _draft(const [_gap]),
      _request(const [LyricSpanEngine.whisper]),
    );
    await waiting.future;
    final second = await fill.fill(
      _draft(const [_gap]),
      _request(const [LyricSpanEngine.whisper]),
    );
    expect(second.report.skipReason, VocalGapFillSkipReason.failed);
    harness.whisper.hold!.complete();
    final done = await first;
    expect(done.report.applied, isTrue);
  });

  test('a work directory that cannot be made leaves the draft', () async {
    final fill = LocalTranscriptionVocalGapFill(
      createWorkDirectory: () async =>
          throw const FileSystemException('no space'),
    );
    final draft = _draft(const [_gap]);
    final result = await fill.fill(
      draft,
      _request(const [LyricSpanEngine.whisper]),
    );
    expect(identical(result.document, draft), isTrue);
    expect(result.report.skipReason, VocalGapFillSkipReason.failed);
    expect(result.report.error, contains('no space'));
  });

  test('cancel when idle does nothing', () async {
    await LocalTranscriptionVocalGapFill().cancel();
  });

  group('progress', () {
    test('names the stretch and the engine', () {
      final progress = vocalGapFillProgress(
        VocalGapFillProgress(
          current: 2,
          total: 5,
          start: _ms(62300),
          end: _ms(65800),
          engine: LyricSpanEngine.qwen,
          fallback: false,
        ),
      );
      expect(progress.message, '正在补全漏句 2/5：1:02.3–1:05.8（Qwen3-ASR）');
      expect(progress.stage, TranscriptionStage.parsing);
      // The step's own share: one of five stretches is done (D-049).
      expect(progress.progress, closeTo(0.2, 0.0001));
    });

    test('says when it tries the other engine', () {
      final progress = vocalGapFillProgress(
        VocalGapFillProgress(
          current: 1,
          total: 1,
          start: _ms(7700),
          end: _ms(11300),
          engine: LyricSpanEngine.whisper,
          fallback: true,
        ),
      );
      expect(progress.message, '正在补全漏句 1/1：0:07.7–0:11.3（换用 Whisper 再试）');
      expect(progress.progress, 0);
    });

    test('is sent for every attempt', () async {
      final progress = <TranscriptionProgress>[];
      await _Harness().build().fill(
        _draft(const [_gap]),
        _request(const [
          LyricSpanEngine.qwen,
          LyricSpanEngine.whisper,
        ], onProgress: progress.add),
      );
      expect(progress.map((p) => p.message), [
        '正在补全漏句 1/1：0:07.7–0:11.3（Qwen3-ASR）',
        '正在补全漏句 1/1：0:07.7–0:11.3（换用 Whisper 再试）',
      ]);
    });
  });

  test('shiftLine moves words with the row', () {
    final shifted = LocalTranscriptionVocalGapFill.shiftLine(
      LyricLine(
        text: 'ab',
        startTime: _ms(100),
        endTime: _ms(900),
        words: [
          LyricWordTiming(text: 'a', start: _ms(100), end: _ms(400)),
          LyricWordTiming(text: 'b', start: _ms(400), end: _ms(900)),
        ],
      ),
      _ms(1000),
    );
    expect(shifted.startTime, _ms(1100));
    expect(shifted.words.last.end, _ms(1900));
  });

  test('VocalGapFiller default policy is bounded', () {
    const policy = VocalGapFillPolicy();
    expect(policy.maxGaps, 24);
    expect(policy.maxAudio, const Duration(minutes: 4));
  });
}
