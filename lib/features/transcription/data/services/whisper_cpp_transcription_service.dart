import 'dart:async';
import 'dart:io';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/models/whisper_decoding_policy.dart';
import '../../domain/services/transcription_service.dart';
import 'asr_audio_normalization.dart';
import 'asr_process_supervisor.dart';
import 'whisper_json_transcript_parser.dart';

/// Metadata key holding the decoding profile a Whisper run actually used.
const String kWhisperDecodingMetadataKey = 'whisperDecoding';

class WhisperCppTranscriptionService implements TranscriptionService {
  WhisperCppTranscriptionService({
    AsrProcessSupervisor? processSupervisor,
    bool? isWindows,
    WhisperDecodingPolicy decodingPolicy = const WhisperDecodingPolicy(),
  }) : _processSupervisor = processSupervisor ?? AsrProcessSupervisor(),
       _isWindows = isWindows ?? Platform.isWindows,
       _decodingPolicy = decodingPolicy;

  final bool _isWindows;
  final WhisperDecodingPolicy _decodingPolicy;

  /// Help-text probes are cached per binary identity (path, size, mtime), so a
  /// replaced runtime is probed again while a batch probes each binary once.
  static final Map<String, WhisperRuntimeCapabilities> _capabilityCache = {};

  /// Test hook: forget every cached help-text probe.
  static void clearCapabilityCache() => _capabilityCache.clear();

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

      final plan = await _planDecoding(request);
      _throwIfCancelled();

      _emit(TranscriptionStage.transcribing, 0.20, 'Whisper 正在识别歌词');
      final outcome = await _runWhisperWithFallback(
        config: request.config,
        inputPath: normalizedPath,
        outputBase: outputBase,
        plan: plan,
      );
      _throwIfCancelled();

