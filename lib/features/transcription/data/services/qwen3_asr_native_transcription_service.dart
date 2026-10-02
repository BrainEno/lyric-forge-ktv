import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_service.dart';

class Qwen3AsrNativeTranscriptionService implements TranscriptionService {
  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();
  final HttpClient _httpClient = HttpClient();

  Process? _serverProcess;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  HttpClientRequest? _activeRequest;
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
      throw const TranscriptionException('Qwen3-ASR 已有识别任务正在运行');
    }

    _running = true;
    _cancelRequested = false;
    _idleShutdownTimer?.cancel();
    _idleShutdownTimer = null;

    try {
      _emit(
        TranscriptionStage.validating,
        0.02,
        '正在检查 Qwen3-ASR 高质量运行环境',
      );
      await _validateRequest(request);
      _throwIfCancelled();

      final outputDirectory = Directory(request.outputDirectory);
      await outputDirectory.create(recursive: true);

      final normalizedPath = outputDirectory.path +
          Platform.pathSeparator +
          'qwen_transcription_input.wav';
      final rawJsonPath = outputDirectory.path +
          Platform.pathSeparator +
          'qwen3_asr_result.json';

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
      _throwIfCancelled();

      _emit(
        TranscriptionStage.loadingModel,
        0.16,
        '正在加载 Qwen3-ASR 1.7B 与 ForcedAligner',
      );
      await _ensureServer(request.config);
      _throwIfCancelled();

      _emit(
        TranscriptionStage.transcribing,
        0.34,
        'Qwen3-ASR 1.7B 正在识别歌曲',
      );
      final response = await _requestTranscription(
        audioPath: normalizedPath,
        config: request.config,
        context: request.context,
      );
      _throwIfCancelled();

      await File(rawJsonPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(response),
        flush: true,
      );

      _emit(
        TranscriptionStage.aligning,
        0.82,
        'ForcedAligner 正在整理歌词时间轴',
      );
      final result = _parseResponse(
        response,
        normalizedAudioPath: normalizedPath,
        rawJsonPath: rawJsonPath,
      );

      _emit(
        TranscriptionStage.completed,
        1.0,
        'Qwen3-ASR 高质量识别完成',
      );
      return result;
    } on _QwenCancelledException {
      _emit(TranscriptionStage.cancelled, 0.0, 'Qwen3-ASR 识别已取消');
      throw const TranscriptionException('歌词识别已取消');
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      _emit(TranscriptionStage.failed, 0.0, 'Qwen3-ASR 识别失败');
      throw TranscriptionException(
        'Qwen3-ASR 识别失败',
        details: error.toString(),
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

  Future<void> _validateRequest(TranscriptionRequest request) async {
    if (!await File(request.inputAudioPath).exists()) {
      throw const TranscriptionException('待识别音频文件不存在');
    }

    final config = request.config;
    if (!config.isQwenConfigured) {
      throw const TranscriptionException(
        '最高质量模式需要配置 Qwen3-ASR、1.7B 模型和 ForcedAligner',
      );
    }

    await _validateExecutable(
      config.qwenExecutable,
      'Qwen3-ASR native runtime',
    );
    await _validateExecutable(config.ffmpegExecutable, 'FFmpeg');

    if (!await _modelReferenceAvailable(config.qwenModelPath)) {
      throw const TranscriptionException(
        'Qwen3-ASR 1.7B 模型 ID / 路径无效',
      );
    }
    if (!await _modelReferenceAvailable(config.qwenAlignerModelPath)) {
      throw const TranscriptionException(
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
      throw TranscriptionException(label + ' 路径未配置');
    }

    final hasExplicitPath = value.contains('/') || value.contains('\\');
    if (hasExplicitPath) {
      if (!await File(value).exists()) {
        throw TranscriptionException(label + ' 可执行文件不存在');
      }
      return;
    }

    try {
      final result = await Process.run(value, const ['--help']);
      if (result.exitCode != 0) {
        throw TranscriptionException(label + ' 无法执行');
      }
    } on ProcessException catch (error) {
      throw TranscriptionException(
        label + ' 无法执行',
        details: error.message,
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

    Process process;
    try {
      process = await Process.start(
        executable,
        [
          '-y',
          '-i',
          inputPath,
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
    } on ProcessException catch (error) {
      throw TranscriptionException(
        '无法启动 FFmpeg',
        details: error.message,
      );
    }

    _activeToolProcess = process;
    if (_cancelRequested) process.kill();

    final stdoutFuture = process.stdout.drain<void>();
    final stderrFuture = utf8.decoder.bind(process.stderr).join();
    final exitCode = await process.exitCode;
    await stdoutFuture;
    final stderrText = await stderrFuture;

    if (identical(_activeToolProcess, process)) {
      _activeToolProcess = null;
    }

    _throwIfCancelled();

    if (exitCode != 0) {
      throw TranscriptionException(
        'FFmpeg 音频预处理失败',
        details: stderrText,
      );
    }
    if (!await output.exists()) {
      throw const TranscriptionException(
        'FFmpeg 未生成 Qwen3-ASR 输入文件',
      );
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
      process = await Process.start(
        config.qwenExecutable,
        [
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
        ],
      );
    } on ProcessException catch (error) {
      throw TranscriptionException(
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

    const attempts = 240;
    for (var attempt = 0; attempt < attempts; attempt++) {
      _throwIfCancelled();

      if (_serverExited) {
        final details = _serverLogTail.join('\n');
        await _stopServer();
        throw TranscriptionException(
          'Qwen3-ASR native runtime 启动失败',
          details: details,
        );
      }

      if (await _isServerHealthy()) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    final details = _serverLogTail.join('\n');
    await _stopServer();
    throw TranscriptionException(
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
    final socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
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
      final response =
          await request.close().timeout(const Duration(seconds: 2));
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _requestTranscription({
    required String audioPath,
    required TranscriptionConfig config,
    required String context,
  }) async {
    final port = _serverPort;
    if (port == null) {
      throw const TranscriptionException('Qwen3-ASR 服务尚未启动');
    }

    final request = await _httpClient.postUrl(
      Uri.parse('http://127.0.0.1:$port/v1/transcribe'),
    );
    _activeRequest = request;
    request.headers.contentType = ContentType.json;

    final language = _qwenLanguage(config.language);
    final body = <String, dynamic>{
      'audio': audioPath,
      'return_timestamps': true,
      'max_new_tokens': 1024,
      'max_batch_size': 4,
      'bucket_by_length': true,
      if (context.trim().isNotEmpty) 'context': context.trim(),
      if (language != null) 'language': language,
    };
    request.add(utf8.encode(jsonEncode(body)));

    HttpClientResponse response;
    try {
      response = await request.close();
    } catch (error) {
      _throwIfCancelled();
      rethrow;
    } finally {
      _activeRequest = null;
    }

    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw TranscriptionException(
        'Qwen3-ASR 返回 HTTP ${response.statusCode}',
        details: text,
      );
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const TranscriptionException('Qwen3-ASR 返回了无效 JSON');
    }

    final envelope = Map<String, dynamic>.from(decoded);
    final results = envelope['results'];
    if (results is List && results.isNotEmpty && results.first is Map) {
      return Map<String, dynamic>.from(results.first as Map);
    }

    if (envelope['text'] != null || envelope['timestamps'] != null) {
      return envelope;
    }

    throw const TranscriptionException(
      'Qwen3-ASR 响应缺少 results[0]',
    );
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
  }) {
    final language = _normalizeLanguage(response['language']?.toString());

    var lines = _parseSegmentLevel(response);
    if (lines.isEmpty) {
      lines = _parseAndGroupWordLevel(response);
    }

    if (lines.isEmpty) {
      throw const TranscriptionException(
        'Qwen3 ForcedAligner 没有返回可用时间戳；最高质量模式拒绝生成无时间轴歌词',
      );
    }

    final suspiciousIndexes = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].confidence < 70) {
        suspiciousIndexes.add(i);
      }
    }

    final document = LyricDocument(
      language: language,
      lines: lines,
      metadata: {
        'generatedBy': 'qwen3-asr-1.7b',
        'forcedAligner': 'qwen3-forced-aligner-0.6b',
        'draft': true,
        'qualityMode': 'highestQuality',
        'segmentCount': lines.length,
        'suspiciousLineIndexes': suspiciousIndexes,
        'confidenceSource': 'aligner_timing_heuristics',
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

  List<LyricLine> _parseAndGroupWordLevel(
    Map<String, dynamic> response,
  ) {
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

    return LyricLine(
      text: token.text,
      startTime: token.start,
      endTime: token.end,
      confidence: _lineConfidence(
        token.text,
        token.start,
        token.end,
        explicitConfidence: token.confidence,
      ),
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
    final end = _readSeconds(
      item['end'] ?? item['end_time'] ?? item['finish'],
    );
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
    final raw = item['confidence'] ??
        item['score'] ??
        item['probability'] ??
        item['p'];
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
          : (confidences.reduce((a, b) => a + b) / confidences.length)
              .round();

      lines.add(
        LyricLine(
          text: text,
          startTime: buffer.first.start,
          endTime: buffer.last.end,
          confidence: _lineConfidence(
            text,
            buffer.first.start,
            buffer.last.end,
            explicitConfidence: explicitConfidence,
          ),
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

  int _lineConfidence(
    String text,
    Duration start,
    Duration end, {
    int? explicitConfidence,
  }) {
    var score = explicitConfidence ?? 92;
    final duration = end - start;

    if (duration > const Duration(seconds: 9)) score -= 18;
    if (text.length > 72) score -= 18;
    if (duration < const Duration(milliseconds: 350) && text.length > 8) {
      score -= 18;
    }
    if (_hasSuspiciousRepetition(text)) score -= 35;
    if (text.trim().length <= 1) score -= 12;

    return score.clamp(25, 99).toInt();
  }

  bool _hasSuspiciousRepetition(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(
          RegExp(r'[^a-z0-9\u3400-\u9fff\u3040-\u30ff]+'),
          ' ',
        )
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
    _activeRequest?.abort();
    _activeToolProcess?.kill();
    _activeToolProcess = null;
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
      process.kill();
    }

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
  }

  @override
  Future<void> dispose() async {
    _cancelRequested = true;
    _activeRequest?.abort();
    _activeToolProcess?.kill();
    _activeToolProcess = null;
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
