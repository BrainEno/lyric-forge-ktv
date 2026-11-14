import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/asr_confidence.dart';
import '../../domain/models/qwen_decode_budget.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_service.dart';
import 'asr_audio_normalization.dart';
import 'asr_process_supervisor.dart';
import 'forced_alignment_http_client.dart';
import 'qwen_runtime_session.dart';

class Qwen3AsrNativeTranscriptionService implements TranscriptionService {
  Qwen3AsrNativeTranscriptionService({
    AsrProcessSupervisor? processSupervisor,
    QwenRuntimeLauncher? runtimeLauncher,
    HttpClient? httpClient,
    this.runtimeStartupTimeout = const Duration(minutes: 2),
    this.idleShutdownDelay = const Duration(minutes: 10),
  }) : _processSupervisor = processSupervisor ?? AsrProcessSupervisor(),
       _httpClient =
           httpClient ?? (HttpClient()..connectionTimeout = _connectTimeout) {
    _runtimeLauncher =
        runtimeLauncher ?? QwenRuntimeLauncher(supervisor: _processSupervisor);
  }

  static const Duration _connectTimeout = Duration(seconds: 10);

  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();
  final AsrProcessSupervisor _processSupervisor;
  late final QwenRuntimeLauncher _runtimeLauncher;
  final HttpClient _httpClient;
  final Duration runtimeStartupTimeout;
  final Duration idleShutdownDelay;

  /// The only authenticated runtime this service may talk to. Replaced (with
  /// a fresh secret) on restart, config change, crash, cancel and dispose.
  QwenRuntimeSession? _session;
  HttpClientRequest? _activeRequest;
  ForcedAlignmentHttpClient? _activeAlignmentClient;
  Process? _activeToolProcess;
  Timer? _idleShutdownTimer;

  String? _serverKey;

  /// Bumped by cancel/dispose so a launch that finishes afterwards is closed
  /// instead of being adopted as a second, orphaned session.
  int _lifecycleGeneration = 0;
  bool _running = false;
  bool _cancelRequested = false;

  /// Test/diagnostic view: whether an authenticated runtime is attached.
  bool get hasRuntimeSession => _session != null;

  @override
  Stream<TranscriptionProgress> get progressStream =>
      _progressController.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    if (_running) {
      throw const TranscriptionException.busy('Qwen3-ASR 已有识别任务正在运行');
    }

    _running = true;
    _cancelRequested = false;
    _idleShutdownTimer?.cancel();
    _idleShutdownTimer = null;

