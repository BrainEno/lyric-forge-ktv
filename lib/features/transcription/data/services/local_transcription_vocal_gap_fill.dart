import 'dart:io';

import '../../../lyrics/domain/services/lyric_span_rerecognition.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/models/vocal_gap_fill_models.dart';
import '../../domain/services/transcription_service.dart';
import '../../domain/services/transcription_vocal_gap_fill.dart';
import '../../domain/services/vocal_gap_filler.dart';
import 'project_span_recognition_service.dart';
import 'qwen3_asr_native_transcription_service.dart';
import 'whisper_cpp_transcription_service.dart';

/// [TranscriptionVocalGapFill] with the local recognisers (D-047).
///
/// Each stretch is cut from the vocal audio into its own 16 kHz clip with
/// FFmpeg, as the editor's "re-run this stretch" does, and recognised with
/// Qwen3-ASR or Whisper; the rows are moved back onto the song's timeline
/// and [VocalGapFiller] decides what goes in.
///
/// Takes no resource lease: it runs inside the whole-song run, which holds
/// the transcription lease until the draft is saved. Qwen3-ASR runs on the
/// app's shared adapter when one is given, so the model the song was just
/// recognised with is reused; that adapter is never disposed here. Other
/// adapters are created once per step and disposed at its end.
class LocalTranscriptionVocalGapFill implements TranscriptionVocalGapFill {
  LocalTranscriptionVocalGapFill({
    TranscriptionService Function()? createQwen,
    TranscriptionService Function()? createWhisper,
    TranscriptionService? sharedQwen,
    SpanClipCutter? cutClip,
    VocalGapFiller filler = const VocalGapFiller(),
    Future<Directory> Function()? createWorkDirectory,
  }) : _createQwen = createQwen ?? Qwen3AsrNativeTranscriptionService.new,
       _createWhisper = createWhisper ?? WhisperCppTranscriptionService.new,
       _sharedQwen = sharedQwen,
       _cutClip = cutClip ?? cutSpanClipWithFfmpeg,
       _filler = filler,
       _createWorkDirectory =
           createWorkDirectory ??
           (() => Directory.systemTemp.createTemp('lyricforge-gapfill-'));

  final TranscriptionService Function() _createQwen;
  final TranscriptionService Function() _createWhisper;
  final TranscriptionService? _sharedQwen;
  final SpanClipCutter _cutClip;
  final VocalGapFiller _filler;
  final Future<Directory> Function() _createWorkDirectory;

  bool _running = false;
  bool _cancelled = false;
  Process? _ffmpeg;
  TranscriptionService? _active;

  bool get isRunning => _running;

  @override
  Future<VocalGapFillResult> fill(
    LyricDocument draft,
    VocalGapFillRequest request,
  ) async {
    if (_running) {
      return VocalGapFillResult(
        draft,
        const VocalGapFillReport.skipped(
          VocalGapFillSkipReason.failed,
          error: 'already running',
        ),
      );
    }
    _running = true;
    _cancelled = false;
    Directory? work;
    final owned = <LyricSpanEngine, TranscriptionService>{};
    try {
      final directory = work = await _createWorkDirectory();
      var clips = 0;
      return await _filler.fill(
        draft,
        engines: request.engines,
        audioDuration: request.audioDuration,
        onProgress: (progress) =>
            request.onProgress?.call(vocalGapFillProgress(progress)),
        recognize: ({required start, required end, required engine}) =>
            _recognize(
              request,
              directory: directory,
              clip: clips++,
              start: start,
              end: end,
              engine: engine,
              owned: owned,
            ),
      );
    } on Object catch (error) {
      return VocalGapFillResult(
        draft,
        VocalGapFillReport.skipped(
          VocalGapFillSkipReason.failed,
          engines: request.engines,
          error: '$error',
        ),
      );
    } finally {
      _ffmpeg = null;
      _active = null;
      for (final adapter in owned.values) {
        try {
          await adapter.dispose();
        } on Object {
          // A recogniser that fails to shut down must not hide the result.
        }
      }
      try {
        if (work != null) await work.delete(recursive: true);
      } on FileSystemException {
        // A leftover temporary clip must not hide the result.
      } finally {
        _running = false;
        _cancelled = false;
      }
    }
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelled = true;
    _ffmpeg?.kill();
    final active = _active;
    if (active != null) await active.cancel();
  }

