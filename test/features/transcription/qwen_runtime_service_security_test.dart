import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen3_asr_native_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen_runtime_session_auth.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

void main() {
  group('Qwen native runtime session security', () {
    late Directory tempDirectory;
    late File input;
    late File normalized;
    late File executable;
    late File alignerModel;
    late File firstModel;
    late File secondModel;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'lyric_forge_qwen_security_',
      );
      input = await _touch(tempDirectory, 'song.mp3', [1, 2, 3]);
      normalized = await _touch(
        tempDirectory,
        'song.wav',
        List<int>.filled(44 + 32000, 0),
      );
      executable = await _touch(tempDirectory, 'qwen-runtime', [1]);
      alignerModel = await _touch(tempDirectory, 'aligner.bin', [1]);
      firstModel = await _touch(tempDirectory, 'qwen-first.bin', [1]);
      secondModel = await _touch(tempDirectory, 'qwen-second.bin', [1]);
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('rejects a forged healthy endpoint before sending audio or lyrics', () async {
      final runtime = _FakeQwenRuntimeProcess(authenticateResponse: false);
      late List<String> arguments;
      final service = Qwen3AsrNativeTranscriptionService(
        startRuntimeProcess: (_, args) async {
          arguments = List<String>.of(args);
          await runtime.start();
          return runtime;
        },
      );
      addTearDown(service.dispose);

      await expectLater(
        service.transcribe(_request(model: firstModel)),
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.message,
            'message',
            contains('身份验证失败'),
          ),
        ),
      );

      expect(arguments, containsAllInOrder(['--port', '0']));
      expect(arguments, contains('--session-auth-stdin'));
      expect(arguments, isNot(contains(input.path)));
      expect(runtime.requestPaths, ['/healthz']);
      expect(runtime.receivedBodies, everyElement(isEmpty));
      await runtime.stopped.future.timeout(const Duration(seconds: 2));
    });

    test('accepts only signed runtime health and transcription responses', () async {
      final runtime = _FakeQwenRuntimeProcess();
      final service = Qwen3AsrNativeTranscriptionService(
        startRuntimeProcess: (_, arguments) async {
          runtime.recordArguments(arguments);
          await runtime.start();
          return runtime;
        },
      );
      addTearDown(service.dispose);

      final result = await service.transcribe(_request(model: firstModel));

      expect(result.lyrics.lines.single.text, 'recognized lyric');
      expect(runtime.requestPaths, [
        '/healthz',
        '/healthz',
        '/v1/transcribe',
      ]);
      final transcriptBody = jsonDecode(runtime.receivedBodies.last) as Map;
      expect(transcriptBody['audio'], normalized.path);
      expect(runtime.receivedHeaders, hasLength(3));
      expect(
        runtime.receivedHeaders.every((value) => value.contains(':')),
        isTrue,
      );
      expect(
        runtime.receivedHeaders.join('\n'),
        isNot(contains(runtime.bootstrapPayload)),
      );
      expect(
        runtime.receivedBodies.join('\n'),
        isNot(contains(runtime.bootstrapPayload)),
      );
      expect(runtime.argumentsForPortZero, isTrue);
    });

    test(
      'configuration change kills the old session and rejects its credential',
      () async {
        final runtimes = <_FakeQwenRuntimeProcess>[];
        final service = Qwen3AsrNativeTranscriptionService(
          startRuntimeProcess: (_, arguments) async {
            final runtime = _FakeQwenRuntimeProcess();
            runtime.recordArguments(arguments);
            await runtime.start();
            runtimes.add(runtime);
            return runtime;
          },
        );
        addTearDown(service.dispose);

        await service.transcribe(_request(model: firstModel));
        final oldCredential = runtimes.single.bootstrapPayload;
        await service.transcribe(_request(model: secondModel));

        expect(runtimes, hasLength(2));
        expect(runtimes.first.isStopped, isTrue);
        expect(runtimes.last.bootstrapPayload, isNot(oldCredential));
        expect(
          await _healthStatus(runtimes.last.port, oldCredential),
          HttpStatus.unauthorized,
        );
        expect(runtimes.first.requestPaths, [
          '/healthz',
          '/healthz',
          '/v1/transcribe',
        ]);
        expect(runtimes.last.requestPaths, [
          '/healthz',
          '/healthz',
          '/v1/transcribe',
          '/healthz',
        ]);
      },
    );

    test(
      'cancellation aborts a signed request and closes the runtime',
      () async {
        final runtime = _FakeQwenRuntimeProcess(stallTranscription: true);
        final service = Qwen3AsrNativeTranscriptionService(
          startRuntimeProcess: (_, arguments) async {
            runtime.recordArguments(arguments);
            await runtime.start();
            return runtime;
          },
        );
        addTearDown(service.dispose);

        final running = service.transcribe(_request(model: firstModel));
        await runtime.transcriptionReceived.future.timeout(
          const Duration(seconds: 2),
        );
        await service.cancel();

        await expectLater(
          running,
          throwsA(
            isA<TranscriptionException>().having(
              (error) => error.kind,
              'failure kind',
              TranscriptionFailureKind.cancelled,
            ),
          ),
        );
        await runtime.stopped.future.timeout(const Duration(seconds: 2));
        expect(runtime.requestPaths, [
          '/healthz',
          '/healthz',
          '/v1/transcribe',
        ]);
      },
    );

    test('idle shutdown closes the server and invalidates its session', () async {
      final runtime = _FakeQwenRuntimeProcess();
      final service = Qwen3AsrNativeTranscriptionService(
        idleShutdownDelay: const Duration(milliseconds: 1),
        startRuntimeProcess: (_, arguments) async {
          runtime.recordArguments(arguments);
          await runtime.start();
          return runtime;
        },
      );
      addTearDown(service.dispose);

      await service.transcribe(_request(model: firstModel));
      final oldCredential = runtime.bootstrapPayload;
      await runtime.stopped.future.timeout(const Duration(seconds: 2));

      expect(runtime.isStopped, isTrue);
      expect(await _healthStatus(runtime.port, oldCredential), isNull);
    });

    TranscriptionRequest _request({required File model}) => TranscriptionRequest(
      inputAudioPath: input.path,
      normalizedInputAudioPath: normalized.path,
      outputDirectory: '${tempDirectory.path}/output',
      config: TranscriptionConfig(
        qwenExecutable: executable.path,
        qwenModelPath: model.path,
        qwenAlignerModelPath: alignerModel.path,
        qwenDevice: 'cpu',
        qwenDtype: 'f32',
        ffmpegExecutable: executable.path,
        whisperExecutable: 'unused-whisper',
        modelPath: 'unused-whisper-model',
        language: 'en',
      ),
    );
  });
}

