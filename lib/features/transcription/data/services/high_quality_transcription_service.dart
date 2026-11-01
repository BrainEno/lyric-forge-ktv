import 'dart:async';
import 'dart:io';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/transcription_degradation.dart';
import '../../domain/models/transcription_model_identity.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_service.dart';
import 'asr_audio_normalization.dart';
import 'asr_process_supervisor.dart';

class HighQualityTranscriptionService implements TranscriptionService {
  // Surface borderline ASR disagreements for human review; never auto-apply
  // on this threshold alone.
  static const double _reviewDisagreementThreshold = 0.80;
  final TranscriptionService primary;
  final TranscriptionService fallback;

  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();

  bool _running = false;
  bool _cancelRequested = false;
  Process? _sharedNormalizationProcess;
  final AsrProcessSupervisor _processSupervisor;
  final Future<Duration> Function(String inputPath) _sharedAudioTimeoutForFile;

  /// Injectable so orchestration tests can verify the shared-input contract
  /// without depending on an installed FFmpeg executable.
  final Future<String> Function(TranscriptionRequest request)?
  sharedAudioPreparer;

  HighQualityTranscriptionService({
    required this.primary,
    required this.fallback,
    this.sharedAudioPreparer,
    AsrProcessSupervisor? processSupervisor,
    Future<Duration> Function(String inputPath)? sharedAudioTimeoutForFile,
  }) : _processSupervisor = processSupervisor ?? AsrProcessSupervisor(),
       _sharedAudioTimeoutForFile =
           sharedAudioTimeoutForFile ??
           AsrProcessTimeoutPolicy.ffmpegPreprocessingForFile;

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
      // Whisper is the baseline every mode depends on. Without it there is
      // nothing to run and nothing to degrade to.
      if (!request.config.isWhisperConfigured) {
        throw const TranscriptionException.environment(
          '尚未配置 Whisper 本地识别引擎与模型，无法识别歌词',
        );
      }

      if (request.config.mode == TranscriptionMode.whisperOnly) {
        return await _runWhisperOnly(request);
      }

      // Highest quality is a capability request: the second engine is optional
      // and its absence degrades the run instead of failing it.
      if (!request.config.isQwenConfigured) {
        return await _runDegradedToWhisper(
          request,
          reason: TranscriptionDegradationReason.qwenNotConfigured,
          detail: '未配置 Qwen3-ASR / ForcedAligner，已用 Whisper large-v3 单引擎识别',
        );
      }

      final sharedNormalizedPath =
          request.normalizedInputAudioPath ??
          await (sharedAudioPreparer ?? _prepareSharedAudio)(request);
      final sharedRequest = TranscriptionRequest(
        inputAudioPath: request.inputAudioPath,
        normalizedInputAudioPath: sharedNormalizedPath,
        outputDirectory: request.outputDirectory,
        config: request.config,
        context: request.context,
      );

      if (request.config.engineOrder ==
          TranscriptionEngineOrder.whisperPrimary) {
        return await _transcribeWhisperPrimary(sharedRequest);
      }

      TranscriptionResult primaryResult;
      try {
        primaryResult = await _runPrimary(sharedRequest);
      } on TranscriptionException catch (error) {
        if (error.message == '歌词识别已取消') rethrow;
        if (!_canDegradeToWhisper(error)) rethrow;
        // One broken engine must not cost the song. The error is recorded in
        // the document instead of escaping, so a missing driver, an exhausted
        // GPU or a moved model file still leaves a Whisper draft the user can
        // correct — and no longer pauses the whole transcription queue.
        return await _runDegradedToWhisper(
          TranscriptionRequest(
            inputAudioPath: request.inputAudioPath,
            normalizedInputAudioPath: sharedNormalizedPath,
            outputDirectory: request.outputDirectory,
            config: request.config,
            context: request.context,
          ),
          reason: TranscriptionDegradationReason.qwenUnavailable,
          detail: error.toString(),
        );
      }
      _throwIfCancelled();

      _emit(TranscriptionStage.fallback, 0.76, 'Whisper large-v3 正在进行全曲第二意见识别');

      final fallbackDirectory = Directory(
        '${request.outputDirectory}${Platform.pathSeparator}whisper_second_opinion',
      );
      await fallbackDirectory.create(recursive: true);

      TranscriptionResult fallbackResult;
      try {
        fallbackResult = await _runFallbackFullSong(
          TranscriptionRequest(
            inputAudioPath: request.inputAudioPath,
            normalizedInputAudioPath: sharedRequest.normalizedInputAudioPath,
            outputDirectory: fallbackDirectory.path,
            config: request.config.copyWith(
              mode: TranscriptionMode.whisperOnly,
            ),
            context: request.context,
          ),
        );
      } on TranscriptionException catch (error) {
        if (error.message == '歌词识别已取消') rethrow;

        _emit(TranscriptionStage.completed, 1.0, 'Qwen 识别完成，但 Whisper 第二意见失败');

        return TranscriptionResult(
          lyrics: primaryResult.lyrics.copyWith(
            metadata: {
              ...primaryResult.lyrics.metadata,
              ...TranscriptionQualityMetadata.degradedFields(
                TranscriptionDegradationReason.whisperSecondOpinionFailed,
                detail: error.toString(),
              ),
              'qualityMode': 'highestQuality',
              'primaryEngine': TranscriptionModelIdentity.qwenAsrEngine(
                request.config.qwenModelPath,
              ),
              'alignmentEngine': TranscriptionModelIdentity.qwenAlignerEngine(
                request.config.qwenAlignerModelPath,
              ),
              'fallbackEngine': TranscriptionModelIdentity.whisperEngine(
                request.config.modelPath,
              ),
              'fallbackStatus': 'failed',
              'fallbackError': error.toString(),
              'fallbackCandidateCount': 0,
              'fallbackAppliedCount': 0,
            },
          ),
          normalizedAudioPath: primaryResult.normalizedAudioPath,
          rawJsonPath: primaryResult.rawJsonPath,
          detectedLanguage: primaryResult.detectedLanguage,
        );
      }
      _throwIfCancelled();

