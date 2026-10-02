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
          '最高质量模式需要完整配置 Qwen3-ASR 1.7B、ForcedAligner 和 Whisper large-v3',
        );
      }

      final primaryResult = await _runPrimary(request);
      _throwIfCancelled();

      _emit(
        TranscriptionStage.fallback,
        0.76,
        'Whisper large-v3 正在进行全曲第二意见识别',
      );

      final fallbackDirectory = Directory(
        request.outputDirectory +
            Platform.pathSeparator +
            'whisper_second_opinion',
      );
      await fallbackDirectory.create(recursive: true);

      final fallbackResult = await _runFallbackFullSong(
        TranscriptionRequest(
          inputAudioPath: request.inputAudioPath,
          outputDirectory: fallbackDirectory.path,
          config: request.config.copyWith(
            mode: TranscriptionMode.whisperOnly,
          ),
        ),
      );
      _throwIfCancelled();

      _emit(
        TranscriptionStage.parsing,
        0.96,
        '正在比较 Qwen 与 Whisper 的歌词分歧',
      );

      final merge = _mergeIndependentResults(
        primary: primaryResult.lyrics,
        fallback: fallbackResult.lyrics,
        config: request.config,
      );

      final mergedDocument = primaryResult.lyrics.copyWith(
        lines: merge.lines,
        metadata: {
          ...primaryResult.lyrics.metadata,
          'qualityMode': 'highestQuality',
          'primaryEngine': 'qwen3-asr-1.7b',
          'alignmentEngine': 'qwen3-forced-aligner-0.6b',
          'fallbackEngine': 'whisper.cpp-large-v3',
          'fallbackStrategy': 'fullSongSecondOpinion',
          'fallbackCandidateCount': merge.candidates.length,
          'fallbackAppliedCount': merge.appliedCount,
          'fallbackCandidates': merge.candidates,
          'whisperRawJsonPath': fallbackResult.rawJsonPath,
        },
      );

      _emit(
        TranscriptionStage.completed,
        1.0,
        merge.candidates.isEmpty
            ? '最高质量识别完成，两套引擎结果高度一致'
            : '最高质量识别完成，发现 ${merge.candidates.length} 行需要重点校对',
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
    } on TranscriptionException catch (error) {
      if (error.message == '歌词识别已取消') {
        _emit(TranscriptionStage.cancelled, 0.0, '歌词识别已取消');
      } else {
        _emit(TranscriptionStage.failed, 0.0, '最高质量歌词识别失败');
      }
      rethrow;
    } finally {
      _running = false;
      _cancelRequested = false;
    }
  }

  Future<TranscriptionResult> _runPrimary(
    TranscriptionRequest request,
  ) async {
    final subscription = primary.progressStream.listen((progress) {
      if (_cancelRequested) return;
      final mapped = 0.02 + progress.progress * 0.70;
      _emit(
        progress.stage,
        mapped.clamp(0.02, 0.72).toDouble(),
        progress.message,
      );
    });

    try {
      return await primary.transcribe(request);
    } finally {
      await subscription.cancel();
    }
  }

  Future<TranscriptionResult> _runFallbackFullSong(
    TranscriptionRequest request,
  ) async {
    final subscription = fallback.progressStream.listen((progress) {
      if (_cancelRequested) return;

      final mapped = 0.76 + progress.progress * 0.18;
      _emit(
        TranscriptionStage.fallback,
        mapped.clamp(0.76, 0.94).toDouble(),
        'Whisper 第二意见 · ' + progress.message,
      );
    });

    try {
      return await fallback.transcribe(request);
    } finally {
      await subscription.cancel();
    }
  }

  Future<TranscriptionResult> _runWhisperOnly(
    TranscriptionRequest request,
  ) async {
    final subscription = fallback.progressStream.listen((progress) {
      if (_cancelRequested) return;
      _emit(progress.stage, progress.progress, progress.message);
    });

    try {
      return await fallback.transcribe(request);
    } finally {
      await subscription.cancel();
    }
  }

  _MergeResult _mergeIndependentResults({
    required LyricDocument primary,
    required LyricDocument fallback,
    required TranscriptionConfig config,
  }) {
    final lines = List<LyricLine>.from(primary.lines);
    final candidates = <_RankedCandidate>[];

    for (var index = 0; index < primary.lines.length; index++) {
      final qwenLine = primary.lines[index];
      final whisperLines = _overlappingLines(
        qwenLine,
        fallback.lines,
      );
      if (whisperLines.isEmpty) {
        if (_isPrimarySuspicious(qwenLine, config)) {
          candidates.add(
            _RankedCandidate(
              priority: 100 - qwenLine.confidence,
              data: {
                'lineIndex': index,
                'startMs': qwenLine.startTime.inMilliseconds,
                'endMs': qwenLine.endTime.inMilliseconds,
                'qwenText': qwenLine.text,
                'qwenConfidence': qwenLine.confidence,
                'selected': 'qwen',
                'reason': 'whisper_no_overlap',
              },
            ),
          );
        }
        continue;
      }

      final whisperText = _joinFallbackLines(whisperLines);
      final whisperConfidence = _averageConfidence(whisperLines);
      final similarity = _textSimilarity(
        qwenLine.text,
        whisperText,
      );
      final durationRatio = _durationRatio(qwenLine, whisperLines);

      final suspicious = _isPrimarySuspicious(qwenLine, config) ||
          similarity < 0.72;
      if (!suspicious) continue;

      final decision = _decideCandidate(
        qwenLine: qwenLine,
        whisperText: whisperText,
        whisperConfidence: whisperConfidence,
        similarity: similarity,
        durationRatio: durationRatio,
      );

      candidates.add(
        _RankedCandidate(
          priority: _candidatePriority(
            qwenLine: qwenLine,
            similarity: similarity,
          ),
          data: {
            'lineIndex': index,
            'startMs': qwenLine.startTime.inMilliseconds,
            'endMs': qwenLine.endTime.inMilliseconds,
            'qwenText': qwenLine.text,
            'qwenConfidence': qwenLine.confidence,
            'whisperText': whisperText,
            'whisperConfidence': whisperConfidence,
            'similarity': double.parse(similarity.toStringAsFixed(3)),
            'durationRatio': double.parse(durationRatio.toStringAsFixed(3)),
            'selected': decision.useWhisper ? 'whisper' : 'qwen',
            'reason': decision.reason,
          },
          decision: decision,
        ),
      );
    }

    candidates.sort((a, b) => b.priority.compareTo(a.priority));
    final limited = candidates
        .take(config.maxFallbackSegments)
        .toList(growable: false);

    var appliedCount = 0;
    for (final candidate in limited) {
      final decision = candidate.decision;
      if (decision == null || !decision.useWhisper) continue;

      final index = candidate.data['lineIndex'] as int;
      final whisperText = candidate.data['whisperText'] as String;
      lines[index] = lines[index].copyWith(
        text: whisperText,
        confidence: decision.outputConfidence,
      );
      appliedCount++;
    }

    return _MergeResult(
      lines: lines,
      candidates: limited.map((e) => e.data).toList(growable: false),
      appliedCount: appliedCount,
    );
  }

  bool _isPrimarySuspicious(
    LyricLine line,
    TranscriptionConfig config,
  ) {
    return line.confidence < config.fallbackConfidenceThreshold ||
        _hasSuspiciousRepetition(line.text) ||
        _looksTimingSuspicious(line);
  }

  List<LyricLine> _overlappingLines(
    LyricLine target,
    List<LyricLine> candidates,
  ) {
    final paddedStart = target.startTime - const Duration(milliseconds: 450);
    final paddedEnd = target.endTime + const Duration(milliseconds: 450);
    final result = <LyricLine>[];

    for (final line in candidates) {
      final overlapStart =
          line.startTime > paddedStart ? line.startTime : paddedStart;
      final overlapEnd = line.endTime < paddedEnd ? line.endTime : paddedEnd;

      if (overlapEnd > overlapStart) {
        result.add(line);
      }
    }

    return result;
  }

  double _durationRatio(
    LyricLine qwenLine,
    List<LyricLine> whisperLines,
  ) {
    if (whisperLines.isEmpty) return 0.0;

    final qwenDuration =
        (qwenLine.endTime - qwenLine.startTime).inMilliseconds;
    final whisperStart = whisperLines
        .map((line) => line.startTime)
        .reduce((a, b) => a < b ? a : b);
    final whisperEnd = whisperLines
        .map((line) => line.endTime)
        .reduce((a, b) => a > b ? a : b);
    final whisperDuration =
        (whisperEnd - whisperStart).inMilliseconds;

    if (qwenDuration <= 0 || whisperDuration <= 0) return 0.0;
    return whisperDuration / qwenDuration;
  }

  int _candidatePriority({
    required LyricLine qwenLine,
    required double similarity,
  }) {
    final confidenceRisk = 100 - qwenLine.confidence;
    final disagreementRisk = ((1.0 - similarity) * 100).round();
    final repetitionRisk = _hasSuspiciousRepetition(qwenLine.text) ? 35 : 0;
    return confidenceRisk + disagreementRisk + repetitionRisk;
  }

  _CandidateDecision _decideCandidate({
    required LyricLine qwenLine,
    required String whisperText,
    required int whisperConfidence,
    required double similarity,
    required double durationRatio,
  }) {
    final qwenSuspicious = _hasSuspiciousRepetition(qwenLine.text);
    final whisperSuspicious = _hasSuspiciousRepetition(whisperText);

    final timingCompatible = durationRatio >= 0.55 && durationRatio <= 1.80;

    if (timingCompatible &&
        qwenSuspicious &&
        !whisperSuspicious &&
        whisperConfidence >= 55 &&
        similarity < 0.82) {
      return _CandidateDecision(
        useWhisper: true,
        outputConfidence: whisperConfidence.clamp(55, 85).toInt(),
        reason: 'qwen_repetition',
      );
    }

    if (timingCompatible &&
        qwenLine.confidence <= 45 &&
        !whisperSuspicious &&
        whisperConfidence >= qwenLine.confidence + 12 &&
        similarity < 0.75) {
      return _CandidateDecision(
        useWhisper: true,
        outputConfidence: whisperConfidence.clamp(50, 85).toInt(),
        reason: 'whisper_materially_stronger',
      );
    }

    return _CandidateDecision(
      useWhisper: false,
      outputConfidence: qwenLine.confidence,
      reason: similarity < 0.72
          ? 'engine_disagreement_review'
          : 'keep_qwen_primary',
    );
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

  String _joinFallbackLines(List<LyricLine> lines) {
    final parts = lines
        .map((line) => line.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';

    final combined = parts.join();
    final containsCjk =
        RegExp(r'[\u3400-\u9fff\u3040-\u30ff]').hasMatch(combined);
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

  double _textSimilarity(String left, String right) {
    final a = _normalizeForComparison(left);
    final b = _normalizeForComparison(right);

    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;

    final leftRunes = a.runes.toList();
    final rightRunes = b.runes.toList();
    final distance = _levenshtein(leftRunes, rightRunes);
    final longest =
        leftRunes.length > rightRunes.length ? leftRunes.length : rightRunes.length;
    return (1.0 - distance / longest).clamp(0.0, 1.0).toDouble();
  }

  String _normalizeForComparison(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff\u3040-\u30ff]+'), '');
  }

  int _levenshtein(List<int> left, List<int> right) {
    if (left.isEmpty) return right.length;
    if (right.isEmpty) return left.length;

    var previous = List<int>.generate(right.length + 1, (index) => index);

    for (var i = 0; i < left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = i + 1;

      for (var j = 0; j < right.length; j++) {
        final substitutionCost = left[i] == right[j] ? 0 : 1;
        final deletion = previous[j + 1] + 1;
        final insertion = current[j] + 1;
        final substitution = previous[j] + substitutionCost;

        var best = deletion < insertion ? deletion : insertion;
        if (substitution < best) best = substitution;
        current[j + 1] = best;
      }

      previous = current;
    }

    return previous[right.length];
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

class _MergeResult {
  final List<LyricLine> lines;
  final List<Map<String, dynamic>> candidates;
  final int appliedCount;

  const _MergeResult({
    required this.lines,
    required this.candidates,
    required this.appliedCount,
  });
}

class _RankedCandidate {
  final int priority;
  final Map<String, dynamic> data;
  final _CandidateDecision? decision;

  const _RankedCandidate({
    required this.priority,
    required this.data,
    this.decision,
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
