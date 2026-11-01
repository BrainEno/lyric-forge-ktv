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

class Qwen3AsrNativeTranscriptionService implements TranscriptionService {
  Qwen3AsrNativeTranscriptionService({AsrProcessSupervisor? processSupervisor})
    : _processSupervisor = processSupervisor ?? AsrProcessSupervisor();

  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();
  final AsrProcessSupervisor _processSupervisor;
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  Process? _serverProcess;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  HttpClientRequest? _activeRequest;
  ForcedAlignmentHttpClient? _activeAlignmentClient;
  Process? _activeToolProcess;
  Timer? _idleShutdownTimer;

  int? _serverPort;
  String? _serverKey;
  bool _serverExited = false;
  bool _running = false;
  bool _cancelRequested = false;

  final List<String> _serverLogTail = [];

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
      _running = false;

      if (!_cancelRequested && _serverProcess != null) {
        _scheduleIdleShutdown();
      }
      _cancelRequested = false;
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
      await _ensureServer(config);
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
      final port = _serverPort;
      if (port == null) {
        throw const TranscriptionException.environment('Qwen3-ASR 服务尚未启动');
      }
      final client = ForcedAlignmentHttpClient(
        endpoint: Uri.parse('http://127.0.0.1:$port/v1/align'),
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
      _running = false;
      _cancelRequested = false;
      if (_serverProcess != null) _scheduleIdleShutdown();
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

  Future<void> _ensureServer(TranscriptionConfig config) async {
    final key = [
      config.qwenExecutable,
      config.qwenModelPath,
      config.qwenAlignerModelPath,
      config.qwenDevice,
      config.qwenDtype,
    ].join('|');

    if (_serverProcess != null &&
        _serverKey == key &&
        await _isServerHealthy()) {
      return;
    }

    await _stopServer();

    final port = await _reservePort();

    Process process;
    try {
      process = await Process.start(config.qwenExecutable, [
        '--device',
        config.qwenDevice,
        '--dtype',
        config.qwenDtype,
        'serve',
        '--model',
        config.qwenModelPath,
        '--host',
        '127.0.0.1',
        '--port',
        port.toString(),
        '--forced-aligner',
        config.qwenAlignerModelPath,
      ]);
    } on ProcessException catch (error) {
      throw TranscriptionException.environment(
        '无法启动 Qwen3-ASR native runtime',
        details: error.message,
      );
    }

    _serverProcess = process;
    _serverPort = port;
    _serverKey = key;
    _serverExited = false;
    _serverLogTail.clear();

    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_captureServerLog);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_captureServerLog);

    unawaited(
      process.exitCode.then((_) {
        if (identical(_serverProcess, process)) {
          _serverExited = true;
        }
      }),
    );

    const startupTimeout = Duration(minutes: 2);
    const pollInterval = Duration(milliseconds: 500);
    final startupStopwatch = Stopwatch()..start();
    while (startupStopwatch.elapsed < startupTimeout) {
      if (_cancelRequested) {
        await _stopServer();
        _throwIfCancelled();
      }

      if (_serverExited) {
        final details = _serverLogTail.join('\n');
        await _stopServer();
        throw TranscriptionException.environment(
          'Qwen3-ASR native runtime 启动失败',
          details: details,
        );
      }

      if (await _isServerHealthy()) return;
      final remaining = startupTimeout - startupStopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(
          remaining < pollInterval ? remaining : pollInterval,
        );
      }
    }

    final details = _serverLogTail.join('\n');
    await _stopServer();
    throw TranscriptionException.environment(
      'Qwen3-ASR 模型加载超时',
      details: details,
    );
  }

  void _captureServerLog(String line) {
    if (_serverLogTail.length >= 40) {
      _serverLogTail.removeAt(0);
    }
    _serverLogTail.add(line);
  }

  Future<int> _reservePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<bool> _isServerHealthy() async {
    final port = _serverPort;
    if (port == null) return false;

    try {
      final request = await _httpClient
          .getUrl(Uri.parse('http://127.0.0.1:$port/healthz'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      await response.drain<void>().timeout(const Duration(seconds: 2));
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
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
    final port = _serverPort;
    if (port == null) {
      throw const TranscriptionException.environment('Qwen3-ASR 服务尚未启动');
    }

    final endpoint = Uri.parse('http://127.0.0.1:$port/v1/transcribe');
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
      request.add(utf8.encode(jsonEncode(body)));

      HttpClientResponse? receivedResponse;
      final text = await (() async {
        receivedResponse = await request.close();
        return await utf8.decoder.bind(receivedResponse!).join();
      })().timeout(timeout);
      _throwIfCancelled();

      final response = receivedResponse;
      if (response == null) {
        throw const TranscriptionException.environment('Qwen3-ASR 未返回 HTTP 响应');
      }
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
    _idleShutdownTimer = Timer(
      const Duration(minutes: 10),
      () => unawaited(_stopServer()),
    );
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;

    _cancelRequested = true;
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

    final process = _serverProcess;
    _serverProcess = null;
    _serverPort = null;
    _serverKey = null;
    _serverExited = false;

    if (process != null) {
      await _processSupervisor.terminate(process);
    }

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
  }

  @override
  Future<void> dispose() async {
    _cancelRequested = true;
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