    try {
      _emit(TranscriptionStage.validating, 0.02, '正在检查 Qwen3-ASR 高质量运行环境');
      await _validateRequest(request);
      _throwIfCancelled();

      final outputDirectory = Directory(request.outputDirectory);
      await outputDirectory.create(recursive: true);

      final normalizedPath =
          request.normalizedInputAudioPath ??
          '${outputDirectory.path}${Platform.pathSeparator}qwen_transcription_input.wav';
      final rawJsonPath =
          '${outputDirectory.path}${Platform.pathSeparator}qwen3_asr_result.json';

      if (request.normalizedInputAudioPath == null) {
        _emit(
          TranscriptionStage.preprocessing,
          0.06,
          '正在准备 Qwen3-ASR 16 kHz 单声道输入',
        );
        await _runFfmpeg(
          executable: request.config.ffmpegExecutable,
          inputPath: request.inputAudioPath,
          outputPath: normalizedPath,
        );
      } else {
        _emit(TranscriptionStage.preprocessing, 0.08, '复用双引擎共享的标准化音频');
      }
      _throwIfCancelled();

      _emit(
        TranscriptionStage.loadingModel,
        0.16,
        '正在加载 ${_modelLabel(request.config.qwenModelPath)} 与 ForcedAligner',
      );
      await _ensureServer(request.config);
      _throwIfCancelled();

      _emit(
        TranscriptionStage.transcribing,
        0.34,
        '${_modelLabel(request.config.qwenModelPath)} 正在识别歌曲',
      );
      final input = await _measureNormalizedInput(normalizedPath);
      final response = await _requestTranscription(
        audioPath: normalizedPath,
        config: request.config,
        context: request.context,
        maxNewTokens: input.maxNewTokens,
      );
      _throwIfCancelled();

      await File(rawJsonPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(response),
        flush: true,
      );

      _emit(TranscriptionStage.aligning, 0.82, 'ForcedAligner 正在整理歌词时间轴');
      final result = _parseResponse(
        response,
        normalizedAudioPath: normalizedPath,
        rawJsonPath: rawJsonPath,
        modelPath: request.config.qwenModelPath,
        maxNewTokens: input.maxNewTokens,
        audioDuration: input.audioDuration,
      );

      _emit(TranscriptionStage.completed, 1.0, 'Qwen3-ASR 高质量识别完成');
      return result;
    } on _QwenCancelledException {
      _emit(TranscriptionStage.cancelled, 0.0, 'Qwen3-ASR 识别已取消');
      throw const TranscriptionException.cancelled('歌词识别已取消');
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      _emit(TranscriptionStage.failed, 0.0, 'Qwen3-ASR 识别失败');
      final environmentFailure =
          error is ProcessException ||
          error is SocketException ||
          error is HttpException;
      throw TranscriptionException(
        'Qwen3-ASR 识别失败',
        details: error.toString(),
        kind: environmentFailure
            ? TranscriptionFailureKind.environment
            : TranscriptionFailureKind.unknown,
      );
    } finally {
      _activeRequest = null;
      await _settleRuntimeAfterTask();
      _running = false;
      _cancelRequested = false;
    }
  }

  /// After every task: a cancelled task or a dead runtime releases the
  /// session immediately; a healthy one gets the idle-shutdown timer.
  Future<void> _settleRuntimeAfterTask() async {
    final session = _session;
    if (_cancelRequested || (session != null && !session.isAlive)) {
      await _stopServer();
    } else if (session != null) {
      _scheduleIdleShutdown();
    }
  }

  /// Runs arbitrary-text alignment through the same managed native server
  /// used by transcription. The input is normalized to 16 kHz mono WAV and
  /// temporary audio is removed regardless of success or failure.
  Future<List<ForcedAlignedSpan>> alignReference({
    required String audioPath,
    required String text,
    required String language,
    required Duration audioDuration,
    required TranscriptionConfig config,
  }) async {
    if (_running) {
      throw const TranscriptionException.busy('Qwen3-ASR 已有识别或对齐任务正在运行');
    }
    if (!await File(audioPath).exists()) {
      throw const TranscriptionException.input('待对齐音频文件不存在');
    }
    if (!config.isQwenConfigured) {
      throw const TranscriptionException.environment(
        'ForcedAligner 需要配置 Qwen native runtime 与对齐模型',
      );
    }
    if (text.trim().isEmpty ||
        language.trim().isEmpty ||
        audioDuration <= Duration.zero) {
      throw const TranscriptionException.input('参考歌词、语言和音频时长均为必填项');
    }

    _running = true;
    _cancelRequested = false;
    _idleShutdownTimer?.cancel();
    _idleShutdownTimer = null;
    Directory? temporaryDirectory;
    try {
      await _validateExecutable(
        config.qwenExecutable,
        'Qwen3-ASR native runtime',
      );
      await _validateExecutable(config.ffmpegExecutable, 'FFmpeg');
      if (!await _modelReferenceAvailable(config.qwenModelPath) ||
          !await _modelReferenceAvailable(config.qwenAlignerModelPath)) {
        throw const TranscriptionException.environment(
          'Qwen3-ASR 或 ForcedAligner 模型路径无效',
        );
      }
      final session = await _ensureServer(config);
      temporaryDirectory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'lyricforge-align-${DateTime.now().microsecondsSinceEpoch}',
      );
      await temporaryDirectory.create(recursive: true);
      final normalizedPath =
          '${temporaryDirectory.path}${Platform.pathSeparator}alignment.wav';
      await _runFfmpeg(
        executable: config.ffmpegExecutable,
        inputPath: audioPath,
        outputPath: normalizedPath,
      );
      _throwIfCancelled();
      // FFmpeg can take minutes: prove the runtime is still the process we
      // launched before its port receives the audio path and lyrics.
      await _requireVerifiedSession(session);
      final client = ForcedAlignmentHttpClient(
        endpoint: session.endpoint('/v1/align'),
        authenticator: session,
      );
      _activeAlignmentClient = client;
      try {
        _throwIfCancelled();
        try {
          final spans = await client.align(
            audioPath: normalizedPath,
            text: text,
            language: language,
            audioDuration: audioDuration,
          );
          _throwIfCancelled();
          return spans;
        } on ForcedAlignmentAuthenticationException catch (error) {
          _throwIfCancelled();
          await _stopServer();
          throw TranscriptionException.environment(
            'Qwen3-ASR 本地服务身份验证失败，已停止该 runtime',
            details: error.message,
          );
        } catch (_) {
          _throwIfCancelled();
          rethrow;
        }
      } finally {
        client.close(force: true);
        if (identical(_activeAlignmentClient, client)) {
          _activeAlignmentClient = null;
        }
      }
    } on _QwenCancelledException {
      throw const TranscriptionException.cancelled('歌词对齐已取消');
    } finally {
      if (temporaryDirectory != null && await temporaryDirectory.exists()) {
        try {
          await temporaryDirectory.delete(recursive: true);
        } on FileSystemException {
          // A stale temp file must not mask the alignment result.
        }
      }
      await _settleRuntimeAfterTask();
      _running = false;
      _cancelRequested = false;
    }
  }

  Future<void> _validateRequest(TranscriptionRequest request) async {
    if (!await File(request.inputAudioPath).exists()) {
      throw const TranscriptionException.input('待识别音频文件不存在');
    }
    final normalizedInputPath = request.normalizedInputAudioPath;
    if (normalizedInputPath != null &&
        !await File(normalizedInputPath).exists()) {
      throw const TranscriptionException.input('共享标准化音频文件不存在');
    }

    final config = request.config;
    if (!config.isQwenConfigured) {
      throw const TranscriptionException.environment(
        '最高质量模式需要配置 Qwen3-ASR、1.7B 模型和 ForcedAligner',
      );
    }

    await _validateExecutable(
      config.qwenExecutable,
      'Qwen3-ASR native runtime',
    );
    await _validateExecutable(config.ffmpegExecutable, 'FFmpeg');

    if (!await _modelReferenceAvailable(config.qwenModelPath)) {
      throw const TranscriptionException.environment(
        'Qwen3-ASR 1.7B 模型 ID / 路径无效',
      );
    }
    if (!await _modelReferenceAvailable(config.qwenAlignerModelPath)) {
      throw const TranscriptionException.environment(
        'Qwen3 ForcedAligner 模型 ID / 路径无效',
      );
    }
  }

  Future<bool> _modelReferenceAvailable(String reference) async {
    final value = reference.trim();
    if (value.isEmpty) return false;

    final type = await FileSystemEntity.type(value, followLinks: true);
    if (type != FileSystemEntityType.notFound) return true;

    return RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(value);
  }

  Future<void> _validateExecutable(String executable, String label) async {
    final value = executable.trim();
    if (value.isEmpty) {
      throw TranscriptionException.environment('$label 路径未配置');
    }

    final hasExplicitPath = value.contains('/') || value.contains('\\');
    if (hasExplicitPath) {
      if (!await File(value).exists()) {
        throw TranscriptionException.environment('$label 可执行文件不存在');
      }
      return;
    }

    try {
      final result = await _runToolProcess(
        value,
        const ['--help'],
        operation: '$label 启动自检',
        timeout: AsrProcessTimeoutPolicy.executableProbe,
      );
      if (result.exitCode != 0) {
        throw TranscriptionException.environment(
          '$label 无法执行',
          details: result.stderrTail.join('\n'),
        );
      }
    } on TranscriptionException {
      rethrow;
    } on _QwenCancelledException {
      rethrow;
    } catch (error) {
      throw TranscriptionException.environment(
        '$label 无法执行',
        details: error.toString(),
      );
    }
  }

  Future<void> _runFfmpeg({
    required String executable,
    required String inputPath,
    required String outputPath,
  }) async {
    final output = File(outputPath);
    if (await output.exists()) await output.delete();

    var succeeded = false;
    try {
      final result = await _runToolProcess(
        executable,
        AsrAudioNormalization.ffmpegArguments(
          inputPath: inputPath,
          outputPath: outputPath,
        ),
        operation: 'Qwen FFmpeg 音频预处理',
        timeout: await AsrProcessTimeoutPolicy.ffmpegPreprocessingForFile(
          inputPath,
        ),
      );
      if (result.exitCode != 0) {
        throw TranscriptionException.input(
          'FFmpeg 音频预处理失败',
          details: result.stderrTail.join('\n'),
        );
      }
      if (!await output.exists()) {
        throw const TranscriptionException.input('FFmpeg 未生成 Qwen3-ASR 输入文件');
      }
      succeeded = true;
    } finally {
      if (!succeeded && await output.exists()) {
        try {
          await output.delete();
        } on FileSystemException {
          // Preserve the original failure if cleanup also fails.
        }
      }
    }
  }

  Future<AsrProcessResult> _runToolProcess(
    String executable,
    List<String> arguments, {
    required String operation,
    required Duration timeout,
  }) async {
    _throwIfCancelled();
    try {
      final result = await _processSupervisor.run(
        executable,
        arguments,
        operation: operation,
        timeout: timeout,
        onProcessChanged: (process) {
          _activeToolProcess = process;
          if (process != null && _cancelRequested) {
            unawaited(_processSupervisor.terminate(process));
          }
        },
      );
      _throwIfCancelled();
      return result;
    } on ProcessException catch (error) {
      _throwIfCancelled();
      throw TranscriptionException.environment(
        '无法启动本地处理程序',
        details: error.message,
      );
    } on AsrProcessTimeoutException catch (error) {
      _throwIfCancelled();
      throw TranscriptionException.environment(
        '$operation 超时',
        details: error.toString(),
      );
    } finally {
      _activeToolProcess = null;
    }
  }

  Future<QwenRuntimeSession> _ensureServer(TranscriptionConfig config) async {
    final key = [
      config.qwenExecutable,
      config.qwenModelPath,
      config.qwenAlignerModelPath,
      config.qwenDevice,
      config.qwenDtype,
    ].join('|');

    final current = _session;
    if (current != null && current.isAlive && _serverKey == key) {
      final identity = await current.checkIdentity(_httpClient);
      _throwIfCancelled();
      if (identity == QwenRuntimeIdentity.verified &&
          identical(_session, current)) {
        return current;
      }
      // Unreachable or unproven answers never keep a session alive.
    }

    await _stopServer();
    _throwIfCancelled();

    final generation = _lifecycleGeneration;
    final QwenRuntimeSession session;
    try {
      session = await _runtimeLauncher.start(
        executable: config.qwenExecutable,
        serveArguments: QwenRuntimeSessionProtocol.serveArguments(config),
        startupTimeout: runtimeStartupTimeout,
        isCancelled: () =>
            _cancelRequested || generation != _lifecycleGeneration,
      );
    } on QwenRuntimeLaunchException catch (error) {
      if (error.failure == QwenRuntimeLaunchFailure.cancelled) {
        throw const _QwenCancelledException();
      }
      throw _launchFailure(error);
    }

    if (_cancelRequested || generation != _lifecycleGeneration) {
      await session.close();
      throw const _QwenCancelledException();
    }
    if (_session != null) {
      // Defensive: never run two authenticated runtimes side by side.
      await session.close();
      throw const TranscriptionException.busy('Qwen3-ASR runtime 正在被另一个任务启动');
    }
    _session = session;
    _serverKey = key;
    return session;
  }

  /// Re-proves the runtime identity right before sensitive data is sent.
  Future<void> _requireVerifiedSession(QwenRuntimeSession session) async {
    if (!identical(_session, session) || !session.isAlive) {
      await _stopServer();
      throw const TranscriptionException.environment(
        'Qwen3-ASR 服务已停止，请重新开始任务',
      );
    }
    final identity = await session.checkIdentity(_httpClient);
    _throwIfCancelled();
    if (identity != QwenRuntimeIdentity.verified) {
      await _stopServer();
      throw TranscriptionException.environment(
        'Qwen3-ASR 本地服务身份验证失败，已拒绝发送音频',
        details: 'identity=${identity.name}',
      );
    }
  }

  TranscriptionException _launchFailure(QwenRuntimeLaunchException error) {
    final details = error.details.isEmpty ? null : error.details;
    return switch (error.failure) {
      QwenRuntimeLaunchFailure.startFailed =>
        TranscriptionException.environment(
          '无法启动 Qwen3-ASR native runtime',
          details: details,
        ),
      QwenRuntimeLaunchFailure.exitedDuringStartup =>
        TranscriptionException.environment(
          'Qwen3-ASR native runtime 启动失败',
          details: details,
        ),
      QwenRuntimeLaunchFailure.unsupportedRuntime =>
        TranscriptionException.environment(
          'Qwen3-ASR runtime 版本过旧，不支持本地会话认证；请在识别环境中修复 / 更新识别引擎',
          details: details,
        ),
      QwenRuntimeLaunchFailure.startupTimeout =>
        TranscriptionException.environment(
          'Qwen3-ASR 模型加载超时',
          details: details,
        ),
      QwenRuntimeLaunchFailure.identityRejected =>
        TranscriptionException.environment(
          'Qwen3-ASR 本地服务身份验证失败，已拒绝发送音频',
          details: details,
        ),
      QwenRuntimeLaunchFailure.identityUnreachable =>
        TranscriptionException.environment(
          'Qwen3-ASR 本地服务未响应身份验证',
          details: details,
        ),
      QwenRuntimeLaunchFailure.cancelled =>
        const TranscriptionException.cancelled('歌词识别已取消'),
    };
  }

  /// Measures the normalized input once for the decode budget and the
  /// transcript-coverage record.
  ///
  /// A file that cannot be measured falls back to the previous fixed budget:
  /// the request fails on its own merits, and inflating the budget would only
  /// make that failure slower to surface.
  Future<({int maxNewTokens, Duration audioDuration})> _measureNormalizedInput(
    String audioPath,
  ) async {
    try {
      final bytes = await File(audioPath).length();
      return (
        maxNewTokens: qwenMaxNewTokensForPcmWav(bytes),
        audioDuration: normalizedPcmWavDuration(bytes),
      );
    } on FileSystemException {
      return (
        maxNewTokens: qwenDecodeMinimumTokens,
        audioDuration: Duration.zero,
      );
    }
  }

  Future<Map<String, dynamic>> _requestTranscription({
    required String audioPath,
    required TranscriptionConfig config,
    required String context,
    required int maxNewTokens,
  }) async {
    final session = _session;
    if (session == null || !session.isAlive) {
      throw const TranscriptionException.environment('Qwen3-ASR 服务尚未启动');
    }

    final endpoint = session.endpoint('/v1/transcribe');
    final language = _qwenLanguage(config.language);
    final body = <String, dynamic>{
      'audio': audioPath,
      'return_timestamps': true,
      'max_new_tokens': maxNewTokens,
      'max_batch_size': 4,
      'bucket_by_length': true,
      if (context.trim().isNotEmpty) 'context': context.trim(),
      'language': ?language,
    };
    final payload = utf8.encode(jsonEncode(body));
    // Sign before connecting, so a session that died in the meantime fails
    // without opening a socket to whatever now owns its port.
    final QwenRuntimeRequestAuthorization authorization;
    try {
      authorization = session.authorize('POST', endpoint, payload);
    } on QwenRuntimeSessionClosedException {
      await _stopServer();
      throw const TranscriptionException.environment(
        'Qwen3-ASR 服务已停止，请重新开始任务',
      );
    }

    late final HttpClientRequest request;
    try {
      request = await _httpClient
          .postUrl(endpoint)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException catch (error) {
      _throwIfCancelled();
      throw TranscriptionException.environment(
        'Qwen3-ASR 本地服务连接超时',
        details: error.toString(),
      );
    } catch (error) {
      _throwIfCancelled();
      throw TranscriptionException.environment(
        'Qwen3-ASR 本地服务连接中断',
        details: error.toString(),
      );
    }

    _activeRequest = request;
    final timeout = await AsrProcessTimeoutPolicy.qwenInferenceForPcmWav(
      audioPath,
    );
    try {
      _throwIfCancelled();
      request.headers.contentType = ContentType.json;
      authorization.headers.forEach(request.headers.set);
      request.add(payload);

      HttpClientResponse? receivedResponse;
      final responseBytes = await (() async {
        receivedResponse = await request.close();
        return await readHttpBody(receivedResponse!);
      })().timeout(timeout);
      _throwIfCancelled();

      final response = receivedResponse;
      if (response == null) {
        throw const TranscriptionException.environment('Qwen3-ASR 未返回 HTTP 响应');
      }
      if (!authorization.acceptsResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: responseBytes,
      )) {
        // Never parse or persist a body the runtime did not sign.
        await _stopServer();
        throw TranscriptionException.environment(
          'Qwen3-ASR 本地服务响应未通过会话认证，已停止该 runtime',
          details: 'HTTP ${response.statusCode} without a valid session proof',
        );
      }
      final text = utf8.decode(responseBytes);
      if (response.statusCode != HttpStatus.ok) {
        final environmentFailure = response.statusCode >= 500;
        throw TranscriptionException(
          'Qwen3-ASR 返回 HTTP ${response.statusCode}',
          details: text,
          kind: environmentFailure
              ? TranscriptionFailureKind.environment
              : TranscriptionFailureKind.input,
        );
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const TranscriptionException.environment('Qwen3-ASR 返回了无效 JSON');
      }

      final envelope = Map<String, dynamic>.from(decoded);
      final results = envelope['results'];
      if (results is List && results.isNotEmpty && results.first is Map) {
        return Map<String, dynamic>.from(results.first as Map);
      }

      if (envelope['text'] != null || envelope['timestamps'] != null) {
        return envelope;
      }

      throw const TranscriptionException.environment(
        'Qwen3-ASR 响应缺少 results[0]',
      );
    } on TimeoutException catch (error) {
      request.abort(error, StackTrace.current);
      _throwIfCancelled();
      throw TranscriptionException.environment(
        'Qwen3-ASR 本地识别请求超时',
        details: '识别预算 ${timeout.inMinutes} 分钟已耗尽: ${error.toString()}',
      );
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      _throwIfCancelled();
      throw TranscriptionException.environment(
        'Qwen3-ASR 本地服务请求失败',
        details: error.toString(),
      );
    } finally {
      if (identical(_activeRequest, request)) _activeRequest = null;
    }
  }

  String? _qwenLanguage(String value) {
    return switch (value) {
      'zh' => 'Chinese',
      'en' => 'English',
      'ja' => 'Japanese',
      'ko' => 'Korean',
      _ => null,
    };
  }

  TranscriptionResult _parseResponse(
    Map<String, dynamic> response, {
    required String normalizedAudioPath,
    required String rawJsonPath,
    required String modelPath,
    required int maxNewTokens,
    required Duration audioDuration,
  }) {
    final language = _normalizeLanguage(response['language']?.toString());

    var lines = _parseSegmentLevel(response);
    if (lines.isEmpty) {
      lines = _parseAndGroupWordLevel(response);
    }

    if (lines.isEmpty) {
      throw const TranscriptionException.input(
        'Qwen3 ForcedAligner 没有返回可用时间戳；最高质量模式拒绝生成无时间轴歌词',
      );
    }

    final suspiciousIndexes = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].isLowConfidence(70)) {
        suspiciousIndexes.add(i);
      }
    }

    final document = LyricDocument(
      language: language,
      lines: lines,
      metadata: {
        'generatedBy': _modelKey(modelPath),
        'forcedAligner': 'qwen3-forced-aligner-0.6b',
        'draft': true,
        'qualityMode': 'highestQuality',
        'segmentCount': lines.length,
        'suspiciousLineIndexes': suspiciousIndexes,
        'confidenceSource': 'per-line: model|heuristic|unscored',
        'maxNewTokens': maxNewTokens,
        // How far the recognised lyrics reach into the audio. A transcript that
        // stops well before the end is the only visible symptom of a decode
        // budget that ran out, so the number is recorded rather than inferred.
        'transcriptCoverage': _coverage(
          lines.map((line) => line.endTime).reduce((a, b) => a > b ? a : b),
          audioDuration,
        ),
        'rawJsonPath': rawJsonPath,
      },
    );

    return TranscriptionResult(
      lyrics: document,
      normalizedAudioPath: normalizedAudioPath,
      rawJsonPath: rawJsonPath,
      detectedLanguage: language,
    );
  }

  /// Fraction of the audio covered by the recognised lyrics, in [0, 1].
  ///
  /// Returns null when the audio length is unknown, because "unknown" must not
  /// look like "the transcript stops at the very beginning".
  double? _coverage(Duration lastLineEnd, Duration audioDuration) {
    if (audioDuration <= Duration.zero) return null;
    final ratio = lastLineEnd.inMilliseconds / audioDuration.inMilliseconds;
    return ratio.clamp(0.0, 1.0).toDouble();
  }

  String _modelLabel(String modelPath) {
    return modelPath.toLowerCase().contains('0.6b')
        ? 'Qwen3-ASR 0.6B'
        : 'Qwen3-ASR 1.7B';
  }

  String _modelKey(String modelPath) {
    return modelPath.toLowerCase().contains('0.6b')
        ? 'qwen3-asr-0.6b'
        : 'qwen3-asr-1.7b';
  }

  String _normalizeLanguage(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    return switch (normalized) {
      'chinese' || 'zh' || 'mandarin' => 'zh',
      'english' || 'en' => 'en',
      'japanese' || 'ja' => 'ja',
      'korean' || 'ko' => 'ko',
      '' => 'unknown',
      _ => normalized,
    };
  }

  List<LyricLine> _parseSegmentLevel(Map<String, dynamic> response) {
    final candidates = <dynamic>[
      response['segments'],
      if (response['timestamps'] is Map)
        (response['timestamps'] as Map)['segment'],
      if (response['timestamps'] is Map)
        (response['timestamps'] as Map)['segments'],
    ];

    for (final candidate in candidates) {
      if (candidate is! List || candidate.isEmpty) continue;

      final lines = <LyricLine>[];
      for (final raw in candidate) {
        final parsed = _parseTimestampLine(raw);
        if (parsed != null) lines.add(parsed);
      }

      if (lines.isNotEmpty) return lines;
    }

    return const [];
  }

  List<LyricLine> _parseAndGroupWordLevel(Map<String, dynamic> response) {
    final candidates = <dynamic>[
      response['words'],
      response['time_stamps'],
      if (response['timestamps'] is Map)
        (response['timestamps'] as Map)['word'],
      if (response['timestamps'] is Map)
        (response['timestamps'] as Map)['words'],
      if (response['timestamps'] is Map)
        (response['timestamps'] as Map)['items'],
      if (response['timestamps'] is List) response['timestamps'],
    ];

    for (final candidate in candidates) {
      if (candidate is! List || candidate.isEmpty) continue;

      final tokens = <_TimedToken>[];
      for (final raw in candidate) {
        final token = _parseTimedToken(raw);
        if (token != null) tokens.add(token);
      }

      if (tokens.isNotEmpty) return _groupTokens(tokens);
    }

    return const [];
  }

  LyricLine? _parseTimestampLine(dynamic raw) {
    final token = _parseTimedToken(raw);
    if (token == null) return null;

    // The native response usually has no calibrated lexical confidence; see
    // [scoreAsrLine] for how a missing score stays visibly missing.
    final score = scoreAsrLine(
      text: token.text,
      start: token.start,
      end: token.end,
      explicitConfidence: token.confidence,
    );
    return LyricLine(
      text: token.text,
      startTime: token.start,
      endTime: token.end,
      confidence: score.value,
      confidenceSource: score.source,
    );
  }

  _TimedToken? _parseTimedToken(dynamic raw) {
    if (raw is! Map) return null;

    final item = Map<String, dynamic>.from(raw);
    final text = (item['text'] ?? item['word'])?.toString().trim();
    if (text == null || text.isEmpty) return null;

    final start = _readSeconds(
      item['start'] ?? item['start_time'] ?? item['begin'],
    );
    final end = _readSeconds(item['end'] ?? item['end_time'] ?? item['finish']);
    if (start == null || end == null || end <= start) return null;

    return _TimedToken(
      text: text,
      start: Duration(milliseconds: (start * 1000).round()),
      end: Duration(milliseconds: (end * 1000).round()),
      confidence: _readConfidence(item),
    );
  }

  double? _readSeconds(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _readConfidence(Map<String, dynamic> item) {
    final raw =
        item['confidence'] ?? item['score'] ?? item['probability'] ?? item['p'];
    if (raw is! num) return null;

    final value = raw.toDouble();
    final normalized = value <= 1 ? value * 100 : value;
    return normalized.round().clamp(0, 100).toInt();
  }

  List<LyricLine> _groupTokens(List<_TimedToken> tokens) {
    final lines = <LyricLine>[];
    final buffer = <_TimedToken>[];

    void flush() {
      if (buffer.isEmpty) return;

      final text = _joinTokens(
        buffer.map((token) => token.text).toList(growable: false),
      );
      if (text.isEmpty) {
        buffer.clear();
        return;
      }

      final confidences = buffer
          .where((token) => token.confidence != null)
          .map((token) => token.confidence!)
          .toList(growable: false);
      final explicitConfidence = confidences.isEmpty
          ? null
          : (confidences.reduce((a, b) => a + b) / confidences.length).round();

      final score = scoreAsrLine(
        text: text,
        start: buffer.first.start,
        end: buffer.last.end,
        explicitConfidence: explicitConfidence,
      );
      lines.add(
        LyricLine(
          text: text,
          startTime: buffer.first.start,
          endTime: buffer.last.end,
          confidence: score.value,
          confidenceSource: score.source,
        ),
      );
      buffer.clear();
    }

    for (final token in tokens) {
      if (buffer.isNotEmpty) {
        final previous = buffer.last;
        final gap = token.start - previous.end;
        final lineDuration = previous.end - buffer.first.start;
        final currentText = _joinTokens(
          buffer.map((item) => item.text).toList(growable: false),
        );

        if (gap >= const Duration(milliseconds: 650) ||
            lineDuration >= const Duration(seconds: 7) ||
            currentText.length >= 54 ||
            _endsPhrase(previous.text)) {
          flush();
        }
      }

      buffer.add(token);
    }

    flush();
    return lines;
  }

  String _joinTokens(List<String> tokens) {
    final buffer = StringBuffer();

    for (final raw in tokens) {
      final token = raw.trim();
      if (token.isEmpty) continue;

      if (buffer.isNotEmpty && _needsSpace(buffer.toString(), token)) {
        buffer.write(' ');
      }
      buffer.write(token);
    }

    return buffer.toString().trim();
  }

  bool _needsSpace(String previous, String next) {
    final nextStartsLatin = RegExp(r'^[A-Za-z0-9]').hasMatch(next);
    if (!nextStartsLatin) return false;

    return RegExp(r'[A-Za-z0-9]$').hasMatch(previous) ||
        RegExp(r'[,.;:!?]$').hasMatch(previous);
  }

  bool _endsPhrase(String text) {
    return RegExp(r'[。！？!?；;]$').hasMatch(text.trim());
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
      throw const _QwenCancelledException();
    }
  }

  void _scheduleIdleShutdown() {
    _idleShutdownTimer?.cancel();
    _idleShutdownTimer = Timer(idleShutdownDelay, () {
      if (!_running) unawaited(_stopServer());
    });
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;

    _cancelRequested = true;
    _lifecycleGeneration++;
    _idleShutdownTimer?.cancel();
    _idleShutdownTimer = null;
    _activeAlignmentClient?.close(force: true);
    _activeRequest?.abort();
    final process = _activeToolProcess;
    if (process != null) {
      await _processSupervisor.terminate(process);
      if (identical(_activeToolProcess, process)) _activeToolProcess = null;
    }
    await _stopServer();
  }

  Future<void> _stopServer() async {
    _idleShutdownTimer?.cancel();
    _idleShutdownTimer = null;

    final session = _session;
    _session = null;
    _serverKey = null;
    await session?.close();
  }

  @override
  Future<void> dispose() async {
    _cancelRequested = true;
    _lifecycleGeneration++;
    _activeAlignmentClient?.close(force: true);
    _activeRequest?.abort();
    final process = _activeToolProcess;
    if (process != null) {
      await _processSupervisor.terminate(process);
      if (identical(_activeToolProcess, process)) _activeToolProcess = null;
    }
    await _stopServer();
    _httpClient.close(force: true);
    await _progressController.close();
  }
}

class _TimedToken {
  final String text;
  final Duration start;
  final Duration end;
  final int? confidence;

  const _TimedToken({
    required this.text,
    required this.start,
    required this.end,
    this.confidence,
  });
}

class _QwenCancelledException implements Exception {
  const _QwenCancelledException();
}