  Future<List<LyricLine>> _recognize(
    VocalGapFillRequest request, {
    required Directory directory,
    required int clip,
    required Duration start,
    required Duration end,
    required LyricSpanEngine engine,
    required Map<LyricSpanEngine, TranscriptionService> owned,
  }) async {
    final separator = Platform.pathSeparator;
    try {
      _checkCancelled();
      final output = Directory('${directory.path}${separator}gap-$clip');
      await output.create(recursive: true);
      final wavPath = '${output.path}${separator}clip.wav';
      await _cutClip(
        ffmpegExecutable: request.config.ffmpegExecutable,
        inputPath: request.audioPath,
        outputPath: wavPath,
        start: start,
        length: end - start,
        onProcess: (process) => _ffmpeg = process,
      );
      _checkCancelled();
      final adapter = _adapter(engine, owned);
      if (adapter.isRunning) {
        throw const LyricSpanRecognitionException('识别服务正在使用', busy: true);
      }
      _active = adapter;
      try {
        final result = await adapter.transcribe(
          TranscriptionRequest(
            inputAudioPath: wavPath,
            normalizedInputAudioPath: wavPath,
            outputDirectory: output.path,
            config: request.config,
            recognitionHints: request.hints,
          ),
        );
        _checkCancelled();
        return [
          for (final line in result.lyrics.lines) shiftLine(line, start),
        ];
      } finally {
        _active = null;
      }
    } on LyricSpanRecognitionException {
      rethrow;
    } on TranscriptionException catch (error) {
      if (_cancelled || error.kind == TranscriptionFailureKind.cancelled) {
        throw const LyricSpanRecognitionException('已取消', cancelled: true);
      }
      throw LyricSpanRecognitionException(
        error.message,
        busy: error.kind == TranscriptionFailureKind.busy,
      );
    } on Exception catch (error) {
      if (_cancelled) {
        throw const LyricSpanRecognitionException('已取消', cancelled: true);
      }
      throw LyricSpanRecognitionException('$error');
    }
  }

  TranscriptionService _adapter(
    LyricSpanEngine engine,
    Map<LyricSpanEngine, TranscriptionService> owned,
  ) {
    if (engine == LyricSpanEngine.qwen) {
      final shared = _sharedQwen;
      if (shared != null) return shared;
    }
    return owned.putIfAbsent(
      engine,
      () => switch (engine) {
        LyricSpanEngine.qwen => _createQwen(),
        LyricSpanEngine.whisper => _createWhisper(),
      },
    );
  }

  void _checkCancelled() {
    if (_cancelled) {
      throw const LyricSpanRecognitionException('已取消', cancelled: true);
    }
  }

  /// [line] moved [by] later, words included.
  static LyricLine shiftLine(LyricLine line, Duration by) => line.copyWith(
    startTime: line.startTime + by,
    endTime: line.endTime + by,
    words: [
      for (final word in line.words)
        LyricWordTiming(
          text: word.text,
          start: word.start + by,
          end: word.end + by,
        ),
    ],
  );
}

/// The progress line for one stretch, as the run's progress stream shows it.
TranscriptionProgress vocalGapFillProgress(VocalGapFillProgress progress) {
  final engine = switch (progress.engine) {
    LyricSpanEngine.qwen => 'Qwen3-ASR',
    LyricSpanEngine.whisper => 'Whisper',
  };
  final how = progress.fallback ? '换用 $engine 再试' : engine;
  final done = (progress.current - 1) / progress.total;
  return TranscriptionProgress(
    stage: TranscriptionStage.parsing,
    progress: 0.95 + 0.05 * done,
    message:
        '正在补全漏句 ${progress.current}/${progress.total}：'
        '${vocalGapFillClock(progress.start)}–${vocalGapFillClock(progress.end)}'
        '（$how）',
  );
}

/// `m:ss.s`, as the editor writes times.
String vocalGapFillClock(Duration value) {
  final tenths = (value.inMilliseconds / 100).round();
  final minutes = tenths ~/ 600;
  final seconds = tenths % 600;
  return '$minutes:${'${seconds ~/ 10}'.padLeft(2, '0')}.${seconds % 10}';
}
