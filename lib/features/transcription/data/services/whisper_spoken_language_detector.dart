import 'dart:io';

import '../../domain/models/spoken_language.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/models/vocal_activity.dart';
import '../../domain/services/spoken_language_detector.dart';
import '../../domain/services/vocal_activity_analyzer.dart';
import 'asr_audio_normalization.dart';
import 'asr_process_supervisor.dart';
import 'pcm_wav_clip_writer.dart';
import 'pcm_wav_energy_reader.dart';

/// Runs one child process for the language probe.
typedef SpokenLanguageProcessRunner =
    Future<AsrProcessResult> Function(
      String executable,
      List<String> arguments, {
      required Duration timeout,
      required String operation,
      void Function(String line)? onStderrLine,
      ActiveAsrProcessChanged? onProcessChanged,
    });

/// Asks whisper.cpp which language the sung parts of a song are in (D-061).
///
/// 1. FFmpeg decodes the input to the 16 kHz mono WAV every engine reads
///    (skipped when the request already carries one).
/// 2. The loudness envelope tells where the singing is
///    ([SpokenLanguagePolicy.probeWindows]).
/// 3. Those stretches, joined into one clip of at most 30 seconds, go to
///    `whisper-cli --detect-language`, which stops after the language
///    identification: one encoder pass, no decoding.
/// 4. A second clip of the next most sung stretches is tried when the first
///    answer is not reliable.
///
/// The probe files are deleted afterwards.
class WhisperSpokenLanguageDetector implements SpokenLanguageDetector {
  WhisperSpokenLanguageDetector({
    SpokenLanguagePolicy policy = const SpokenLanguagePolicy(),
    VocalActivityAnalyzer analyzer = const VocalActivityAnalyzer(),
    AsrProcessSupervisor? processSupervisor,
    SpokenLanguageProcessRunner? runProcess,
    Future<VocalEnergyEnvelope> Function(String path)? readEnvelope,
  }) : _policy = policy,
       _analyzer = analyzer,
       _supervisor = processSupervisor ?? AsrProcessSupervisor(),
       _runProcessOverride = runProcess,
       _readEnvelope = readEnvelope ?? PcmWavEnergyReader.readInIsolate;

  static const String detectLanguageFlag = '--detect-language';
  static const String _cancelledMessage = '歌词识别已取消';

  /// Loading large-v3 and one encoder pass; generous for a slow CPU.
  static const Duration whisperTimeout = Duration(minutes: 5);

  final SpokenLanguagePolicy _policy;
  final VocalActivityAnalyzer _analyzer;
  final AsrProcessSupervisor _supervisor;
  final SpokenLanguageProcessRunner? _runProcessOverride;
  final Future<VocalEnergyEnvelope> Function(String path) _readEnvelope;

  bool _cancelled = false;
  Process? _active;

  /// `whisper_full_with_state: auto-detected language: en (p = 0.981234)`.
  static final RegExp _detectedLine = RegExp(
    r'auto-detected language:\s*([A-Za-z-]+)\s*\(p\s*=\s*([0-9]*\.?[0-9]+)',
  );

  /// The language and probability in one whisper.cpp stderr line, or null.
  static SpokenLanguageProbe? parseDetectedLanguage(String line) {
    final match = _detectedLine.firstMatch(line);
    if (match == null) return null;
    final probability = double.tryParse(match.group(2)!);
    if (probability == null) return null;
    return SpokenLanguageProbe(
      match.group(1)!.toLowerCase(),
      probability.clamp(0.0, 1.0).toDouble(),
    );
  }