Future<File> _touch(Directory directory, String name, List<int> bytes) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<int?> _healthStatus(int port, String bootstrapPayload) async {
  final secret = base64Url.decode(base64Url.normalize(bootstrapPayload));
  final uri = Uri.parse('http://127.0.0.1:$port/healthz');
  final nonce = List<int>.generate(16, (index) => index).map(_hexByte).join();
  final bodyHash = sha256.convert(const <int>[]).toString();
  final canonical =
      'lyricforge-qwen-request-v1\nGET\n/healthz\n$bodyHash\n$nonce';
  final mac = Hmac(sha256, secret).convert(utf8.encode(canonical)).toString();
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(QwenRuntimeSessionAuth.requestHeader, '$nonce:$mac');
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } on IOException {
    return null;
  } finally {
    client.close(force: true);
  }
}

String _hexByte(int value) => value.toRadixString(16).padLeft(2, '0');

class _FakeQwenRuntimeProcess implements Process {
  final bool authenticateResponse;
  final bool stallTranscription;
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final _BootstrapInput _bootstrapInput = _BootstrapInput();
  final List<ProcessSignal> killSignals = [];
  final List<String> requestPaths = [];
  final List<String> receivedBodies = [];
  final List<String> receivedHeaders = [];
  final List<String> _arguments = [];
  final Completer<void> transcriptionReceived = Completer<void>();
  final Completer<void> stopped = Completer<void>();

  late final IOSink _stdin = IOSink(_bootstrapInput);
  late HttpServer _server;
  bool _started = false;

  _FakeQwenRuntimeProcess({
    this.authenticateResponse = true,
    this.stallTranscription = false,
  });