      _emit(TranscriptionStage.parsing, 0.96, '正在比较 Qwen 与 Whisper 的歌词分歧');

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
          'primaryEngine': TranscriptionModelIdentity.qwenAsrEngine(
            request.config.qwenModelPath,
          ),
          'alignmentEngine': TranscriptionModelIdentity.qwenAlignerEngine(
            request.config.qwenAlignerModelPath,
          ),
          'fallbackEngine': TranscriptionModelIdentity.whisperEngine(
            request.config.modelPath,
          ),
          'fallbackStrategy': 'fullSongSecondOpinion',
          'fallbackStatus': 'completed',
          'fallbackCandidateCount': merge.candidates.length,
          'fallbackAppliedCount': merge.appliedCount,
          'fallbackCandidates': merge.candidates,
          'secondaryOnlyLineCount': merge.secondaryOnlyLineIndices.length,
          'secondaryOnlyLineIndices': merge.secondaryOnlyLineIndices,
          'fusionPolicy':
              'add_unmatched_secondary_as_low_confidence_review_lines',
          'whisperRawJsonPath': fallbackResult.rawJsonPath,
        },
      );

      _emit(
        TranscriptionStage.completed,
        1.0,
        [
          '最高质量识别完成',
          if (merge.secondaryOnlyLineIndices.isNotEmpty)
            '补入 ${merge.secondaryOnlyLineIndices.length} 行备用引擎独有歌词（低置信待复核）',
          if (merge.candidates.isNotEmpty)
            '发现 ${merge.candidates.length} 行需要重点校对',
          if (merge.candidates.isEmpty &&
              merge.secondaryOnlyLineIndices.isEmpty)
            '两套引擎结果未发现明显分歧',
        ].join('；'),
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

  Future<String> _prepareSharedAudio(TranscriptionRequest request) async {
    _throwIfCancelled();
    if (!await File(request.inputAudioPath).exists()) {
      throw const TranscriptionException.input('待识别音频文件不存在');
    }

    final outputDirectory = Directory(request.outputDirectory);
    await outputDirectory.create(recursive: true);
    final output = File(
      '${outputDirectory.path}${Platform.pathSeparator}high_quality_shared_input.wav',
    );
    final inputPath = File(request.inputAudioPath).absolute.path;
    final outputPath = output.absolute.path;
    final samePath = Platform.isWindows
        ? inputPath.toLowerCase() == outputPath.toLowerCase()
        : inputPath == outputPath;
    if (samePath) {
      throw const TranscriptionException.input('共享标准化音频输出路径不能覆盖原始音频');
    }
    if (await output.exists()) {
      try {
        await output.delete();
      } on FileSystemException catch (error) {
        throw TranscriptionException.environment(
          '无法替换上一次双引擎共享音频',
          details: error.message,
        );
      }
    }

    var succeeded = false;
    try {
      _throwIfCancelled();
      _emit(
        TranscriptionStage.preprocessing,
        0.01,
        '正在为双引擎生成一次共享的 16 kHz 单声道输入',
      );

      final timeout = await _sharedAudioTimeoutForFile(request.inputAudioPath);
      final result = await _processSupervisor.run(
        request.config.ffmpegExecutable,
        AsrAudioNormalization.ffmpegArguments(
          inputPath: request.inputAudioPath,
          outputPath: output.path,
        ),
        timeout: timeout,
        operation: '最高质量共享音频预处理',
        maxOutputLines: 80,
        maxLineLength: 2048,
        onProcessChanged: (process) {
          _sharedNormalizationProcess = process;
          if (process != null && _cancelRequested) {
            unawaited(_processSupervisor.terminate(process));
          }
        },
      );

      _throwIfCancelled();
      final diagnostic = result.stderrTail.join('\n');
      if (result.exitCode != 0) {
        throw TranscriptionException.input(
          'FFmpeg 双引擎共享音频预处理失败',
          details: diagnostic,
        );
      }
      if (!await output.exists() || await output.length() <= 44) {
        throw TranscriptionException.input(
          'FFmpeg 未生成有效的双引擎共享 WAV 文件',
          details: diagnostic.isEmpty ? null : diagnostic,
        );
      }

      succeeded = true;
      return output.path;
    } on AsrProcessTimeoutException catch (error) {
      _throwIfCancelled();
      throw TranscriptionException.environment(
        'FFmpeg 双引擎共享音频预处理超时',
        details: error.toString(),
      );
    } on ProcessException catch (error) {
      _throwIfCancelled();
      throw TranscriptionException.environment(
        '无法启动 FFmpeg 生成双引擎共享音频',
        details: error.message,
      );
    } finally {
      _sharedNormalizationProcess = null;
      if (!succeeded && await output.exists()) {
        try {
          await output.delete();
        } on FileSystemException {
          // Preserve the original processing error if cleanup also fails.
        }
      }
    }
  }

  Future<TranscriptionResult> _transcribeWhisperPrimary(
    TranscriptionRequest request,
  ) async {
    final qwenModelKey = TranscriptionModelIdentity.qwenAsrEngine(
      request.config.qwenModelPath,
    );
    final qwenModelLabel = TranscriptionModelIdentity.qwenAsrLabel(
      request.config.qwenModelPath,
    );

    _emit(TranscriptionStage.transcribing, 0.02, 'Whisper large-v3 正在进行主识别');

    final whisperSubscription = fallback.progressStream.listen((progress) {
      if (_cancelRequested) return;
      final mapped = 0.02 + progress.progress * 0.54;
      _emit(
        progress.stage,
        mapped.clamp(0.02, 0.56).toDouble(),
        'Whisper 主识别 · ${progress.message}',
      );
    });

    late final TranscriptionResult whisperResult;
    try {
      whisperResult = await fallback.transcribe(
        TranscriptionRequest(
          inputAudioPath: request.inputAudioPath,
          normalizedInputAudioPath: request.normalizedInputAudioPath,
          outputDirectory:
              '${request.outputDirectory}${Platform.pathSeparator}whisper_primary',
          config: request.config.copyWith(mode: TranscriptionMode.whisperOnly),
          context: request.context,
        ),
      );
    } finally {
      await whisperSubscription.cancel();
    }

    _throwIfCancelled();

    _emit(TranscriptionStage.fallback, 0.58, '$qwenModelLabel 正在进行第二意见识别');

    final qwenDirectory = Directory(
      '${request.outputDirectory}${Platform.pathSeparator}qwen_second_opinion',
    );
    await qwenDirectory.create(recursive: true);

    TranscriptionResult qwenResult;
    try {
      final qwenSubscription = primary.progressStream.listen((progress) {
        if (_cancelRequested) return;
        final mapped = 0.58 + progress.progress * 0.34;
        _emit(
          TranscriptionStage.fallback,
          mapped.clamp(0.58, 0.92).toDouble(),
          'Qwen 第二意见 · ${progress.message}',
        );
      });

      try {
        qwenResult = await primary.transcribe(
          TranscriptionRequest(
            inputAudioPath: request.inputAudioPath,
            normalizedInputAudioPath: request.normalizedInputAudioPath,
            outputDirectory: qwenDirectory.path,
            config: request.config,
            context: request.context,
          ),
        );
      } finally {
        await qwenSubscription.cancel();
      }
    } on TranscriptionException catch (error) {
      if (error.message == '歌词识别已取消') rethrow;

      _emit(TranscriptionStage.completed, 1.0, 'Whisper 主识别完成，但 Qwen 第二意见失败');

      return TranscriptionResult(
        lyrics: whisperResult.lyrics.copyWith(
          metadata: {
            ...whisperResult.lyrics.metadata,
            ...TranscriptionQualityMetadata.degradedFields(
              TranscriptionDegradationReason.qwenSecondOpinionFailed,
              detail: error.toString(),
            ),
            'qualityMode': 'highestQuality',
            'primaryEngine': TranscriptionModelIdentity.whisperEngine(
              request.config.modelPath,
            ),
            'alignmentEngine': 'whisper-segment-timestamps',
            'fallbackEngine': qwenModelKey,
            'fallbackAlignmentEngine':
                TranscriptionModelIdentity.qwenAlignerEngine(
                  request.config.qwenAlignerModelPath,
                ),
            'fallbackStatus': 'failed',
            'fallbackError': error.toString(),
            'fallbackCandidateCount': 0,
            'fallbackAppliedCount': 0,
          },
        ),
        normalizedAudioPath: whisperResult.normalizedAudioPath,
        rawJsonPath: whisperResult.rawJsonPath,
        detectedLanguage: whisperResult.detectedLanguage,
      );
    }

    _throwIfCancelled();

    _emit(TranscriptionStage.parsing, 0.95, '正在比较 Whisper 与 Qwen 的歌词分歧');

    final merge = _mergeWhisperPrimaryResults(
      whisperPrimary: whisperResult.lyrics,
      qwenSecondOpinion: qwenResult.lyrics,
      config: request.config,
    );

    final mergedDocument = whisperResult.lyrics.copyWith(
      lines: merge.lines,
      metadata: {
        ...whisperResult.lyrics.metadata,
        'qualityMode': 'highestQuality',
        'primaryEngine': TranscriptionModelIdentity.whisperEngine(
          request.config.modelPath,
        ),
        'alignmentEngine': 'whisper-segment-timestamps',
        'fallbackEngine': qwenModelKey,
        'fallbackAlignmentEngine': TranscriptionModelIdentity.qwenAlignerEngine(
          request.config.qwenAlignerModelPath,
        ),
        'fallbackStrategy': 'fullSongSecondOpinion',
        'fallbackStatus': 'completed',
        'fallbackCandidateCount': merge.candidates.length,
        'fallbackAppliedCount': merge.appliedCount,
        'fallbackCandidates': merge.candidates,
        'secondaryOnlyLineCount': merge.secondaryOnlyLineIndices.length,
        'secondaryOnlyLineIndices': merge.secondaryOnlyLineIndices,
        'fusionPolicy':
            'add_unmatched_secondary_as_low_confidence_review_lines',
        'qwenRawJsonPath': qwenResult.rawJsonPath,
      },
    );

    _emit(
      TranscriptionStage.completed,
      1.0,
      [
        '最高质量识别完成',
        if (merge.secondaryOnlyLineIndices.isNotEmpty)
          '补入 ${merge.secondaryOnlyLineIndices.length} 行备用引擎独有歌词（低置信待复核）',
        if (merge.candidates.isNotEmpty)
          '发现 ${merge.candidates.length} 行需要重点校对',
        if (merge.candidates.isEmpty && merge.secondaryOnlyLineIndices.isEmpty)
          '两套引擎结果未发现明显分歧',
      ].join('；'),
    );

    return TranscriptionResult(
      lyrics: mergedDocument,
      normalizedAudioPath: whisperResult.normalizedAudioPath,
      rawJsonPath: whisperResult.rawJsonPath,
      detectedLanguage: whisperResult.detectedLanguage,
    );
  }

  _MergeResult _mergeWhisperPrimaryResults({
    required LyricDocument whisperPrimary,
    required LyricDocument qwenSecondOpinion,
    required TranscriptionConfig config,
  }) {
    final lines = List<LyricLine>.from(whisperPrimary.lines);
    final candidates = <_RankedCandidate>[];
    final matchedSecondaryIndices = <int>{};

    for (var index = 0; index < whisperPrimary.lines.length; index++) {
      final whisperLine = whisperPrimary.lines[index];
      final overlappingIndices = _overlappingLineIndices(
        whisperLine,
        qwenSecondOpinion.lines,
      );
      final correspondingIndices = _correspondingSecondaryLineIndices(
        primaryLine: whisperLine,
        secondaryLines: qwenSecondOpinion.lines,
        overlappingIndices: overlappingIndices,
      );
      matchedSecondaryIndices.addAll(correspondingIndices);
      final qwenLines = [
        for (final secondaryIndex in correspondingIndices)
          qwenSecondOpinion.lines[secondaryIndex],
      ];

      if (qwenLines.isEmpty) {
        if (_isPrimarySuspicious(whisperLine, config)) {
          candidates.add(
            _RankedCandidate(
              priority: 100 - whisperLine.confidence,
              data: {
                'lineIndex': index,
                'startMs': whisperLine.startTime.inMilliseconds,
                'endMs': whisperLine.endTime.inMilliseconds,
                'primaryEngine': 'whisper',
                'primaryText': whisperLine.text,
                'primaryConfidence': whisperLine.confidence,
                'whisperText': whisperLine.text,
                'whisperConfidence': whisperLine.confidence,
                'selected': 'whisper',
                'reason': overlappingIndices.isEmpty
                    ? 'qwen_no_overlap'
                    : 'qwen_no_corresponding_line',
              },
            ),
          );
        }
        continue;
      }

      final qwenText = _joinFallbackLines(qwenLines);
      final qwenConfidence = _averageConfidence(qwenLines);
      final similarity = _textSimilarity(whisperLine.text, qwenText);
      final durationRatio = _durationRatio(whisperLine, qwenLines);

      final suspicious =
          _isPrimarySuspicious(whisperLine, config) ||
          similarity < _reviewDisagreementThreshold;
      if (!suspicious) continue;

      final decision = _decideWhisperPrimaryCandidate(
        whisperLine: whisperLine,
        qwenText: qwenText,
        qwenConfidence: qwenConfidence,
        similarity: similarity,
        durationRatio: durationRatio,
      );

      candidates.add(
        _RankedCandidate(
          priority: _candidatePriority(
            qwenLine: whisperLine,
            similarity: similarity,
          ),
          data: {
            'lineIndex': index,
            'startMs': whisperLine.startTime.inMilliseconds,
            'endMs': whisperLine.endTime.inMilliseconds,
            'primaryEngine': 'whisper',
            'primaryText': whisperLine.text,
            'primaryConfidence': whisperLine.confidence,
            'alternativeEngine': 'qwen',
            'alternativeText': qwenText,
            'alternativeConfidence': qwenConfidence,
            'whisperText': whisperLine.text,
            'whisperConfidence': whisperLine.confidence,
            'qwenText': qwenText,
            'qwenConfidence': qwenConfidence,
            'similarity': double.parse(similarity.toStringAsFixed(3)),
            'durationRatio': double.parse(durationRatio.toStringAsFixed(3)),
            'selected': decision.useAlternative ? 'qwen' : 'whisper',
            'reason': decision.reason,
          },
          alternativeDecision: decision,
        ),
      );
    }

    candidates.sort((a, b) => b.priority.compareTo(a.priority));
    final limited = candidates
        .take(config.maxFallbackSegments)
        .toList(growable: false);

    var appliedCount = 0;
    for (final candidate in limited) {
      final decision = candidate.alternativeDecision;
      if (decision == null || !decision.useAlternative) continue;

      final index = candidate.data['lineIndex'] as int;
      final qwenText = candidate.data['qwenText'] as String;
      lines[index] = lines[index].copyWith(
        text: qwenText,
        confidence: decision.outputConfidence,
        // The fused score is this service's policy, not the engine's number.
        confidenceSource: LyricConfidenceSource.heuristic,
      );
      appliedCount++;
    }

    final timeline = _mergeUnmatchedSecondaryLines(
      primaryLines: lines,
      secondaryLines: qwenSecondOpinion.lines,
      matchedSecondaryIndices: matchedSecondaryIndices,
    );
    final remappedCandidates = _remapCandidateIndices(
      limited.map((candidate) => candidate.data).toList(growable: false),
      timeline.primaryIndexToMergedIndex,
    );

    return _MergeResult(
      lines: timeline.lines,
      candidates: remappedCandidates,
      appliedCount: appliedCount,
      secondaryOnlyLineIndices: timeline.secondaryOnlyLineIndices,
    );
  }

  _AlternativeDecision _decideWhisperPrimaryCandidate({
    required LyricLine whisperLine,
    required String qwenText,
    required int qwenConfidence,
    required double similarity,
    required double durationRatio,
  }) {
    final whisperSuspicious = _hasSuspiciousRepetition(whisperLine.text);
    final qwenSuspicious = _hasSuspiciousRepetition(qwenText);
    final timingCompatible = durationRatio >= 0.55 && durationRatio <= 1.80;

    if (timingCompatible &&
        whisperSuspicious &&
        !qwenSuspicious &&
        qwenConfidence >= 55 &&
        similarity < 0.82) {
      return _AlternativeDecision(
        useAlternative: true,
        outputConfidence: qwenConfidence.clamp(55, 85).toInt(),
        reason: 'whisper_repetition',
      );
    }

    if (timingCompatible &&
        whisperLine.confidence <= 45 &&
        !qwenSuspicious &&
        qwenConfidence >= whisperLine.confidence + 12 &&
        similarity < 0.75) {
      return _AlternativeDecision(
        useAlternative: true,
        outputConfidence: qwenConfidence.clamp(50, 85).toInt(),
        reason: 'qwen_materially_stronger',
      );
    }

    return _AlternativeDecision(
      useAlternative: false,
      outputConfidence: whisperLine.confidence,
      reason: similarity < _reviewDisagreementThreshold
          ? 'engine_disagreement_review'
          : 'keep_whisper_primary',
    );
  }

  /// Whether an engine failure is about the engine rather than the audio.
  ///
  /// Input problems (missing, unreadable or unsupported audio) are engine
  /// independent: Whisper would fail the same way, so surfacing the original
  /// error is more useful than running the second engine to collect an
  /// identical complaint. Cancellation is never a reason to keep working.
  static bool _canDegradeToWhisper(TranscriptionException error) {
    return error.kind != TranscriptionFailureKind.cancelled &&
        error.kind != TranscriptionFailureKind.input;
  }

  /// Produces a Whisper draft when the second engine cannot contribute.
  ///
  /// Used both when Qwen is absent from the configuration and when it fails at
  /// run time. The reason travels with the document so the editor and project
  /// panel can state it plainly; presenting a single-engine draft as
  /// "highest quality" is exactly the kind of silent downgrade users read as
  /// "the app got worse".
  Future<TranscriptionResult> _runDegradedToWhisper(
    TranscriptionRequest request, {
    required TranscriptionDegradationReason reason,
    required String detail,
  }) async {
    _throwIfCancelled();
    _emit(TranscriptionStage.fallback, 0.05, reason.message);

    final directory = Directory(
      '${request.outputDirectory}${Platform.pathSeparator}whisper_degraded',
    );
    await directory.create(recursive: true);

    final subscription = fallback.progressStream.listen((progress) {
      if (_cancelRequested) return;
      final mapped = 0.05 + progress.progress * 0.9;
      _emit(
        progress.stage,
        mapped.clamp(0.05, 0.97).toDouble(),
        'Whisper 降级识别 · ${progress.message}',
      );
    });

    TranscriptionResult result;
    try {
      result = await fallback.transcribe(
        TranscriptionRequest(
          inputAudioPath: request.inputAudioPath,
          normalizedInputAudioPath: request.normalizedInputAudioPath,
          outputDirectory: directory.path,
          config: request.config.copyWith(mode: TranscriptionMode.whisperOnly),
          context: request.context,
        ),
      );
    } on TranscriptionException catch (error) {
      if (error.message == '歌词识别已取消') rethrow;
      // Whisper is the last engine standing. Report both failures so the user
      // sees the root cause, not just "the fallback failed too".
      throw TranscriptionException(
        '已降级为 Whisper 单引擎识别，但 Whisper 也失败了：${error.message}',
        details: [
          '降级原因：$detail',
          if (error.details != null && error.details!.trim().isNotEmpty)
            'Whisper：${error.details}',
        ].join('\n'),
        kind: error.kind,
      );
    } finally {
      await subscription.cancel();
    }

    _throwIfCancelled();
    _emit(TranscriptionStage.completed, 1.0, reason.message);

    return TranscriptionResult(
      lyrics: result.lyrics.copyWith(
        metadata: {
          ...result.lyrics.metadata,
          'qualityMode': 'highestQuality',
          TranscriptionQualityMetadata.requestedModeKey: 'highestQuality',
          ...TranscriptionQualityMetadata.degradedFields(
            reason,
            detail: detail,
          ),
          'primaryEngine': TranscriptionModelIdentity.whisperEngine(
            request.config.modelPath,
          ),
          'alignmentEngine': 'whisper-segment-timestamps',
          'fallbackStatus': 'degraded',
          'fallbackCandidateCount': 0,
          'fallbackAppliedCount': 0,
        },
      ),
      normalizedAudioPath: result.normalizedAudioPath,
      rawJsonPath: result.rawJsonPath,
      detectedLanguage: result.detectedLanguage,
    );
  }

  Future<TranscriptionResult> _runPrimary(TranscriptionRequest request) async {
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
        'Whisper 第二意见 · ${progress.message}',
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
    final matchedSecondaryIndices = <int>{};

    for (var index = 0; index < primary.lines.length; index++) {
      final qwenLine = primary.lines[index];
      final overlappingIndices = _overlappingLineIndices(
        qwenLine,
        fallback.lines,
      );
      final correspondingIndices = _correspondingSecondaryLineIndices(
        primaryLine: qwenLine,
        secondaryLines: fallback.lines,
        overlappingIndices: overlappingIndices,
      );
      matchedSecondaryIndices.addAll(correspondingIndices);
      final whisperLines = [
        for (final secondaryIndex in correspondingIndices)
          fallback.lines[secondaryIndex],
      ];
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
                'reason': overlappingIndices.isEmpty
                    ? 'whisper_no_overlap'
                    : 'whisper_no_corresponding_line',
              },
            ),
          );
        }
        continue;
      }

      final whisperText = _joinFallbackLines(whisperLines);
      final whisperConfidence = _averageConfidence(whisperLines);
      final similarity = _textSimilarity(qwenLine.text, whisperText);
      final durationRatio = _durationRatio(qwenLine, whisperLines);

      final suspicious =
          _isPrimarySuspicious(qwenLine, config) ||
          similarity < _reviewDisagreementThreshold;
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
            'primaryEngine': 'qwen',
            'primaryText': qwenLine.text,
            'primaryConfidence': qwenLine.confidence,
            'alternativeEngine': 'whisper',
            'alternativeText': whisperText,
            'alternativeConfidence': whisperConfidence,
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
        confidenceSource: LyricConfidenceSource.heuristic,
      );
      appliedCount++;
    }

    final timeline = _mergeUnmatchedSecondaryLines(
      primaryLines: lines,
      secondaryLines: fallback.lines,
      matchedSecondaryIndices: matchedSecondaryIndices,
    );
    final remappedCandidates = _remapCandidateIndices(
      limited.map((candidate) => candidate.data).toList(growable: false),
      timeline.primaryIndexToMergedIndex,
    );

    return _MergeResult(
      lines: timeline.lines,
      candidates: remappedCandidates,
      appliedCount: appliedCount,
      secondaryOnlyLineIndices: timeline.secondaryOnlyLineIndices,
    );
  }

  bool _isPrimarySuspicious(LyricLine line, TranscriptionConfig config) {
    return line.confidence < config.fallbackConfidenceThreshold ||
        _hasSuspiciousRepetition(line.text) ||
        _looksTimingSuspicious(line);
  }

  List<int> _overlappingLineIndices(
    LyricLine target,
    List<LyricLine> candidates,
  ) {
    final paddedStart = target.startTime - const Duration(milliseconds: 450);
    final paddedEnd = target.endTime + const Duration(milliseconds: 450);
    final result = <int>[];

    for (var index = 0; index < candidates.length; index++) {
      final line = candidates[index];
      final overlapStart = line.startTime > paddedStart
          ? line.startTime
          : paddedStart;
      final overlapEnd = line.endTime < paddedEnd ? line.endTime : paddedEnd;

      if (overlapEnd > overlapStart) result.add(index);
    }
    return result;
  }

  /// Select secondary rows that plausibly describe the same lyric as the
  /// primary row. Timestamp overlap is only a search window: a distinct
  /// ad-lib or omitted line can occur inside a long primary segment.
  List<int> _correspondingSecondaryLineIndices({
    required LyricLine primaryLine,
    required List<LyricLine> secondaryLines,
    required List<int> overlappingIndices,
  }) {
    return [
      for (final index in overlappingIndices)
        if (_isLikelySameLyricLine(primaryLine, secondaryLines[index])) index,
    ];
  }

  bool _isLikelySameLyricLine(LyricLine primaryLine, LyricLine secondaryLine) {
    final primaryText = _normalizeForComparison(primaryLine.text);
    final secondaryText = _normalizeForComparison(secondaryLine.text);
    if (primaryText.isEmpty || secondaryText.isEmpty) return false;
    if (primaryText == secondaryText) return true;

    final primaryContainsSecondary = primaryText.contains(secondaryText);
    final secondaryContainsPrimary = secondaryText.contains(primaryText);
    if (primaryContainsSecondary || secondaryContainsPrimary) {
      // One row's text sits inside the other's. Whether that is the same lyric
      // re-segmented or a genuinely different row is decided by the timestamps.
      final fullLine = primaryContainsSecondary ? primaryLine : secondaryLine;
      final fragmentLine = primaryContainsSecondary
          ? secondaryLine
          : primaryLine;

      // A row whose text is already inside the other engine's line and whose
      // time span sits inside that same line is the same lyric, re-segmented.
      // Inserting it cannot add words the user cannot already read; it only
      // duplicates them. Text-position pacing is deliberately not consulted
      // here: singers hold notes and ASR timings are noisy, so the proportional
      // estimate below rejects genuine fragments and floods the document.
      if (_spanContains(fullLine, fragmentLine)) return true;

      final fullText = primaryContainsSecondary ? primaryText : secondaryText;
      final fragmentText = primaryContainsSecondary
          ? secondaryText
          : primaryText;
      return _containedFragmentMatchesTimeline(
        fullText: fullText,
        fragmentText: fragmentText,
        fullLine: fullLine,
        fragmentLine: fragmentLine,
      );
    }

    final primaryDuration =
        (primaryLine.endTime - primaryLine.startTime).inMilliseconds;
    final secondaryDuration =
        (secondaryLine.endTime - secondaryLine.startTime).inMilliseconds;
    if (primaryDuration <= 0 || secondaryDuration <= 0) return false;

    final overlapStart = primaryLine.startTime > secondaryLine.startTime
        ? primaryLine.startTime
        : secondaryLine.startTime;
    final overlapEnd = primaryLine.endTime < secondaryLine.endTime
        ? primaryLine.endTime
        : secondaryLine.endTime;
    final overlapMs = (overlapEnd - overlapStart).inMilliseconds;
    final shorterDuration = primaryDuration < secondaryDuration
        ? primaryDuration
        : secondaryDuration;
    final longerDuration = primaryDuration > secondaryDuration
        ? primaryDuration
        : secondaryDuration;
    final overlapRatio = overlapMs <= 0 ? 0.0 : overlapMs / shorterDuration;
    final similarity = _textSimilarity(primaryLine.text, secondaryLine.text);

    // Lexically similar alternatives must also describe comparable time spans;
    // a short nested line inside a long segment is not enough.
    if (similarity >= 0.55 &&
        overlapRatio >= 0.65 &&
        longerDuration / shorterDuration <= 2.0) {
      return true;
    }

    // A strong boundary match is enough to pair different hypotheses for the
    // same segment, but merely sitting inside another line is not.
    final startDelta = (primaryLine.startTime - secondaryLine.startTime)
        .inMilliseconds
        .abs();
    final endDelta = (primaryLine.endTime - secondaryLine.endTime)
        .inMilliseconds
        .abs();
    return startDelta <= 350 &&
        endDelta <= 350 &&
        longerDuration / shorterDuration <= 2.0;
  }

  /// True when [inner]'s time span lies inside [outer]'s span, allowing the
  /// boundary jitter that two recognizers always disagree about.
  bool _spanContains(LyricLine outer, LyricLine inner) {
    const tolerance = Duration(milliseconds: 400);
    return inner.startTime >= outer.startTime - tolerance &&
        inner.endTime <= outer.endTime + tolerance;
  }

  bool _containedFragmentMatchesTimeline({
    required String fullText,
    required String fragmentText,
    required LyricLine fullLine,
    required LyricLine fragmentLine,
  }) {
    final fullDuration = (fullLine.endTime - fullLine.startTime).inMilliseconds;
    if (fullDuration <= 0 || fullText.isEmpty) return false;

    final fragmentStart = fullText.indexOf(fragmentText);
    if (fragmentStart < 0) return false;
    final fragmentEnd = fragmentStart + fragmentText.length;
    final isPrefix = fragmentStart / fullText.length <= 0.10;
    final trailingLength = fullText.length - fragmentEnd;
    final isSuffix = trailingLength / fullText.length <= 0.10;
    final startDelta = (fragmentLine.startTime - fullLine.startTime)
        .inMilliseconds
        .abs();
    final endDelta = (fragmentLine.endTime - fullLine.endTime).inMilliseconds
        .abs();

    if (isPrefix && startDelta <= 450) return true;
    if (isSuffix && endDelta <= 450) return true;

    // For an internal fragment, compare its observed boundaries with a loose
    // text-position estimate. The tolerance accounts for uneven singing pace;
    // when timing does not fit, retain the fragment as a review-only extra row.
    final expectedStartMs = (fullDuration * fragmentStart / fullText.length)
        .round();
    final expectedEndMs = (fullDuration * fragmentEnd / fullText.length)
        .round();
    final proportionalTolerance = (fullDuration * 0.18).round();
    final toleranceMs = proportionalTolerance > 350
        ? proportionalTolerance
        : 350;
    final expectedStart =
        fullLine.startTime + Duration(milliseconds: expectedStartMs);
    final expectedEnd =
        fullLine.startTime + Duration(milliseconds: expectedEndMs);
    final positionedStartDelta = (fragmentLine.startTime - expectedStart)
        .inMilliseconds
        .abs();
    final positionedEndDelta = (fragmentLine.endTime - expectedEnd)
        .inMilliseconds
        .abs();

    return positionedStartDelta <= toleranceMs &&
        positionedEndDelta <= toleranceMs;
  }

  /// Retain useful lines found only by the secondary recognizer instead of
  /// silently discarding them. They are inserted on the time axis with a
  /// deliberately capped confidence so the editor forces human review.
  _MergedTimeline _mergeUnmatchedSecondaryLines({
    required List<LyricLine> primaryLines,
    required List<LyricLine> secondaryLines,
    required Set<int> matchedSecondaryIndices,
  }) {
    final entries = <_MergedTimelineEntry>[
      for (var index = 0; index < primaryLines.length; index++)
        _MergedTimelineEntry(
          line: primaryLines[index],
          primaryIndex: index,
          secondaryOnly: false,
        ),
    ];

    for (var index = 0; index < secondaryLines.length; index++) {
      if (matchedSecondaryIndices.contains(index)) continue;
      final line = secondaryLines[index];
      if (line.text.trim().isEmpty ||
          line.startTime.isNegative ||
          line.endTime <= line.startTime) {
        continue;
      }
      entries.add(
        _MergedTimelineEntry(
          line: line.copyWith(
            confidence: line.confidence.clamp(0, 60).toInt(),
            // The clamped value is this service's review policy, not the
            // engine's score, so it is labelled as a heuristic.
            confidenceSource: LyricConfidenceSource.heuristic,
          ),
          primaryIndex: null,
          secondaryOnly: true,
        ),
      );
    }

    entries.sort((left, right) {
      final byStart = left.line.startTime.compareTo(right.line.startTime);
      if (byStart != 0) return byStart;
      final byEnd = left.line.endTime.compareTo(right.line.endTime);
      if (byEnd != 0) return byEnd;
      // Preserve the primary row before a secondary suggestion at identical
      // times so existing lyric rows remain stable in tie cases.
      if (left.secondaryOnly != right.secondaryOnly) {
        return left.secondaryOnly ? 1 : -1;
      }
      return (left.primaryIndex ?? 0).compareTo(right.primaryIndex ?? 0);
    });

    final primaryIndexToMergedIndex = <int, int>{};
    final secondaryOnlyLineIndices = <int>[];
    final mergedLines = <LyricLine>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      mergedLines.add(entry.line);
      final primaryIndex = entry.primaryIndex;
      if (primaryIndex != null) {
        primaryIndexToMergedIndex[primaryIndex] = index;
      }
      if (entry.secondaryOnly) secondaryOnlyLineIndices.add(index);
    }

    return _MergedTimeline(
      lines: List.unmodifiable(mergedLines),
      primaryIndexToMergedIndex: Map.unmodifiable(primaryIndexToMergedIndex),
      secondaryOnlyLineIndices: List.unmodifiable(secondaryOnlyLineIndices),
    );
  }

  List<Map<String, dynamic>> _remapCandidateIndices(
    List<Map<String, dynamic>> candidates,
    Map<int, int> primaryIndexToMergedIndex,
  ) {
    return [
      for (final candidate in candidates)
        () {
          final remapped = Map<String, dynamic>.from(candidate);
          final index = remapped['lineIndex'];
          if (index is num) {
            remapped['lineIndex'] =
                primaryIndexToMergedIndex[index.toInt()] ?? index.toInt();
          }
          return remapped;
        }(),
    ];
  }

  double _durationRatio(LyricLine qwenLine, List<LyricLine> whisperLines) {
    if (whisperLines.isEmpty) return 0.0;

    final qwenDuration = (qwenLine.endTime - qwenLine.startTime).inMilliseconds;
    final whisperStart = whisperLines
        .map((line) => line.startTime)
        .reduce((a, b) => a < b ? a : b);
    final whisperEnd = whisperLines
        .map((line) => line.endTime)
        .reduce((a, b) => a > b ? a : b);
    final whisperDuration = (whisperEnd - whisperStart).inMilliseconds;

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
      reason: similarity < _reviewDisagreementThreshold
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
    final containsCjk = RegExp(
      r'[\u3400-\u9fff\u3040-\u30ff]',
    ).hasMatch(combined);
    return parts.join(containsCjk ? '' : ' ').trim();
  }

  int _averageConfidence(List<LyricLine> lines) {
    if (lines.isEmpty) return 0;
    final total = lines.fold<int>(0, (sum, line) => sum + line.confidence);
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
    final longest = leftRunes.length > rightRunes.length
        ? leftRunes.length
        : rightRunes.length;
    return (1.0 - distance / longest).clamp(0.0, 1.0).toDouble();
  }

  String _normalizeForComparison(String value) {
    return value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9\u3400-\u9fff\u3040-\u30ff]+'),
      '',
    );
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

  void _emit(TranscriptionStage stage, double progress, String message) {
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
    final process = _sharedNormalizationProcess;
    if (process != null) await _processSupervisor.terminate(process);
    await Future.wait([primary.cancel(), fallback.cancel()]);
  }

  @override
  Future<void> dispose() async {
    _cancelRequested = true;
    final process = _sharedNormalizationProcess;
    if (process != null) await _processSupervisor.terminate(process);
    await primary.dispose();
    await fallback.dispose();
    await _progressController.close();
  }
}

