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

  int? _serverPort;
  String? _serverKey;
  final List<String> _serverLogTail = [];

  bool _running = false;
  bool _cancelRequested = false;
  bool _serverExited = false;

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

    try {
      _emit(TranscriptionStage.validating, 0.02, '正在检查 Qwen3-ASR 高质量运行环境');
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
        normalizedPath,
        request.config,
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

    await _validateExecutable(config.qwenExecutable, 'Qwen3-ASR native runtime');
    await _validateExecutable(config.ffmpegExecutable, 'FFmpeg');

    if (!await _pathExists(config.qwenModelPath)) {
      throw const TranscriptionException('Qwen3-ASR 1.7B 模型路径不存在');
    }
    if (!await _pathExists(config.qwenAlignerModelPath)) {
      throw const TranscriptionException('Qwen3 ForcedAligner 模型路径不存在');
    }
  }

  Future<bool> _pathExists(String path) async {
    if (path.trim().isEmpty) return false;
    final type = await FileSystemEntity.type(path, followLinks: true);
    return type != FileSystemEntityType.notFound;
  }

  Future<void> _validateExecutable(String executable, String label) async {
    final value = executable.trim();
    if (value.isEmpty) {
      throw TranscriptionException(label + ' 路径未配置');
    }

    final hasExplicitPath = value.contains('/') || value.contains('\\');
    if (hasExplicitPath && !await File(value).exists()) {
      throw TranscriptionException(label + ' 可执行文件不存在');
    }

    if (!hasExplicitPath) {
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
  }

  Future<void> _runFfmpeg({
    required String executable,
    required String inputPath,
    required String outputPath,
  }) async {
    final output = File(outputPath);
    if (await output.exists()) await output.delete();

    final result = await Process.run(
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

    _throwIfCancelled();

    if (result.exitCode != 0) {
      throw TranscriptionException(
        'FFmpeg 音频预处理失败',
        details: result.stderr.toString(),
      );
    }
    if (!await output.exists()) {
      throw const TranscriptionException('FFmpeg 未生成 Qwen3-ASR 输入文件');
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
    final process = await Process.start(
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
        throw TranscriptionException(
          'Qwen3-ASR native runtime 启动失败',
          details: _serverLogTail.join('\n'),
        );
      }

      if (await _isServerHealthy()) {
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    throw TranscriptionException(
      'Qwen3-ASR 模型加载超时',
      details: _serverLogTail.join('\n'),
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
      final request = await _httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$port/healthz'),
      );
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _requestTranscription(
    String audioPath,
    TranscriptionConfig config,
  ) async {
    final port = _serverPort;
    if (port == null) {
      throw const TranscriptionException('Qwen3-ASR 服务尚未启动');
    }

    final request = await _httpClient.postUrl(
      Uri.parse('http://127.0.0.1:$port/v1/transcribe'),
    );
    _activeRequest = request;
    request.headers.contentType = ContentType.json;

    final body = <String, dynamic>{
      'audio': audioPath,
      'return_timestamps': true,
      if (_qwenLanguage(config.language) != null)
        'language': _qwenLanguage(config.language),
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

    return Map<String, dynamic>.from(decoded);
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
    final language =
        (response['language'] as String?)?.trim().isNotEmpty == true
            ? response['language'] as String
            : 'unknown';

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
      if (lines[i].confidence < 70) suspiciousIndexes.add(i);
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
        final parsed = _parseTimestampItem(raw);
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
      if (response['timestamps'] is List) response['timestamps'],
    ];

    for (final candidate in candidates) {
      if (candidate is! List || candidate.isEmpty) continue;

      final words = <_TimedToken>[];
      for (final raw in candidate) {
        final token = _parseTimedToken(raw);
        if (token != null) words.add(token);
      }

      if (words.isNotEmpty) {
        return _groupWords(words);
      }
    }

    return const [];
  }

  LyricLine? _parseTimestampItem(dynamic raw) {
    final token = _parseTimedToken(raw);
    if (token == null) return null;

    final confidence = _lineConfidence(
      token.text,
      token.start,
      token.end,
      explicitConfidence: token.confidence,
    );

    return LyricLine(
      text: token.text.trim(),
      startTime: token.start,
      endTime: token.end,
      confidence: confidence,
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

  List<LyricLine> _groupWords(List<_TimedToken> words) {
    final lines = <LyricLine>[];
    final buffer = <_TimedToken>[];

    void flush() {
      if (buffer.isEmpty) return;
      final text = _joinTokens(buffer.map((e) => e.text).toList());
      final confidences = buffer
          .where((e) => e.confidence != null)
          .map((e) => e.confidence!)
          .toList();

      final explicitConfidence = confidences.isEmpty
          ? null
          : (confidences.reduce((a, b) => a + b) / confidences.length)
              .round();

      final confidence = _lineConfidence(
        text,
        buffer.first.start,
        buffer.last.end,
        explicitConfidence: explicitConfidence,
      );

      lines.add(
        LyricLine(
          text: text,
          startTime: buffer.first.start,
          endTime: buffer.last.end,
          confidence: confidence,
        ),
      );
      buffer.clear();
    }

    for (final word in words) {
      if (buffer.isNotEmpty) {
        final previous = buffer.last;
        final gap = word.start - previous.end;
        final lineDuration = previous.end - buffer.first.start;
        final currentText =
            _joinTokens(buffer.map((e) => e.text).toList());

        if (gap >= const Duration(milliseconds: 650) ||
            lineDuration >= const Duration(seconds: 7) ||
            currentText.length >= 54 ||
            _endsPhrase(previous.text)) {
          flush();
        }
      }

      buffer.add(word);
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
    return RegExp(r'[A-Za-z0-9]

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
    if (_cancelRequested) throw const _QwenCancelledException();
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    _activeRequest?.abort();
    await _stopServer();
  }

  Future<void> _stopServer() async {
    final process = _serverProcess;
    _serverProcess = null;
    _serverPort = null;
    _serverKey = null;
    _serverExited = false;

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    if (process != null) {
      process.kill();
    }
  }

  @override
  Future<void> dispose() async {
    _cancelRequested = true;
    _activeRequest?.abort();
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
).hasMatch(previous) &&
        RegExp(r'^[A-Za-z0-9]').hasMatch(next);
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
        .replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff\u3040-\u30ff]+'), ' ')
        .trim();
    if (normalized.length < 8) return false;

    final tokens = normalized.contains(' ')
        ? normalized.split(RegExp(r'\s+'))
        : normalized.characters.toList();
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
    if (_cancelRequested) throw const _QwenCancelledException();
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    _activeRequest?.abort();
    await _stopServer();
  }

  Future<void> _stopServer() async {
    final process = _serverProcess;
    _serverProcess = null;
    _serverPort = null;
    _serverKey = null;
    _serverExited = false;

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    if (process != null) {
      process.kill();
    }
  }

  @override
  Future<void> dispose() async {
    _cancelRequested = true;
    _activeRequest?.abort();
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
