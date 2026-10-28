import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef AsrProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);
typedef ActiveAsrProcessChanged = void Function(Process? process);

class AsrProcessResult {
  final int exitCode;
  final List<String> stdoutTail;
  final List<String> stderrTail;

  const AsrProcessResult({
    required this.exitCode,
    required this.stdoutTail,
    required this.stderrTail,
  });
}

class AsrProcessTimeoutException implements Exception {
  final String operation;
  final String executable;
  final Duration timeout;

  const AsrProcessTimeoutException({
    required this.operation,
    required this.executable,
    required this.timeout,
  });

  @override
  String toString() =>
      '$operation timed out after ${timeout.inSeconds} seconds '
      '(${executable.split(Platform.pathSeparator).last})';
}

/// Runs a child process with bounded execution, termination, and diagnostics.
class AsrProcessSupervisor {
  final AsrProcessStarter _startProcess;
  final Duration terminationGrace;
  final Duration streamDrainGrace;

  AsrProcessSupervisor({
    AsrProcessStarter? startProcess,
    this.terminationGrace = const Duration(seconds: 2),
    this.streamDrainGrace = const Duration(seconds: 2),
  }) : _startProcess = startProcess ?? _startPlatformProcess;

  static Future<Process> _startPlatformProcess(
    String executable,
    List<String> arguments,
  ) => Process.start(executable, arguments, runInShell: false);

  Future<AsrProcessResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    String operation = 'ASR child process',
    int maxOutputLines = 30,
    int maxLineLength = 1024,
    void Function(String line)? onStderrLine,
    ActiveAsrProcessChanged? onProcessChanged,
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }

    final process = await _startProcess(executable, arguments);
    _notifyProcessChanged(onProcessChanged, process);

    final stdoutLines = <String>[];
    final stderrLines = <String>[];
    final stdoutClosed = Completer<void>();
    final stderrClosed = Completer<void>();

    void recordLine(List<String> tail, String line) {
      if (maxOutputLines <= 0 || maxLineLength <= 0) return;
      final boundedLine = line.length <= maxLineLength
          ? line
          : line.substring(line.length - maxLineLength);
      if (tail.length >= maxOutputLines) tail.removeAt(0);
      tail.add(boundedLine);
    }

    void markClosed(Completer<void> completer) {
      if (!completer.isCompleted) completer.complete();
    }

    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => recordLine(stdoutLines, line),
          onError: (Object error, [StackTrace? stackTrace]) {
            markClosed(stdoutClosed);
          },
          onDone: () => markClosed(stdoutClosed),
          cancelOnError: false,
        );
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            recordLine(stderrLines, line);
            try {
              onStderrLine?.call(line);
            } catch (_) {
              // A progress callback must not interrupt pipe draining.
            }
          },
          onError: (Object error, [StackTrace? stackTrace]) {
            markClosed(stderrClosed);
          },
          onDone: () => markClosed(stderrClosed),
          cancelOnError: false,
        );

    final exitCodeFuture = process.exitCode;
    try {
      late final int exitCode;
      try {
        exitCode = await exitCodeFuture.timeout(timeout);
      } on TimeoutException {
        await _terminate(process, exitCodeFuture);
        throw AsrProcessTimeoutException(
          operation: operation,
          executable: executable,
          timeout: timeout,
        );
      }

      // A descendant can inherit a pipe after the direct child exits. It must
      // not make a completed process look like an ASR operation that is hung.
      try {
        await Future.wait<void>([
          stdoutClosed.future,
          stderrClosed.future,
        ]).timeout(streamDrainGrace);
      } on TimeoutException {
        // Cancel subscriptions in finally instead of waiting indefinitely.
      }

      return AsrProcessResult(
        exitCode: exitCode,
        stdoutTail: List<String>.unmodifiable(stdoutLines),
        stderrTail: List<String>.unmodifiable(stderrLines),
      );
    } finally {
      try {
        await stdoutSubscription.cancel();
      } catch (_) {}
      try {
        await stderrSubscription.cancel();
      } catch (_) {}
      _notifyProcessChanged(onProcessChanged, null);
    }
  }

  Future<void> _terminate(Process process, Future<int> exitCode) async {
    try {
      process.kill();
    } catch (_) {}

    try {
      await exitCode.timeout(terminationGrace);
      return;
    } catch (_) {
      // Escalate only when normal termination did not stop the child.
    }

    try {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {
      // SIGKILL may not be available on every supported platform.
    }

    try {
      await exitCode.timeout(terminationGrace);
    } catch (_) {
      // Keep cleanup bounded even if the OS does not report termination.
    }
  }

  void _notifyProcessChanged(
    ActiveAsrProcessChanged? callback,
    Process? process,
  ) {
    try {
      callback?.call(process);
    } catch (_) {
      // Lifecycle observers must not interrupt process cleanup.
    }
  }
}

abstract final class AsrProcessTimeoutPolicy {
  static const Duration executableProbe = Duration(seconds: 10);
  static const Duration _ffmpegBase = Duration(minutes: 5);
  static const Duration _ffmpegMaximum = Duration(minutes: 60);
  static const Duration _inferenceMinimum = Duration(minutes: 5);
  static const Duration _inferenceMaximum = Duration(minutes: 120);

  static const int _bytesPerMebibyte = 1024 * 1024;
  static const int _pcmWavHeaderBytes = 44;
  static const int _normalizedPcmBytesPerSecond = 16000 * 1 * 2;

  /// Gives larger source files more FFmpeg time, with a hard upper bound.
  static Duration ffmpegPreprocessingForBytes(int sourceBytes) {
    final mebibytes = sourceBytes <= 0
        ? 0
        : (sourceBytes + _bytesPerMebibyte - 1) ~/ _bytesPerMebibyte;
    final seconds = (_ffmpegBase.inSeconds + mebibytes * 20)
        .clamp(_ffmpegBase.inSeconds, _ffmpegMaximum.inSeconds)
        .toInt();
    return Duration(seconds: seconds);
  }

  static Future<Duration> ffmpegPreprocessingForFile(String inputPath) async {
    try {
      return ffmpegPreprocessingForBytes(await File(inputPath).length());
    } catch (_) {
      return const Duration(minutes: 10);
    }
  }

  /// ASR input is normalized to 16 kHz, mono, signed 16-bit PCM WAV.
  static Duration whisperInferenceForPcmWavBytes(int wavBytes) {
    final payloadBytes = wavBytes > _pcmWavHeaderBytes
        ? wavBytes - _pcmWavHeaderBytes
        : 0;
    final audioSeconds =
        (payloadBytes + _normalizedPcmBytesPerSecond - 1) ~/
        _normalizedPcmBytesPerSecond;
    final seconds = (180 + audioSeconds * 10)
        .clamp(_inferenceMinimum.inSeconds, _inferenceMaximum.inSeconds)
        .toInt();
    return Duration(seconds: seconds);
  }

  static Future<Duration> whisperInferenceForPcmWav(String path) async {
    try {
      return whisperInferenceForPcmWavBytes(await File(path).length());
    } catch (_) {
      return const Duration(minutes: 30);
    }
  }
}
