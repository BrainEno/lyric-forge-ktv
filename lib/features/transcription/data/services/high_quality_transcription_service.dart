import 'dart:async';
import 'dart:io';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_service.dart';

class HighQualityTranscriptionService implements TranscriptionService {
  final TranscriptionService primary;
  final TranscriptionService fallback;

  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();

  bool _running = false;
  bool _cancelRequested = false;

  HighQualityTranscriptionService({
    required this.primary,
    required this.fallback,
  });

  @override
  Stream<TranscriptionProgress> get progressStream =>
      _progressController.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    if (_running) {
      throw const TranscriptionException('已有歌词识别任务正在运行');
    }

    _running = true;
    _cancelRequested = false;

    try {
      if (request.config.mode == TranscriptionMode.whisperOnly) {
        return await _runWhisperOnly(request);
      }

      if (!request.config.isHighQualityConfigured) {
        throw const TranscriptionException(
          '最高质量模式需要完整配置 Qwen3-ASR 1.7B、ForcedAligner 和 Whisper fallback',
        );
      }

      final primaryResult = await _runPrimary(request);
      _throwIfCancelled();

      final suspicious = _selectSuspiciousLines(
        primaryResult.lyrics,
        request.config,
      );

      if (suspicious.isEmpty) {
        _emit(
          TranscriptionStage.completed,
          1.0,
          'Qwen3-ASR 结果稳定，无需备用识别',
        );
        return _withQualityMetadata(
          primaryResult,
          fallbackCandidates: const [],
          fallbackAppliedCount: 0,
        );
      }

      final mergedLines = List<LyricLine>.from(primaryResult.lyrics.lines);
      final candidates = <Map<String, dynamic>>[];
      var appliedCount = 0;

      for (var order = 0; order < suspicious.length; order++) {
        _throwIfCancelled();

        final index = suspicious[order];
        final qwenLine = mergedLines[index];
        final fallbackProgress =
            0.78 + ((order + 1) / suspicious.length) * 0.18;

        _emit(
          TranscriptionStage.fallback,
          fallbackProgress.clamp(0.78, 0.96).toDouble(),
          'Whisper 正在复核可疑歌词 · ${order + 1}/${suspicious.length}',
        );

        try {
          final candidate = await _runFallbackForLine(
            request: request,
            primaryResult: primaryResult,
            line: qwenLine,
            lineIndex: index,
          );
          _throwIfCancelled();

          final decision = _decideCandidate(
            qwenLine: qwenLine,
            whisperText: candidate.text,
            whisperConfidence: candidate.confidence,
          );

          if (decision.useWhisper) {
            mergedLines[index] = qwenLine.copyWith(
              text: candidate.text,
              confidence: decision.outputConfidence,
            );
            appliedCount++;
          }

          candidates.add({
            'lineIndex': index,
            'startMs': qwenLine.startTime.inMilliseconds,
            'endMs': qwenLine.endTime.inMilliseconds,
            'qwenText': qwenLine.text,
            'qwenConfidence': qwenLine.confidence,
            'whisperText': candidate.text,
            'whisperConfidence': candidate.confidence,
            'selected': decision.useWhisper ? 'whisper' : 'qwen',
            'reason': decision.reason,
          });
        } on TranscriptionException catch (error) {
          if (error.message == '歌词识别已取消') rethrow;

          candidates.add({
            'lineIndex': index,
            'startMs': qwenLine.startTime.inMilliseconds,
            'endMs': qwenLine.endTime.inMilliseconds,
            'qwenText': qwenLine.text,
            'qwenConfidence': qwenLine.confidence,
            'selected': 'qwen',
            'fallbackError': error.toString(),
          });
        }
      }

      final mergedDocument = primaryResult.lyrics.copyWith(
        lines: mergedLines,
        metadata: {
          ...primaryResult.lyrics.metadata,
          'qualityMode': 'highestQuality',
          'primaryEngine': 'qwen3-asr-1.7b',
          'alignmentEngine': 'qwen3-forced-aligner-0.6b',
          'fallbackEngine': 'whisper.cpp',
          'fallbackCandidateCount': candidates.length,
          'fallbackAppliedCount': appliedCount,
          'fallbackCandidates': candidates,
        },
      );

      _emit(
        TranscriptionStage.completed,
        1.0,
        appliedCount == 0
            ? '最高质量识别完成，Whisper 已复核可疑片段'
            : '最高质量识别完成，已合并 $appliedCount 个备用结果',
      );

      return TranscriptionResult(
        lyrics: mergedDocument,
        normalizedAudioPath: primaryResult.normalizedAudioPath,
        rawJsonPath: primaryResult.rawJsonPath,
        detectedLanguage: primaryResult.detectedLanguage,
      );
    } on _HighQualityCancelledException {
      _emit(TranscriptionStage.cancelled, 0.0, '歌词识别已取消');
      throw const TranscriptionException('歌词识别已取消');
    } finally {
      _running = false;
      _cancelRequested = false;
    }
  }

  Future<TranscriptionResult> _runPrimary(
    TranscriptionRequest request,
  ) async {
    StreamSubscription<TranscriptionProgress>? subscription;
    subscription = primary.progressStream.listen((progress) {
      if (_cancelRequested) return;

      final mapped = 0.02 + progress.progress * 0.74;
      _emit(
        progress.stage,
        mapped.clamp(0.02, 0.76).toDouble(),
        progress.message,
      );
    });

    try {
      return await primary.transcribe(request);
    } finally {
      await subscription.cancel();
    }
  }

  Future<TranscriptionResult> _runWhisperOnly(
    TranscriptionRequest request,
  ) async {
    StreamSubscription<TranscriptionProgress>? subscription;
    subscription = fallback.progressStream.listen((progress) {
      if (_cancelRequested) return;
      _emit(progress.stage, progress.progress, progress.message);
    });

    try {
      return await fallback.transcribe(request);
    } finally {
      await subscription.cancel();
    }
  }

  List<int> _selectSuspiciousLines(
    LyricDocument lyrics,
    TranscriptionConfig config,
  ) {
    final candidates = <int>[];

    for (var i = 0; i < lyrics.lines.length; i++) {
      final line = lyrics.lines[i];
      if (line.confidence < config.fallbackConfidenceThreshold ||
          _hasSuspiciousRepetition(line.text) ||
          _looksTimingSuspicious(line)) {
        candidates.add(i);
      }
    }

    candidates.sort(
      (a, b) => lyrics.lines[a].confidence.compareTo(
        lyrics.lines[b].confidence,
      ),
    );

    return candidates.take(config.maxFallbackSegments).toList();
  }

  bool _looksTimingSuspicious(LyricLine line) {
    final duration = line.endTime - line.startTime;
    if (duration > const Duration(seconds: 10)) return true;
    if (duration < const Duration(milliseconds: 300) &&
        line.text.trim().length > 8) {
      return true;
    }
    return false;
  }

  Future<_FallbackCandidate> _runFallbackForLine({
    required TranscriptionRequest request,
    required TranscriptionResult primaryResult,
    required LyricLine line,
    required int lineIndex,
  }) async {
    final root = Directory(
      request.outputDirectory +
          Platform.pathSeparator +
          'fallback' +
          Platform.pathSeparator +
          'segment_' +
          lineIndex.toString().padLeft(3, '0'),
    );
    await root.create(recursive: true);

    final slicePath =
        root.path + Platform.pathSeparator + 'candidate.wav';
    final padding = const Duration(milliseconds: 350);
    final start = line.startTime > padding
        ? line.startTime - padding
        : Duration.zero;
    final end = line.endTime + padding;
    final duration = end - start;

    await _extractSlice(
      ffmpegExecutable: request.config.ffmpegExecutable,
      inputPath: primaryResult.normalizedAudioPath,
      outputPath: slicePath,
      start: start,
      duration: duration,
    );
    _throwIfCancelled();

    final fallbackRequest = TranscriptionRequest(
      inputAudioPath: slicePath,
      outputDirectory: root.path,
      config: request.config.copyWith(
        mode: TranscriptionMode.whisperOnly,
      ),
    );

    final result = await fallback.transcribe(fallbackRequest);
    final text = _joinFallbackLines(result.lyrics.lines);
    if (text.isEmpty) {
      throw const TranscriptionException('Whisper fallback 未识别到文本');
    }

    final confidence = _averageConfidence(result.lyrics.lines);
    return _FallbackCandidate(
      text: text,
      confidence: confidence,
    );
  }

  Future<void> _extractSlice({
    required String ffmpegExecutable,
    required String inputPath,
    required String outputPath,
    required Duration start,
    required Duration duration,
  }) async {
    final result = await Process.run(
      ffmpegExecutable,
      [
        '-y',
        '-ss',
        _seconds(start),
        '-i',
        inputPath,
        '-t',
        _seconds(duration),
        '-vn',
        '-ar',
        '16000',
        '-ac',
        '1',
        '-c:a',
        'pcm_s16le',
        outputPath,
      ],
    );

    _throwIfCancelled();

    if (result.exitCode != 0 || !await File(outputPath).exists()) {
      throw TranscriptionException(
        '无法提取备用识别片段',
        details: result.stderr.toString(),
      );
    }
  }

  String _seconds(Duration duration) {
    return (duration.inMilliseconds / 1000.0).toStringAsFixed(3);
  }

  String _joinFallbackLines(List<LyricLine> lines) {
    final parts = lines
        .map((line) => line.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';

    final containsCjk = RegExp(r'[\u3400-\u9fff\u3040-\u30ff]')
        .hasMatch(parts.join());
    return parts.join(containsCjk ? '' : ' ').trim();
  }

  int _averageConfidence(List<LyricLine> lines) {
    if (lines.isEmpty) return 0;
    final total = lines.fold<int>(
      0,
      (sum, line) => sum + line.confidence,
    );
    return (total / lines.length).round().clamp(0, 100).toInt();
  }

  _CandidateDecision _decideCandidate({
    required LyricLine qwenLine,
    required String whisperText,
    required int whisperConfidence,
  }) {
    final qwenSuspicious = _hasSuspiciousRepetition(qwenLine.text);
    final whisperSuspicious = _hasSuspiciousRepetition(whisperText);

    if (qwenSuspicious && !whisperSuspicious && whisperConfidence >= 55) {
      return _CandidateDecision(
        useWhisper: true,
        outputConfidence: whisperConfidence.clamp(55, 85).toInt(),
        reason: 'qwen_repetition',
      );
    }

    if (qwenLine.confidence <= 45 &&
        !whisperSuspicious &&
        whisperConfidence >= qwenLine.confidence + 12) {
      return _CandidateDecision(
        useWhisper: true,
        outputConfidence: whisperConfidence.clamp(50, 85).toInt(),
        reason: 'whisper_materially_stronger',
      );
    }

    return _CandidateDecision(
      useWhisper: false,
      outputConfidence: qwenLine.confidence,
      reason: 'keep_qwen_primary',
    );
  }

  bool _hasSuspiciousRepetition(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff\u3040-\u30ff]+'), ' ')
        .trim();
    if (normalized.length < 8) return false;

    final tokens = normalized.contains(' ')
        ? normalized.split(RegExp(r'\s+'))
        : normalized.runes.map(String.fromCharCode).toList();
    if (tokens.length < 4) return false;

    var repeated = 0;
    for (var i = 1; i < tokens.length; i++) {
      if (tokens[i] == tokens[i - 1]) repeated++;
    }

    return repeated >= 2 || tokens.toSet().length / tokens.length < 0.45;
  }

  TranscriptionResult _withQualityMetadata(
    TranscriptionResult result, {
    required List<Map<String, dynamic>> fallbackCandidates,
    required int fallbackAppliedCount,
  }) {
    return TranscriptionResult(
      lyrics: result.lyrics.copyWith(
        metadata: {
          ...result.lyrics.metadata,
          'qualityMode': 'highestQuality',
          'primaryEngine': 'qwen3-asr-1.7b',
          'alignmentEngine': 'qwen3-forced-aligner-0.6b',
          'fallbackEngine': 'whisper.cpp',
          'fallbackCandidateCount': fallbackCandidates.length,
          'fallbackAppliedCount': fallbackAppliedCount,
          'fallbackCandidates': fallbackCandidates,
        },
      ),
      normalizedAudioPath: result.normalizedAudioPath,
      rawJsonPath: result.rawJsonPath,
      detectedLanguage: result.detectedLanguage,
    );
  }

  void _emit(
    TranscriptionStage stage,
    double progress,
    String message,
  ) {
    if (_progressController.isClosed) return;
    _progressController.add(
      TranscriptionProgress(
        stage: stage,
        progress: progress.clamp(0.0, 1.0).toDouble(),
        message: message,
      ),
    );
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const _HighQualityCancelledException();
    }
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    await Future.wait([
      primary.cancel(),
      fallback.cancel(),
    ]);
  }

  @override
  Future<void> dispose() async {
    _cancelRequested = true;
    await primary.dispose();
    await fallback.dispose();
    await _progressController.close();
  }
}

class _FallbackCandidate {
  final String text;
  final int confidence;

  const _FallbackCandidate({
    required this.text,
    required this.confidence,
  });
}

class _CandidateDecision {
  final bool useWhisper;
  final int outputConfidence;
  final String reason;

  const _CandidateDecision({
    required this.useWhisper,
    required this.outputConfidence,
    required this.reason,
  });
}

class _HighQualityCancelledException implements Exception {
  const _HighQualityCancelledException();
}
