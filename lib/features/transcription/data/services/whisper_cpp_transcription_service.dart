import 'dart:async';
import 'dart:io';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_service.dart';
import 'asr_audio_normalization.dart';
import 'asr_process_supervisor.dart';
import 'whisper_json_transcript_parser.dart';

class WhisperCppTranscriptionService implements TranscriptionService {
  WhisperCppTranscriptionService({AsrProcessSupervisor? processSupervisor})
    : _processSupervisor = processSupervisor ?? AsrProcessSupervisor();

  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();
  final AsrProcessSupervisor _processSupervisor;

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
      throw const TranscriptionException.busy('已有歌词识别任务正在运行');
    }

    _running = true;
    _cancelRequested = false;

    try {
      _emit(TranscriptionStage.validating, 0.02, '正在检查本地识别环境');
      await _validateRequest(request);

      final outputDirectory = Directory(request.outputDirectory);
      await outputDirectory.create(recursive: true);

      final normalizedPath =
          request.normalizedInputAudioPath ??
          '${outputDirectory.path}${Platform.pathSeparator}transcription_input.wav';
      final outputBase =
          '${outputDirectory.path}${Platform.pathSeparator}whisper_result';
      final rawJsonPath = '$outputBase.json';

      if (request.normalizedInputAudioPath == null) {
        _emit(TranscriptionStage.preprocessing, 0.08, '正在准备 16 kHz 单声道人声');
        await _runFfmpeg(
          executable: request.config.ffmpegExecutable,
          inputPath: request.inputAudioPath,
          outputPath: normalizedPath,
        );
      } else {
        _emit(TranscriptionStage.preprocessing, 0.18, '复用双引擎共享的标准化音频');
      }
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
      throw const TranscriptionException.cancelled('歌词识别已取消');
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
      throw const TranscriptionException.input('待识别音频文件不存在');
    }
    final normalizedInputPath = request.normalizedInputAudioPath;
    if (normalizedInputPath != null &&
        !await File(normalizedInputPath).exists()) {
      throw const TranscriptionException.input('共享标准化音频文件不存在');
    }

    final model = File(request.config.modelPath);
    if (!await model.exists()) {
      throw const TranscriptionException.environment('Whisper 模型文件不存在');
    }

    await _validateExecutable(request.config.whisperExecutable, 'whisper-cli');
    await _validateExecutable(request.config.ffmpegExecutable, 'FFmpeg');
  }

  Future<void> _validateExecutable(String executable, String label) async {
    final value = executable.trim();
    if (value.isEmpty) {
      throw TranscriptionException.environment('$label 路径未配置');
    }

    final hasExplicitPath = value.contains('/') || value.contains('\\\\');
    if (hasExplicitPath && !await File(value).exists()) {
      throw TranscriptionException.environment('$label 可执行文件不存在');
    }

    if (!hasExplicitPath) {
      final arguments = label == 'FFmpeg' ? const ['-version'] : const ['-h'];
      final result = await _runProcess(
        value,
        arguments,
        operation: '$label 启动自检',
        timeout: AsrProcessTimeoutPolicy.executableProbe,
      );
      if (result.exitCode != 0) {
        throw TranscriptionException.environment(
          '$label 无法执行',
          details: result.stderrTail,
        );
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

    var succeeded = false;
    try {
      final result = await _runProcess(
        executable,
        AsrAudioNormalization.ffmpegArguments(
          inputPath: inputPath,
          outputPath: outputPath,
        ),
        operation: 'FFmpeg 音频预处理',
        timeout: await AsrProcessTimeoutPolicy.ffmpegPreprocessingForFile(
          inputPath,
        ),
      );

      if (result.exitCode != 0) {
        throw TranscriptionException.input(
          'FFmpeg 音频预处理失败',
          details: result.stderrTail,
        );
      }
      if (!await file.exists()) {
        throw const TranscriptionException.input('FFmpeg 未生成识别输入文件');
      }

      succeeded = true;
      _emit(TranscriptionStage.preprocessing, 0.18, '音频预处理完成');
    } finally {
      if (!succeeded && await file.exists()) {
        try {
          await file.delete();
        } on FileSystemException {
          // Preserve the original process failure if cleanup also fails.
        }
      }
    }
  }

  Future<void> _runWhisper({
    required TranscriptionConfig config,
    required String inputPath,
    required String outputBase,
  }) async {
    final jsonFile = File('$outputBase.json');
    if (await jsonFile.exists()) await jsonFile.delete();

    var succeeded = false;
    try {
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
        operation: 'whisper.cpp 歌词识别',
        timeout: await AsrProcessTimeoutPolicy.whisperInferenceForPcmWav(
          inputPath,
        ),
        onStderrLine: (line) {
          final match = RegExp(
            r'progress\s*=\s*(\d+)%',
            caseSensitive: false,
          ).firstMatch(line);
          final value = int.tryParse(match?.group(1) ?? '');
          if (value != null) {
            final fraction = value.clamp(0, 100) / 100.0;
            _emit(
              TranscriptionStage.transcribing,
              0.20 + fraction * 0.72,
              'Whisper 正在识别 · $value%',
            );
          }
        },
      );

      if (result.exitCode != 0) {
        throw TranscriptionException.environment(
          'whisper.cpp 识别进程失败',
          details: result.stderrTail,
        );
      }
      if (!await jsonFile.exists()) {
        throw const TranscriptionException.environment(
          'whisper.cpp 未生成 JSON 结果',
        );
      }
      succeeded = true;
    } finally {
      if (!succeeded && await jsonFile.exists()) {
        try {
          await jsonFile.delete();
        } on FileSystemException {
          // Do not replace the recognition failure with a cleanup failure.
        }
      }
    }
  }

  Future<TranscriptionResult> _parseResult({
    required String rawJsonPath,
    required String normalizedAudioPath,
  }) async {
    final source = await File(rawJsonPath).readAsString();
    final parsed = const WhisperJsonTranscriptParser().parse(
      source,
      rawJsonPath: rawJsonPath,
    );
    return TranscriptionResult(
      lyrics: parsed.document,
      normalizedAudioPath: normalizedAudioPath,
      rawJsonPath: rawJsonPath,
      detectedLanguage: parsed.detectedLanguage,
    );
  }

  Future<_ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    required String operation,
    required Duration timeout,
    void Function(String line)? onStderrLine,
  }) async {
    _throwIfCancelled();

    try {
      final result = await _processSupervisor.run(
        executable,
        arguments,
        timeout: timeout,
        operation: operation,
        onStderrLine: onStderrLine,
        onProcessChanged: (process) {
          _activeProcess = process;
          if (process != null && _cancelRequested) {
            unawaited(_processSupervisor.terminate(process));
          }
        },
      );

      _throwIfCancelled();
      return _ProcessResult(
        exitCode: result.exitCode,
        stderrTail: result.stderrTail.join('\n'),
      );
    } on ProcessException catch (error) {
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
    }
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
    if (_cancelRequested) throw const _CancelledException();
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    final process = _activeProcess;
    if (process != null) {
      await _processSupervisor.terminate(process);
    }
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

  const _ProcessResult({required this.exitCode, required this.stderrTail});
}

class _CancelledException implements Exception {
  const _CancelledException();
}
