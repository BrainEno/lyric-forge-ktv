import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';

void main() {
  group('AsrProcessSupervisor', () {
    test('drains both pipes and retains bounded output tails', () async {
      final process = _FakeProcess();
      final supervisor = AsrProcessSupervisor(
        startProcess: (_, __) async => process,
        streamDrainGrace: const Duration(milliseconds: 30),
      );
      final progressLines = <String>[];
      final future = supervisor.run(
        'fake-asr',
        const [],
        timeout: const Duration(seconds: 1),
        maxOutputLines: 2,
        maxLineLength: 12,
        onStderrLine: progressLines.add,
      );
      await Future<void>.delayed(Duration.zero);
      process.emitStdout('out-1\nout-2\nout-3\n');
      process.emitStderr('err-1\nerr-2\nprogress = 45%\n');
      process.finish(0);

      final result = await future;

      expect(result.exitCode, 0);
      expect(result.stdoutTail, ['out-2', 'out-3']);
      expect(result.stderrTail, ['err-2', 'progress = 45%']);
      expect(progressLines, ['err-1', 'err-2', 'progress = 45%']);
    });

    test('kills a timed out process and clears its active reference', () async {
      final process = _FakeProcess(killOnSigterm: true);
      final supervisor = AsrProcessSupervisor(
        startProcess: (_, __) async => process,
        terminationGrace: const Duration(milliseconds: 20),
        streamDrainGrace: const Duration(milliseconds: 20),
      );
      final active = <Process?>[];
      final future = supervisor.run(
        'hung-asr',
        const [],
        operation: 'Whisper inference',
        timeout: const Duration(milliseconds: 15),
        onProcessChanged: active.add,
      );

      await expectLater(future, throwsA(isA<AsrProcessTimeoutException>()));

      expect(process.killSignals, contains(ProcessSignal.sigterm));
      expect(active, [process, null]);
    });

    test('escalates when normal termination does not stop the child', () async {
      final process = _FakeProcess(killOnSigterm: false, killOnSigkill: true);
      final supervisor = AsrProcessSupervisor(
        startProcess: (_, __) async => process,
        terminationGrace: const Duration(milliseconds: 10),
        streamDrainGrace: const Duration(milliseconds: 10),
      );

      await expectLater(
        supervisor.run(
          'hung-asr',
          const [],
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<AsrProcessTimeoutException>()),
      );

      expect(process.killSignals, contains(ProcessSignal.sigterm));
      expect(process.killSignals, contains(ProcessSignal.sigkill));
    });

    test('does not wait forever for pipes inherited after child exit', () async {
      final process = _FakeProcess();
      final supervisor = AsrProcessSupervisor(
        startProcess: (_, __) async => process,
        streamDrainGrace: const Duration(milliseconds: 10),
      );
      final future = supervisor.run(
        'child-with-inherited-pipes',
        const [],
        timeout: const Duration(seconds: 1),
      );
      await Future<void>.delayed(Duration.zero);
      process.finish(0, closeStreams: false);

      final result = await future;

      expect(result.exitCode, 0);
      await process.closeStreams();
    });
  });

  group('AsrProcessTimeoutPolicy', () {
    test('FFmpeg budget grows with larger source files and remains bounded', () {
      final small = AsrProcessTimeoutPolicy.ffmpegPreprocessingForBytes(1024);
      final larger = AsrProcessTimeoutPolicy.ffmpegPreprocessingForBytes(
        80 * 1024 * 1024,
      );
      final huge = AsrProcessTimeoutPolicy.ffmpegPreprocessingForBytes(
        2 * 1024 * 1024 * 1024,
      );

      expect(larger, greaterThan(small));
      expect(huge, const Duration(minutes: 60));
    });

    test('Whisper budget scales with normalized WAV duration', () {
      const bytesPerSecond = 16000 * 2;
      const headerBytes = 44;
      final short = AsrProcessTimeoutPolicy.whisperInferenceForPcmWavBytes(
        headerBytes + bytesPerSecond * 10,
      );
      final long = AsrProcessTimeoutPolicy.whisperInferenceForPcmWavBytes(
        headerBytes + bytesPerSecond * 60 * 10,
      );
      final huge = AsrProcessTimeoutPolicy.whisperInferenceForPcmWavBytes(
        headerBytes + bytesPerSecond * 60 * 180,
      );

      expect(short, const Duration(minutes: 5));
      expect(long, greaterThan(short));
      expect(huge, const Duration(minutes: 120));
      expect(
        AsrProcessTimeoutPolicy.executableProbe,
        const Duration(seconds: 10),
      );
    });
  });
}

class _FakeProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final IOSink _stdin = IOSink(_DiscardingConsumer());
  final List<ProcessSignal> killSignals = <ProcessSignal>[];
  final bool killOnSigterm;
  final bool killOnSigkill;

  _FakeProcess({
    this.killOnSigterm = true,
    this.killOnSigkill = true,
  });

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 12345;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if ((signal == ProcessSignal.sigterm && killOnSigterm) ||
        (signal == ProcessSignal.sigkill && killOnSigkill)) {
      finish(137);
    }
    return true;
  }

  void emitStdout(String text) => _stdout.add(utf8.encode(text));

  void emitStderr(String text) => _stderr.add(utf8.encode(text));

  void finish(int code, {bool closeStreams = true}) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    if (closeStreams) unawaited(closeStreamsAsync());
  }

  Future<void> closeStreams() => closeStreamsAsync();

  Future<void> closeStreamsAsync() async {
    if (!_stdout.isClosed) await _stdout.close();
    if (!_stderr.isClosed) await _stderr.close();
  }
}

class _DiscardingConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<void> close() async {}
}