  @override
  Future<SpokenLanguageResolution> detect(TranscriptionRequest request) async {
    _cancelled = false;
    final songInfo = SpokenLanguagePolicy.languageFromSongInfo(
      request.recognitionHints,
    );
    final probes = <SpokenLanguageProbe>[];
    final listened = <SpokenLanguageWindow>[];
    final work = Directory(
      '${request.outputDirectory}${Platform.pathSeparator}spoken_language',
    );
    try {
      final config = request.config;
      if (!await File(config.modelPath).exists()) {
        return _policy.decide(
          probes: probes,
          songInfoLanguage: songInfo,
          error: 'Whisper 模型不存在：${config.modelPath}',
        );
      }
      await work.create(recursive: true);
      final normalized = await _normalized(request, config, work);
      _checkCancelled();
      final envelope = await _readEnvelope(normalized);
      _checkCancelled();
      final windows = _policy.probeWindows(
        envelope,
        _analyzer.analyze(envelope),
      );
      for (var index = 0; index < windows.length; index++) {
        final clip = '${work.path}${Platform.pathSeparator}probe_$index.wav';
        await writePcmWavClip(
          sourcePath: normalized,
          targetPath: clip,
          windows: windows[index],
        );
        _checkCancelled();
        listened.addAll(windows[index]);
        final probe = await _identify(config, clip);
        _checkCancelled();
        if (probe == null) continue;
        probes.add(probe);
        if (_policy.isReliable(probe)) break;
      }
      return _policy.decide(
        probes: probes,
        songInfoLanguage: songInfo,
        windows: listened,
      );
    } on TranscriptionException catch (error) {
      if (error.kind == TranscriptionFailureKind.cancelled) rethrow;
      return _policy.decide(
        probes: probes,
        songInfoLanguage: songInfo,
        windows: listened,
        error: error.toString(),
      );
    } on Object catch (error) {
      _checkCancelled();
      return _policy.decide(
        probes: probes,
        songInfoLanguage: songInfo,
        windows: listened,
        error: error.toString(),
      );
    } finally {
      try {
        if (await work.exists()) await work.delete(recursive: true);
      } on FileSystemException {
        // Only disk space; the next run replaces the folder.
      }
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final process = _active;
    if (process != null) await _supervisor.terminate(process);
  }

  Future<String> _normalized(
    TranscriptionRequest request,
    TranscriptionConfig config,
    Directory work,
  ) async {
    final given = request.normalizedInputAudioPath;
    if (given != null && await File(given).exists()) return given;
    final output = '${work.path}${Platform.pathSeparator}input.wav';
    final result = await _run(
      config.ffmpegExecutable,
      AsrAudioNormalization.ffmpegArguments(
        inputPath: request.inputAudioPath,
        outputPath: output,
      ),
      timeout: await AsrProcessTimeoutPolicy.ffmpegPreprocessingForFile(
        request.inputAudioPath,
      ),
      operation: 'FFmpeg 语言检测音频',
    );
    _checkCancelled();
    if (result.exitCode != 0 || !await File(output).exists()) {
      throw TranscriptionException.input(
        'FFmpeg 没能为语言检测解码音频',
        details: result.stderrTail.join('\n'),
      );
    }
    return output;
  }

  /// Whisper's answer for [clip], or null when it gave none.
  Future<SpokenLanguageProbe?> _identify(
    TranscriptionConfig config,
    String clip,
  ) async {
    Future<SpokenLanguageProbe?> attempt({required bool detectOnly}) async {
      SpokenLanguageProbe? found;
      var unknownArgument = false;
      await _run(
        config.whisperExecutable,
        [
          '-m',
          config.modelPath,
          '-f',
          clip,
          '-l',
          SpokenLanguagePolicy.auto,
          if (detectOnly) detectLanguageFlag,
        ],
        timeout: whisperTimeout,
        operation: 'whisper.cpp 语言检测',
        onStderrLine: (line) {
          found ??= parseDetectedLanguage(line);
          if (line.toLowerCase().contains('error: unknown argument')) {
            unknownArgument = true;
          }
        },
      );
      if (found == null && unknownArgument && detectOnly) {
        // An old whisper-cli without the flag decodes the clip instead,
        // which logs the same detection line first.
        return attempt(detectOnly: false);
      }
      return found;
    }

    return attempt(detectOnly: true);
  }

  Future<AsrProcessResult> _run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    required String operation,
    void Function(String line)? onStderrLine,
  }) async {
    void track(Process? process) {
      _active = process;
      if (process != null && _cancelled) _supervisor.terminate(process);
    }

    try {
      final runner = _runProcessOverride;
      if (runner != null) {
        return await runner(
          executable,
          arguments,
          timeout: timeout,
          operation: operation,
          onStderrLine: onStderrLine,
          onProcessChanged: track,
        );
      }
      return await _supervisor.run(
        executable,
        arguments,
        timeout: timeout,
        operation: operation,
        onStderrLine: onStderrLine,
        onProcessChanged: track,
      );
    } on ProcessException catch (error) {
      _checkCancelled();
      throw TranscriptionException.environment(
        '$operation 无法启动',
        details: error.message,
      );
    } on AsrProcessTimeoutException {
      _checkCancelled();
      throw TranscriptionException.environment('$operation 超时');
    } finally {
      _active = null;
    }
  }

  void _checkCancelled() {
    if (_cancelled) {
      throw const TranscriptionException.cancelled(_cancelledMessage);
    }
  }
}
