import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_service.dart';

class WhisperCppTranscriptionService implements TranscriptionService {
  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();

  Process? _activeProcess;
  bool _cancelRequested = false;
  bool _running = false;

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
      _emit(TranscriptionStage.validating, 0.02, '正在检查本地识别环境');
      await _validateRequest(request);

      final outputDirectory = Directory(request.outputDirectory);
      await outputDirectory.create(recursive: true);

      final normalizedPath = outputDirectory.path +
          Platform.pathSeparator +
          'transcription_input.wav';
      final outputBase = outputDirectory.path +
          Platform.pathSeparator +
          'whisper_result';
      final rawJsonPath = outputBase + '.json';

      _emit(TranscriptionStage.preprocessing, 0.08, '正在准备 16 kHz 单声道人声');
      await _runFfmpeg(
        executable: request.config.ffmpegExecutable,
        inputPath: request.inputAudioPath,
        outputPath: normalizedPath,
      );
      _throwIfCancelled();

      _emit(TranscriptionStage.transcribing, 0.20, 'Whisper 正在识别歌词');
      await _runWhisper(
        config: request.config,
        inputPath: normalizedPath,
        outputBase: outputBase,
      );
      _throwIfCancelled();

      _emit(TranscriptionStage.parsing, 0.94, '正在整理时间轴和置信度');
      final result = await _parseResult(
        rawJsonPath: rawJsonPath,
        normalizedAudioPath: normalizedPath,
      );