      _emit(TranscriptionStage.parsing, 0.94, '正在整理时间轴和置信度');
      final result = await _parseResult(
        rawJsonPath: rawJsonPath,
        normalizedAudioPath: normalizedPath,
        outcome: outcome,
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

  /// Decides which decoding flags this run uses. Probing never fails the run:
  /// an unreadable help text means "unknown", which yields the standard
  /// command line every runtime has always accepted.
  Future<WhisperDecodingPlan> _planDecoding(
    TranscriptionRequest request,
  ) async {
    final profile = request.config.whisperDecodingProfile;
    if (profile == WhisperDecodingProfile.standard) {
      return WhisperDecodingPlan.standard();
    }
    final capabilities = await _probeCapabilities(
      request.config.whisperExecutable,
    );
    return _decodingPolicy.plan(
      profile: profile,
      hints: request.recognitionHints,
      language: request.config.language,
      capabilities: capabilities,
      chineseScript: request.config.chineseScriptOutputTarget,
    );
  }

  Future<WhisperRuntimeCapabilities> _probeCapabilities(
    String executable,
  ) async {
    final value = executable.trim();
    var key = value;
    try {
      final file = File(value);
      if (await file.exists()) {
        final stat = await file.stat();
        key = '$value|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
      }
    } on FileSystemException {
      // Fall back to the bare path as the cache key.
    }
    final cached = _capabilityCache[key];
    if (cached != null) return cached;

    WhisperRuntimeCapabilities capabilities;
    try {
      final result = await _processSupervisor.run(
        value,
        const ['-h'],
        timeout: AsrProcessTimeoutPolicy.executableProbe,
        operation: 'whisper-cli 能力探测',
        // The usage text is ~90 lines on stderr; keep all of it.
        maxOutputLines: 400,
      );
      capabilities = WhisperRuntimeCapabilities.fromHelpText(
        [...result.stdoutTail, ...result.stderrTail].join('\n'),
      );
    } on ProcessException {
      capabilities = WhisperRuntimeCapabilities.unknown;
    } on AsrProcessTimeoutException {
      capabilities = WhisperRuntimeCapabilities.unknown;
    }
    _throwIfCancelled();
    _capabilityCache[key] = capabilities;
    return capabilities;
  }

  /// Runs the planned profile and, if the runtime rejects its flags, retries
  /// once with the standard command line. The retry is recorded, never silent.
  Future<_WhisperRunOutcome> _runWhisperWithFallback({
    required TranscriptionConfig config,
    required String inputPath,
    required String outputBase,
    required WhisperDecodingPlan plan,
  }) async {
    var effectivePlan = plan;
    String? transportNote;
    final transport = _chooseTransport(
      config: config,
      inputPath: inputPath,
      outputBase: outputBase,
      plan: plan,
    );
    if (transport.plan != null) {
      effectivePlan = transport.plan!;
      transportNote = transport.note;
    }

    if (effectivePlan.isStandard) {
      await _runWhisper(
        config: config,
        inputPath: inputPath,
        outputBase: outputBase,
        plan: effectivePlan,
        useResponseFile: false,
      );
      return _WhisperRunOutcome(
        plan: effectivePlan,
        fallbackReason: transportNote,
      );
    }

    try {
      await _runWhisper(
        config: config,
        inputPath: inputPath,
        outputBase: outputBase,
        plan: effectivePlan,
        useResponseFile: transport.useResponseFile,
      );
      return _WhisperRunOutcome(
        plan: effectivePlan,
        fallbackReason: transportNote,
        promptTransport: transport.useResponseFile ? 'response-file' : 'argv',
      );
    } on _UnsupportedWhisperArgumentsException catch (error) {
      _throwIfCancelled();
      _emit(
        TranscriptionStage.transcribing,
        0.20,
        'Whisper 运行时不支持歌词参数，改用标准参数重试',
      );
      final standard = WhisperDecodingPlan.standard(
        requested: plan.requestedProfile,
        omittedFlags: [
          ...plan.omittedFlags,
          for (final argument in effectivePlan.extraArguments)
            if (argument.startsWith('-')) argument,
        ],
      );
      await _runWhisper(
        config: config,
        inputPath: inputPath,
        outputBase: outputBase,
        plan: standard,
        useResponseFile: false,
      );
      return _WhisperRunOutcome(
        plan: standard,
        fallbackReason: 'runtime_rejected_arguments: ${error.detail}',
      );
    }
  }

  /// whisper-cli on Windows receives argv in the system ANSI code page (see
  /// `SetConsoleOutputCP` in cli.cpp), so a CJK prompt passed on the command
  /// line arrives as '?' or mojibake. Its `@file` response-file form reads
  /// each line as raw bytes instead, which keeps UTF-8 intact — but then file
  /// paths are raw bytes too, so it is only used when every path is ASCII.
  /// Otherwise the prompt is dropped and the reason recorded.
  _WhisperTransport _chooseTransport({
    required TranscriptionConfig config,
    required String inputPath,
    required String outputBase,
    required WhisperDecodingPlan plan,
  }) {
    final prompt = plan.prompt;
    if (!_isWindows || prompt == null || _isAscii(prompt)) {
      return const _WhisperTransport(useResponseFile: false);
    }
    final paths = [config.modelPath, inputPath, outputBase];
    final pathsAreSafe = paths.every(
      (path) => _isAscii(path) && !path.contains('\n') && !path.contains('\r'),
    );
    if (pathsAreSafe) {
      return const _WhisperTransport(useResponseFile: true);
    }
    final withoutPrompt = <String>[];
    for (var index = 0; index < plan.extraArguments.length; index++) {
      final argument = plan.extraArguments[index];
      if (argument == WhisperRuntimeCapabilities.promptFlag) {
        index++;
        continue;
      }
      withoutPrompt.add(argument);
    }
    return _WhisperTransport(
      useResponseFile: false,
      note: 'windows_non_ascii_paths_prompt_omitted',
      plan: withoutPrompt.isEmpty
          ? WhisperDecodingPlan.standard(
              requested: plan.requestedProfile,
              omittedFlags: [
                ...plan.omittedFlags,
                WhisperRuntimeCapabilities.promptFlag,
              ],
            )
          : WhisperDecodingPlan(
              requestedProfile: plan.requestedProfile,
              effectiveProfile: plan.effectiveProfile,
              extraArguments: List.unmodifiable(withoutPrompt),
              prompt: null,
              promptSources: const <String>[],
              omittedFlags: List.unmodifiable([
                ...plan.omittedFlags,
                WhisperRuntimeCapabilities.promptFlag,
              ]),
            ),
    );
  }

  static bool _isAscii(String value) =>
      value.runes.every((rune) => rune < 0x80);

  Future<void> _runWhisper({
    required TranscriptionConfig config,
    required String inputPath,
    required String outputBase,
    required WhisperDecodingPlan plan,
    required bool useResponseFile,
  }) async {
    final jsonFile = File('$outputBase.json');
    if (await jsonFile.exists()) await jsonFile.delete();

    final arguments = <String>[
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
      ...plan.extraArguments,
    ];
    File? responseFile;
    if (useResponseFile) {
      responseFile = File('$outputBase.args.rsp');
      // One argument per line, UTF-8 without BOM, '\n' endings: cli.cpp reads
      // it with std::getline and uses each line verbatim.
      await responseFile.writeAsString('${arguments.join('\n')}\n');
    }

    var succeeded = false;
    var sawUnknownArgument = false;
    String? unknownArgumentLine;
    try {
      final result = await _runProcess(
        config.whisperExecutable,
        responseFile == null ? arguments : ['@${responseFile.path}'],
        operation: 'whisper.cpp 歌词识别',
        timeout: await AsrProcessTimeoutPolicy.whisperInferenceForPcmWav(
          inputPath,
        ),
        onStderrLine: (line) {
          if (WhisperRuntimeCapabilities.isUnknownArgumentLine(line)) {
            sawUnknownArgument = true;
            unknownArgumentLine ??= line.trim();
          }
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

      // An unknown flag prints usage and exits 0 without writing JSON, so the
      // stderr line, not the exit code, is the signal.
      if (sawUnknownArgument && !plan.isStandard) {
        throw _UnsupportedWhisperArgumentsException(
          unknownArgumentLine ?? 'unknown argument',
        );
      }
      // A runtime without response-file support treats '@…' as an input file
      // and fails or produces nothing; retry with the plain standard line.
      if (responseFile != null &&
          (result.exitCode != 0 || !await jsonFile.exists())) {
        throw const _UnsupportedWhisperArgumentsException(
          'response file not honoured',
        );
      }
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
      if (responseFile != null) {
        try {
          if (await responseFile.exists()) await responseFile.delete();
        } on FileSystemException {
          // A leftover argument file is harmless; keep the real outcome.
        }
      }
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
    required _WhisperRunOutcome outcome,
  }) async {
    final source = await File(rawJsonPath).readAsString();
    final parsed = const WhisperJsonTranscriptParser().parse(
      source,
      rawJsonPath: rawJsonPath,
    );
    final echo = removePromptEchoes(parsed.document.lines, outcome.plan.prompt);
    if (echo.lines.isEmpty) {
      // Every row was the prompt repeated back: nothing was recognised.
      throw const TranscriptionException.input('Whisper 没有识别到可用歌词片段');
    }
    return TranscriptionResult(
      lyrics: parsed.document.copyWith(
        lines: echo.lines,
        metadata: {
          ...parsed.document.metadata,
          if (echo.removedCount > 0) 'segmentCount': echo.lines.length,
          kWhisperDecodingMetadataKey: {
            ...outcome.plan.toMetadata(fallbackReason: outcome.fallbackReason),
            'promptTransport': ?outcome.promptTransport,
            if (echo.removedCount > 0)
              'promptEchoRemovedCount': echo.removedCount,
          },
        },
      ),
      normalizedAudioPath: normalizedAudioPath,
      rawJsonPath: rawJsonPath,
      detectedLanguage: parsed.detectedLanguage,
    );
  }

  /// Whisper occasionally reproduces its prompt verbatim over a silent intro.
  /// Only a row that repeats the *entire* prompt is removed: the prompt is
  /// built from metadata templates, so a whole-prompt row is never a lyric,
  /// while a row that merely contains the title (a chorus often does) stays.
  static ({List<LyricLine> lines, int removedCount}) removePromptEchoes(
    List<LyricLine> lines,
    String? prompt,
  ) {
    if (prompt == null) return (lines: lines, removedCount: 0);
    final normalizedPrompt = _normalizeForEcho(prompt);
    // Require some substance so a one-word prompt cannot remove a lyric.
    if (normalizedPrompt.runes.length < 6) {
      return (lines: lines, removedCount: 0);
    }
    final kept = <LyricLine>[];
    var removed = 0;
    for (final line in lines) {
      if (_normalizeForEcho(line.text) == normalizedPrompt) {
        removed++;
      } else {
        kept.add(line);
      }
    }
    return (lines: removed == 0 ? lines : kept, removedCount: removed);
  }

  static String _normalizeForEcho(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

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

class _WhisperRunOutcome {
  final WhisperDecodingPlan plan;
  final String? fallbackReason;
  final String? promptTransport;

  const _WhisperRunOutcome({
    required this.plan,
    this.fallbackReason,
    this.promptTransport,
  });
}

class _WhisperTransport {
  final bool useResponseFile;
  final String? note;
  final WhisperDecodingPlan? plan;

  const _WhisperTransport({
    required this.useResponseFile,
    this.note,
    this.plan,
  });
}

class _UnsupportedWhisperArgumentsException implements Exception {
  final String detail;

  const _UnsupportedWhisperArgumentsException(this.detail);
}

class _ProcessResult {
  final int exitCode;
  final String stderrTail;

  const _ProcessResult({required this.exitCode, required this.stderrTail});
}

class _CancelledException implements Exception {
  const _CancelledException();
}