class _MergeResult {
  final List<LyricLine> lines;
  final List<Map<String, dynamic>> candidates;
  final int appliedCount;
  final List<int> secondaryOnlyLineIndices;

  const _MergeResult({
    required this.lines,
    required this.candidates,
    required this.appliedCount,
    this.secondaryOnlyLineIndices = const [],
  });
}

class _MergedTimeline {
  final List<LyricLine> lines;
  final Map<int, int> primaryIndexToMergedIndex;
  final List<int> secondaryOnlyLineIndices;

  const _MergedTimeline({
    required this.lines,
    required this.primaryIndexToMergedIndex,
    required this.secondaryOnlyLineIndices,
  });
}

class _MergedTimelineEntry {
  final LyricLine line;
  final int? primaryIndex;
  final bool secondaryOnly;

  const _MergedTimelineEntry({
    required this.line,
    required this.primaryIndex,
    required this.secondaryOnly,
  });
}

class _RankedCandidate {
  final int priority;
  final Map<String, dynamic> data;
  final _CandidateDecision? decision;
  final _AlternativeDecision? alternativeDecision;

  const _RankedCandidate({
    required this.priority,
    required this.data,
    this.decision,
    this.alternativeDecision,
  });
}

class _AlternativeDecision {
  final bool useAlternative;
  final int outputConfidence;
  final String reason;

  const _AlternativeDecision({
    required this.useAlternative,
    required this.outputConfidence,
    required this.reason,
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