      _emit(TranscriptionStage.completed, 1.0, '歌词草稿已生成');
      return result;
    } on _CancelledException {
      _emit(TranscriptionStage.cancelled, 0.0, '歌词识别已取消');
      throw const TranscriptionException('歌词识别已取消');
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      _emit(TranscriptionStage.failed, 0.0, '歌词识别失败');
      throw TranscriptionException('歌词识别失败', details: error.toString());
    } finally {
      _activeProcess = null;
      _running = false;
      _cancelRequested = false;
    }
  }

  Future<void> _validateRequest(TranscriptionRequest request) async {
    final input = File(request.inputAudioPath);
    if (!await input.exists()) {
      throw const TranscriptionException('待识别音频文件不存在');
    }

    final model = File(request.config.modelPath);
    if (!await model.exists()) {
      throw const TranscriptionException('Whisper 模型文件不存在');
    }

    await _validateExecutable(
      request.config.whisperExecutable,
      'whisper-cli',
    );
    await _validateExecutable(
      request.config.ffmpegExecutable,
      'FFmpeg',
    );
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
        final arguments =
            label == 'FFmpeg' ? const ['-version'] : const ['-h'];
        final result = await Process.run(value, arguments);
        if (result.exitCode != 0) {
          throw TranscriptionException(label + ' 无法执行');
        }
      } on ProcessException catch (error) {
        throw TranscriptionException(label + ' 无法执行', details: error.message);
      }
    }
  }

  Future<void> _runFfmpeg({
    required String executable,
    required String inputPath,
    required String outputPath,
  }) async {
    final file = File(outputPath);
    if (await file.exists()) await file.delete();

    final result = await _runProcess(
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

    if (result.exitCode != 0) {
      throw TranscriptionException(
        'FFmpeg 音频预处理失败',
        details: result.stderrTail,
      );
    }
    if (!await file.exists()) {
      throw const TranscriptionException('FFmpeg 未生成识别输入文件');
    }

    _emit(TranscriptionStage.preprocessing, 0.18, '音频预处理完成');
  }

  Future<void> _runWhisper({
    required TranscriptionConfig config,
    required String inputPath,
    required String outputBase,
  }) async {
    final jsonFile = File(outputBase + '.json');
    if (await jsonFile.exists()) await jsonFile.delete();

    final result = await _runProcess(
      config.whisperExecutable,
      [
        '-m',
        config.modelPath,
        '-f',
        inputPath,
        '-l',
        config.language,
        '-ojf',
        '-of',
        outputBase,
        '-pp',
      ],
      onStderrLine: (line) {
        final match =
            RegExp(r'progress\s*=\s*(\d+)%', caseSensitive: false)
                .firstMatch(line);
        final value = int.tryParse(match?.group(1) ?? '');
        if (value != null) {
          final fraction = value.clamp(0, 100) / 100.0;
          _emit(
            TranscriptionStage.transcribing,
            0.20 + fraction * 0.72,
            'Whisper 正在识别 · ' + value.toString() + '%',
          );
        }
      },
    );

    if (result.exitCode != 0) {
      throw TranscriptionException(
        'whisper.cpp 识别失败',
        details: result.stderrTail,
      );
    }
    if (!await jsonFile.exists()) {
      throw const TranscriptionException('whisper.cpp 未生成 JSON 结果');
    }
  }

  Future<TranscriptionResult> _parseResult({
    required String rawJsonPath,
    required String normalizedAudioPath,
  }) async {
    final decoded = jsonDecode(await File(rawJsonPath).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const TranscriptionException('Whisper JSON 格式无效');
    }

    final result = decoded['result'];
    final detectedLanguage = result is Map
        ? (result['language'] as String? ?? 'unknown')
        : 'unknown';

    final rawSegments = decoded['transcription'];
    if (rawSegments is! List) {
      throw const TranscriptionException('Whisper JSON 缺少 transcription');
    }

    final lines = <LyricLine>[];
    var lowConfidenceCount = 0;
    var skippedSegmentCount = 0;

    for (final raw in rawSegments) {
      if (raw is! Map) {
        skippedSegmentCount++;
        continue;
      }
      final segment = Map<String, dynamic>.from(raw);
      final text = (segment['text'] as String? ?? '').trim();
      if (text.isEmpty) {
        skippedSegmentCount++;
        continue;
      }

      final offsets = segment['offsets'];
      if (offsets is! Map) {
        skippedSegmentCount++;
        continue;
      }
      final from = offsets['from'];
      final to = offsets['to'];
      if (from is! num || to is! num || to.toInt() <= from.toInt()) {
        skippedSegmentCount++;
        continue;
      }

      final confidence = _segmentConfidence(segment);
      if (confidence < 65) lowConfidenceCount++;

      lines.add(
        LyricLine(
          text: text,
          startTime: Duration(milliseconds: from.toInt()),
          endTime: Duration(milliseconds: to.toInt()),
          confidence: confidence,
        ),
      );
    }

    if (lines.isEmpty) {
      throw const TranscriptionException('Whisper 没有识别到可用歌词片段');
    }

    final document = LyricDocument(
      language: detectedLanguage,
      lines: lines,
      metadata: {
        'generatedBy': 'whisper.cpp',
        'draft': true,
        'segmentCount': lines.length,
        'lowConfidenceThreshold': 65,
        'lowConfidenceLineCount': lowConfidenceCount,
        'skippedSegmentCount': skippedSegmentCount,
        'rawJsonPath': rawJsonPath,
      },
    );

    return TranscriptionResult(
      lyrics: document,
      normalizedAudioPath: normalizedAudioPath,
      rawJsonPath: rawJsonPath,
      detectedLanguage: detectedLanguage,
    );
  }

  int _segmentConfidence(Map<String, dynamic> segment) {
    final tokens = segment['tokens'];
    if (tokens is! List) return 50;

    final probabilities = <double>[];
    for (final rawToken in tokens) {
      if (rawToken is! Map) continue;
      final token = Map<String, dynamic>.from(rawToken);
      final text = (token['text'] as String? ?? '').trim();
      if (text.startsWith('[_') && text.endsWith('_]')) continue;
      final probability = token['p'];
      if (probability is num) {
        probabilities.add(probability.toDouble().clamp(0.0, 1.0));
      }
    }

    if (probabilities.isEmpty) return 50;
    final average =
        probabilities.reduce((a, b) => a + b) / probabilities.length;
    return (average * 100).round().clamp(0, 100).toInt();
  }

  Future<_ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    void Function(String line)? onStderrLine,
  }) async {
    _throwIfCancelled();

    Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
      );
    } on ProcessException catch (error) {
      throw TranscriptionException(
        '无法启动本地处理程序',
        details: error.message,
      );
    }

    _activeProcess = process;
    if (_cancelRequested) {
      process.kill();
    }
    final stderrLines = <String>[];

    final stdoutFuture = process.stdout.drain<void>();
    final stderrFuture = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
      if (stderrLines.length >= 30) stderrLines.removeAt(0);
      stderrLines.add(line);
      onStderrLine?.call(line);
    });

    final exitCode = await process.exitCode;
    await Future.wait([stdoutFuture, stderrFuture]);

    if (identical(_activeProcess, process)) {
      _activeProcess = null;
    }
    _throwIfCancelled();

    return _ProcessResult(
      exitCode: exitCode,
      stderrTail: stderrLines.join('\n'),
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
    if (_cancelRequested) throw const _CancelledException();
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    _activeProcess?.kill();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _progressController.close();
  }
}

class _ProcessResult {
  final int exitCode;
  final String stderrTail;

  const _ProcessResult({
    required this.exitCode,
    required this.stderrTail,
  });
}

class _CancelledException implements Exception {
  const _CancelledException();
}