  int get port => _server.port;
  bool get isStopped => _exitCode.isCompleted;
  String get bootstrapPayload => _bootstrapInput.payload;
  bool get argumentsForPortZero =>
      _arguments.indexOf('--port') >= 0 &&
      _arguments.indexOf('--port') + 1 < _arguments.length &&
      _arguments[_arguments.indexOf('--port') + 1] == '0' &&
      _arguments.contains('--session-auth-stdin');

  void recordArguments(List<String> arguments) {
    _arguments
      ..clear()
      ..addAll(arguments);
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handleRequest);
    _started = true;
    _stdout.add(utf8.encode('LYRICFORGE_QWEN_READY_V1 ${_server.port}\n'));
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final bodyBuilder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bodyBuilder.add(chunk);
    }
    final body = bodyBuilder.takeBytes();
    final bodyText = utf8.decode(body);
    requestPaths.add(request.uri.path);
    receivedBodies.add(bodyText);
    final authHeader = request.headers.value(
      QwenRuntimeSessionAuth.requestHeader,
    );
    if (authHeader != null) receivedHeaders.add(authHeader);

    final secret = base64Url.decode(
      base64Url.normalize(await _bootstrapInput.ready.future),
    );
    if (!_validRequest(request, body, secret, authHeader)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    if (request.uri.path == '/v1/transcribe' && stallTranscription) {
      if (!transcriptionReceived.isCompleted) {
        transcriptionReceived.complete();
      }
      return;
    }

    final responseBody = switch (request.uri.path) {
      '/healthz' => '{"ok":true}',
      '/v1/transcribe' => jsonEncode({
        'results': [
          {
            'language': 'English',
            'segments': [
              {'text': 'recognized lyric', 'start_time': 0.1, 'end_time': 0.4},
            ],
          },
        ],
      }),
      _ => '{}',
    };
    if (authenticateResponse) {
      _addResponseProof(
        request,
        secret,
        authHeader!,
        HttpStatus.ok,
        utf8.encode(responseBody),
      );
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(responseBody);
    await request.response.close();
  }

  bool _validRequest(
    HttpRequest request,
    List<int> body,
    List<int> secret,
    String? header,
  ) {
    if (header == null) return false;
    final parts = header.split(':');
    if (parts.length != 2 || !RegExp(r'^[0-9a-f]{32}$').hasMatch(parts[0])) {
      return false;
    }
    final path = request.uri.hasQuery
        ? '${request.uri.path}?${request.uri.query}'
        : request.uri.path;
    final canonical =
        'lyricforge-qwen-request-v1\n'
        '${request.method}\n'
        '$path\n'
        '${sha256.convert(body)}\n'
        '${parts[0]}';
    final expected = Hmac(sha256, secret).convert(utf8.encode(canonical));
    return expected.toString() == parts[1];
  }

  void _addResponseProof(
    HttpRequest request,
    List<int> secret,
    String header,
    int status,
    List<int> body,
  ) {
    final nonce = header.split(':').first;
    final bodyHash = sha256.convert(body);
    final canonical =
        'lyricforge-qwen-response-v1\n$nonce\n$status\n$bodyHash';
    final proof = Hmac(sha256, secret).convert(utf8.encode(canonical));
    request.response.headers.set(
      QwenRuntimeSessionAuth.responseProofHeader,
      proof.toString(),
    );
  }

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 54321;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if (!_exitCode.isCompleted) _exitCode.complete(0);
    unawaited(_closeResources());
    return true;
  }

  Future<void> _closeResources() async {
    if (_started) await _server.close(force: true);
    if (!_stdout.isClosed) await _stdout.close();
    if (!_stderr.isClosed) await _stderr.close();
    if (!stopped.isCompleted) stopped.complete();
  }
}

class _BootstrapInput implements StreamConsumer<List<int>> {
  final Completer<String> ready = Completer<String>();
  final BytesBuilder _line = BytesBuilder(copy: false);
  String? _payload;

  String get payload => _payload ?? '';

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      for (final byte in bytes) {
        if (byte == 10) {
          if (!ready.isCompleted) {
            final value = utf8.decode(_line.takeBytes()).trim();
            _payload = value;
            ready.complete(value);
          }
        } else {
          _line.addByte(byte);
        }
      }
    }
  }

  @override
  Future<void> close() async {}
}
