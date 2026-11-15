import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen3_asr_native_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen_native_runtime_session.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

void main() {
  late _TestIdentity identity;

  setUpAll(() async {
    identity = await _TestIdentity.load();
  });

  test('session tokens are fresh and readiness records are bounded', () {
    final first = createQwenRuntimeSessionToken();
    final second = createQwenRuntimeSessionToken();

    expect(isQwenRuntimeSessionToken(first), isTrue);
    expect(isQwenRuntimeSessionToken(second), isTrue);
    expect(first, isNot(second));
    expect(first, isNot(contains('=')));

    final record =
        '$qwenRuntimeReadyPrefix\t49152\t'
        '${base64Encode(identity.certificateDer)}';
    final parsed = parseQwenRuntimeReadyRecord(record);
    expect(parsed.port, 49152);
    expect(parsed.certificateDer, identity.certificateDer);
    expect(
      () => parseQwenRuntimeReadyRecord(
        '$qwenRuntimeReadyPrefix\t0\t${base64Encode(identity.certificateDer)}',
      ),
      throwsFormatException,
    );
    expect(
      () => parseQwenRuntimeReadyRecord(
        '$qwenRuntimeReadyPrefix\t49152\t${'A' * 20000}',
      ),
      throwsFormatException,
    );
  });

  test(
    'cancel waits for a child that finishes starting after cancellation',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'qwen_start_cancel_',
      );
      final launchRequested = Completer<void>();
      final releaseLaunch = Completer<Process>();
      final killStarted = Completer<void>();
      final allowExit = Completer<void>();
      final process = _FakeRuntimeProcess(
        onKill: () async {
          if (!killStarted.isCompleted) killStarted.complete();
          await allowExit.future;
        },
      );
      var processExited = false;
      unawaited(process.exitCode.then((_) => processExited = true));

      Future<Process> launchRuntime(
        String executable,
        List<String> arguments,
        Map<String, String> environment,
      ) {
        if (!launchRequested.isCompleted) launchRequested.complete();
        return releaseLaunch.future;
      }

      final qwenPath = _path(temporaryDirectory, 'qwen3-asr');
      final ffmpegPath = _path(temporaryDirectory, 'ffmpeg');
      final inputPath = _path(temporaryDirectory, 'song.wav');
      final normalizedPath = _path(temporaryDirectory, 'normalized.wav');
      await File(qwenPath).writeAsBytes([1]);
      await File(ffmpegPath).writeAsBytes([1]);
      await File(inputPath).writeAsBytes(_wavBytes());
      await File(normalizedPath).writeAsBytes(_wavBytes());

      final service = Qwen3AsrNativeTranscriptionService.forTesting(
        runtimeProcessStarter: launchRuntime,
      );
      final running = service.transcribe(
        TranscriptionRequest(
          inputAudioPath: inputPath,
          normalizedInputAudioPath: normalizedPath,
          outputDirectory: _path(temporaryDirectory, 'output'),
          config: _config(qwenPath: qwenPath, ffmpegPath: ffmpegPath),
        ),
      );

      var cancelCompleted = false;
      late final Future<void> cancelling;
      try {
        await launchRequested.future.timeout(const Duration(seconds: 2));
        cancelling = service.cancel().whenComplete(() {
          cancelCompleted = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(cancelCompleted, isFalse);

        releaseLaunch.complete(process);
        await killStarted.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(processExited, isFalse);
        expect(cancelCompleted, isFalse);

        allowExit.complete();
        await cancelling.timeout(const Duration(seconds: 2));
        expect(processExited, isTrue);
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
      } finally {
        if (!releaseLaunch.isCompleted) releaseLaunch.complete(process);
        if (!allowExit.isCompleted) allowExit.complete();
        await service.dispose();
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'redacts the child session token from runtime diagnostics',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'qwen_token_redaction_',
      );
      late String childToken;
      final service = Qwen3AsrNativeTranscriptionService.forTesting(
        runtimeProcessStarter: (executable, arguments, environment) async {
          childToken = environment[qwenRuntimeSessionTokenEnvironment]!;
          return _FakeRuntimeProcess(onKill: () async {})
            ..emitStderr('runtime diagnostic $childToken')
            ..finish(1);
        },
        idleShutdownDelay: const Duration(days: 1),
      );
      final qwenPath = _path(temporaryDirectory, 'qwen3-asr');
      final ffmpegPath = _path(temporaryDirectory, 'ffmpeg');
      final inputPath = _path(temporaryDirectory, 'song.wav');
      final normalizedPath = _path(temporaryDirectory, 'normalized.wav');
      await File(qwenPath).writeAsBytes([1]);
      await File(ffmpegPath).writeAsBytes([1]);
      await File(inputPath).writeAsBytes(_wavBytes());
      await File(normalizedPath).writeAsBytes(_wavBytes());

      TranscriptionException? failure;
      try {
        await service.transcribe(
          TranscriptionRequest(
            inputAudioPath: inputPath,
            normalizedInputAudioPath: normalizedPath,
            outputDirectory: _path(temporaryDirectory, 'output'),
            config: _config(qwenPath: qwenPath, ffmpegPath: ffmpegPath),
          ),
        );
      } on TranscriptionException catch (error) {
        failure = error;
      } finally {
        await service.dispose();
        await temporaryDirectory.delete(recursive: true);
      }

      expect(failure, isNotNull);
      expect(isQwenRuntimeSessionToken(childToken), isTrue);
      final details = failure?.details ?? '';
      expect(details, contains('[redacted]'));
      expect(details, isNot(contains(childToken)));
    },
  );

  test(
    'a pseudo-health HTTPS server with a different certificate receives no '
    'request body',
    () async {
      final seen = <_RuntimeRequest>[];
      final server = await identity.bindServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        seen.add(
          _RuntimeRequest(
            path: request.uri.path,
            method: request.method,
            authorization: request.headers.value('authorization'),
            uri: request.uri.toString(),
            body: body.isEmpty
                ? null
                : jsonDecode(body) as Map<String, dynamic>,
          ),
        );
        await _respondJson(request, HttpStatus.ok, {'status': 'forged'});
      });
      final wrongPin = Uint8List.fromList(identity.certificateDer);
      wrongPin[0] = wrongPin[0] ^ 1;
      final session = QwenNativeRuntimeSession(
        port: server.port,
        certificateDer: wrongPin,
        token: createQwenRuntimeSessionToken(),
      );
      final client = session.createHttpClient();

      try {
        await expectLater(
          () async {
            final request = await client.getUrl(session.endpoint('/healthz'));
            session.authorize(request);
            return request.close();
          },
          throwsA(anything),
        );
        expect(session.identityRejected, isTrue);
        expect(seen, isEmpty);
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    },
  );

  test(
    'transcription and ForcedAligner use the pinned authenticated session',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'qwen_session_security_',
      );
      final launches = <_RuntimeLaunch>[];
      final requests = <_RuntimeRequest>[];

      Future<Process> launchRuntime(
        String executable,
        List<String> arguments,
        Map<String, String> environment,
      ) async {
        final token = environment[qwenRuntimeSessionTokenEnvironment]!;
        expect(isQwenRuntimeSessionToken(token), isTrue);
        expect(arguments, contains('--port'));
        expect(arguments[arguments.indexOf('--port') + 1], '0');
        expect(arguments, isNot(contains(token)));

        final server = await identity.bindServer((request) async {
          final authorization = request.headers.value('authorization');
          if (authorization != 'Bearer $token') {
            await request.drain<void>();
            requests.add(
              _RuntimeRequest(
                path: request.uri.path,
                method: request.method,
                authorization: authorization,
                uri: request.uri.toString(),
                body: null,
              ),
            );
            await _respondJson(request, HttpStatus.unauthorized, {});
            return;
          }

          Map<String, dynamic>? body;
          final rawBody = await utf8.decoder.bind(request).join();
          if (rawBody.isNotEmpty) {
            body = jsonDecode(rawBody) as Map<String, dynamic>;
          }
          requests.add(
            _RuntimeRequest(
              path: request.uri.path,
              method: request.method,
              authorization: authorization,
              uri: request.uri.toString(),
              body: body,
            ),
          );

          switch (request.uri.path) {
            case '/healthz':
              await _respondJson(request, HttpStatus.ok, {'status': 'ok'});
              break;
            case '/v1/transcribe':
              await _respondJson(request, HttpStatus.ok, {
                'results': [
                  {
                    'language': 'English',
                    'timestamps': {
                      'segment': [
                        {
                          'text': 'recognized words',
                          'start_time': 0.0,
                          'end_time': 0.5,
                        },
                      ],
                    },
                  },
                ],
              });
              break;
            case '/v1/align':
              await _respondJson(request, HttpStatus.ok, {
                'results': [
                  {
                    'items': [
                      {
                        'text': 'confirmed lyric',
                        'start_time': 0.0,
                        'end_time': 0.5,
                      },
                    ],
                  },
                ],
              });
              break;
            default:
              await _respondJson(request, HttpStatus.notFound, {});
              break;
          }
        });
        final process = _FakeRuntimeProcess(
          onKill: () => server.close(force: true),
        )..emitStdout(
            '$qwenRuntimeReadyPrefix\t${server.port}\t'
            '${base64Encode(identity.certificateDer)}',
          );
        launches.add(
          _RuntimeLaunch(token: token, server: server, process: process),
        );
        return process;
      }

      final ffmpegPath = _path(temporaryDirectory, 'ffmpeg');
      final qwenPath = _path(temporaryDirectory, 'qwen3-asr');
      final inputPath = _path(temporaryDirectory, 'song.wav');
      final normalizedPath = _path(temporaryDirectory, 'normalized.wav');
      await File(ffmpegPath).writeAsBytes([1]);
      await File(qwenPath).writeAsBytes([1]);
      await File(inputPath).writeAsBytes(_wavBytes());
      await File(normalizedPath).writeAsBytes(_wavBytes());

      final processSupervisor = AsrProcessSupervisor(
        startProcess: (_, arguments) async {
          await File(arguments.last).writeAsBytes(_wavBytes());
          return _ImmediateProcess();
        },
        terminationGrace: const Duration(milliseconds: 20),
        streamDrainGrace: const Duration(milliseconds: 20),
      );
      final service = Qwen3AsrNativeTranscriptionService.forTesting(
        processSupervisor: processSupervisor,
        runtimeProcessStarter: launchRuntime,
        idleShutdownDelay: const Duration(days: 1),
      );
      final config = _config(qwenPath: qwenPath, ffmpegPath: ffmpegPath);

      try {
        final result = await service.transcribe(
          TranscriptionRequest(
            inputAudioPath: inputPath,
            normalizedInputAudioPath: normalizedPath,
            outputDirectory: _path(temporaryDirectory, 'output'),
            config: config,
            context: 'private lyric context',
          ),
        );
        expect(result.lyrics.lines, hasLength(1));
        expect(result.lyrics.lines.single.text, 'recognized words');

        final aligned = await service.alignReference(
          audioPath: inputPath,
          text: 'confirmed lyric',
          language: 'English',
          audioDuration: const Duration(seconds: 1),
          config: config,
        );
        expect(aligned, hasLength(1));
        expect(aligned.single.text, 'confirmed lyric');
        expect(launches, hasLength(1));

        final token = launches.single.token;
        final transcribeRequest = requests.singleWhere(
          (request) => request.path == '/v1/transcribe',
        );
        expect(transcribeRequest.authorization, 'Bearer $token');
        expect(transcribeRequest.uri, isNot(contains(token)));
        expect(transcribeRequest.body?['audio'], normalizedPath);
        expect(transcribeRequest.body?['context'], 'private lyric context');

        final alignmentRequest = requests.singleWhere(
          (request) => request.path == '/v1/align',
        );
        expect(alignmentRequest.authorization, 'Bearer $token');
        expect(alignmentRequest.uri, isNot(contains(token)));
        expect(alignmentRequest.body?['text'], 'confirmed lyric');
        expect(alignmentRequest.body?['audio'], isA<String>());
      } finally {
        await service.dispose();
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'transcription refuses redirects to another loopback listener',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'qwen_redirect_',
      );
      var redirectedRequests = 0;
      final target = await identity.bindServer((request) async {
        redirectedRequests++;
        await request.drain<void>();
        await _respondJson(request, HttpStatus.ok, {
          'results': [
            {
              'text': 'redirected transcript',
              'timestamps': {
                'segment': [
                  {
                    'text': 'redirected transcript',
                    'start_time': 0,
                    'end_time': 0.5,
                  },
                ],
              },
            },
          ],
        });
      });
      final targetEndpoint = Uri(
        scheme: 'https',
        host: InternetAddress.loopbackIPv4.address,
        port: target.port,
        path: '/v1/transcribe',
      );
      final sourcePaths = <String>[];
      late final String sourceToken;
      late final HttpServer source;
      source = await identity.bindServer((request) async {
        sourcePaths.add(request.uri.path);
        final token = sourceToken;
        await request.drain<void>();
        if (request.headers.value('authorization') != 'Bearer $token') {
          await _respondJson(request, HttpStatus.unauthorized, {});
        } else if (request.uri.path == '/healthz') {
          await _respondJson(request, HttpStatus.ok, {'status': 'ok'});
        } else {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(
              HttpHeaders.locationHeader,
              targetEndpoint.toString(),
            );
          await request.response.close();
        }
      });

      final qwenPath = _path(temporaryDirectory, 'qwen3-asr');
      final ffmpegPath = _path(temporaryDirectory, 'ffmpeg');
      final inputPath = _path(temporaryDirectory, 'song.wav');
      final normalizedPath = _path(temporaryDirectory, 'normalized.wav');
      await File(qwenPath).writeAsBytes([1]);
      await File(ffmpegPath).writeAsBytes([1]);
      await File(inputPath).writeAsBytes(_wavBytes());
      await File(normalizedPath).writeAsBytes(_wavBytes());

      final service = Qwen3AsrNativeTranscriptionService.forTesting(
        runtimeProcessStarter: (executable, arguments, environment) async {
          sourceToken = environment[qwenRuntimeSessionTokenEnvironment]!;
          return _FakeRuntimeProcess(
            onKill: () async {
              await source.close(force: true);
              await target.close(force: true);
            },
          )..emitStdout(
              '$qwenRuntimeReadyPrefix\t${source.port}\t'
              '${base64Encode(identity.certificateDer)}',
            );
        },
        idleShutdownDelay: const Duration(days: 1),
      );

      try {
        await expectLater(
          service.transcribe(
            TranscriptionRequest(
              inputAudioPath: inputPath,
              normalizedInputAudioPath: normalizedPath,
              outputDirectory: _path(temporaryDirectory, 'output'),
              config: _config(qwenPath: qwenPath, ffmpegPath: ffmpegPath),
            ),
          ),
          throwsA(
            isA<TranscriptionException>().having(
              (error) => error.message,
              'message',
              contains('HTTP 302'),
            ),
          ),
        );
        expect(sourcePaths, contains('/healthz'));
        expect(sourcePaths, contains('/v1/transcribe'));
        expect(redirectedRequests, 0);
      } finally {
        await service.dispose();
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'credential rotation rejects a prior token after an idle restart',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'qwen_session_restart_',
      );
      final launches = <_RuntimeLaunch>[];

      Future<Process> launchRuntime(
        String executable,
        List<String> arguments,
        Map<String, String> environment,
      ) async {
        final token = environment[qwenRuntimeSessionTokenEnvironment]!;
        final server = await identity.bindServer((request) async {
          if (request.uri.path == '/healthz') {
            final authorized =
                request.headers.value('authorization') == 'Bearer $token';
            await request.drain<void>();
            await _respondJson(
              request,
              authorized ? HttpStatus.ok : HttpStatus.unauthorized,
              {'status': authorized ? 'ok' : 'unauthorized'},
            );
            return;
          }

          await request.drain<void>();
          await _respondJson(request, HttpStatus.unauthorized, {});
        });
        final process = _FakeRuntimeProcess(
          onKill: () async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            await server.close(force: true);
          },
        )..emitStdout(
            '$qwenRuntimeReadyPrefix\t${server.port}\t'
            '${base64Encode(identity.certificateDer)}',
          );
        launches.add(
          _RuntimeLaunch(token: token, server: server, process: process),
        );
        return process;
      }

      final qwenPath = _path(temporaryDirectory, 'qwen3-asr');
      final ffmpegPath = _path(temporaryDirectory, 'ffmpeg');
      final inputPath = _path(temporaryDirectory, 'song.wav');
      final normalizedPath = _path(temporaryDirectory, 'normalized.wav');
      await File(qwenPath).writeAsBytes([1]);
      await File(ffmpegPath).writeAsBytes([1]);
      await File(inputPath).writeAsBytes(_wavBytes());
      await File(normalizedPath).writeAsBytes(_wavBytes());

      final service = Qwen3AsrNativeTranscriptionService.forTesting(
        runtimeProcessStarter: launchRuntime,
        idleShutdownDelay: const Duration(seconds: 1),
      );
      final request = TranscriptionRequest(
        inputAudioPath: inputPath,
        normalizedInputAudioPath: normalizedPath,
        outputDirectory: _path(temporaryDirectory, 'output'),
        config: _config(qwenPath: qwenPath, ffmpegPath: ffmpegPath),
      );

      try {
        await service.transcribe(request);
      } on TranscriptionException {
        // The restart harness intentionally returns 401 for transcription; the
        // authenticated health check and subsequent session rotation are the
        // assertions under test.
      }

      try {
        expect(launches, hasLength(1));
        await Future<void>.delayed(const Duration(milliseconds: 1050));

        try {
          await service.transcribe(request);
        } on TranscriptionException {
          // As above, this fake only implements authenticated health responses.
        }
        expect(launches, hasLength(2));
        await launches.first.process.exitCode.timeout(
          const Duration(seconds: 2),
        );
        expect(isQwenRuntimeSessionToken(launches[0].token), isTrue);
        expect(isQwenRuntimeSessionToken(launches[1].token), isTrue);
        expect(launches[0].token, isNot(launches[1].token));

        final oldSession = QwenNativeRuntimeSession(
          port: launches[1].server.port,
          certificateDer: identity.certificateDer,
          token: launches[0].token,
        );
        final oldClient = oldSession.createHttpClient();
        try {
          final oldRequest = await oldClient.getUrl(
            oldSession.endpoint('/healthz'),
          );
          oldSession.authorize(oldRequest);
          final oldResponse = await oldRequest.close();
          await oldResponse.drain<void>();
          expect(oldResponse.statusCode, HttpStatus.unauthorized);
        } finally {
          oldClient.close(force: true);
        }

        final newSession = QwenNativeRuntimeSession(
          port: launches[1].server.port,
          certificateDer: identity.certificateDer,
          token: launches[1].token,
        );
        final newClient = newSession.createHttpClient();
        try {
          final newRequest = await newClient.getUrl(
            newSession.endpoint('/healthz'),
          );
          newSession.authorize(newRequest);
          final newResponse = await newRequest.close();
          await newResponse.drain<void>();
          expect(newResponse.statusCode, HttpStatus.ok);
        } finally {
          newClient.close(force: true);
        }
      } finally {
        await service.dispose();
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'an impostor readiness identity fails before transcription data is sent',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'qwen_spoofed_health_',
      );
      final seen = <_RuntimeRequest>[];
      late HttpServer impostor;
      final process = _FakeRuntimeProcess(
        onKill: () => impostor.close(force: true),
      );

      Future<Process> launchImpostor(
        String executable,
        List<String> arguments,
        Map<String, String> environment,
      ) async {
        final token = environment[qwenRuntimeSessionTokenEnvironment]!;
        expect(isQwenRuntimeSessionToken(token), isTrue);
        impostor = await identity.bindServer((request) async {
          final body = await utf8.decoder.bind(request).join();
          seen.add(
            _RuntimeRequest(
              path: request.uri.path,
              method: request.method,
              authorization: request.headers.value('authorization'),
              uri: request.uri.toString(),
              body: body.isEmpty
                  ? null
                  : jsonDecode(body) as Map<String, dynamic>,
            ),
          );
          await _respondJson(request, HttpStatus.ok, {'status': 'fake-health'});
        });
        final wrongIdentity = Uint8List.fromList(identity.certificateDer)
          ..[0] ^= 1;
        process.emitStdout(
          '$qwenRuntimeReadyPrefix\t${impostor.port}\t'
          '${base64Encode(wrongIdentity)}',
        );
        return process;
      }

      final qwenPath = _path(temporaryDirectory, 'qwen3-asr');
      final ffmpegPath = _path(temporaryDirectory, 'ffmpeg');
      final inputPath = _path(temporaryDirectory, 'song.wav');
      final normalizedPath = _path(temporaryDirectory, 'normalized.wav');
      await File(qwenPath).writeAsBytes([1]);
      await File(ffmpegPath).writeAsBytes([1]);
      await File(inputPath).writeAsBytes(_wavBytes());
      await File(normalizedPath).writeAsBytes(_wavBytes());

      final service = Qwen3AsrNativeTranscriptionService.forTesting(
        runtimeProcessStarter: launchImpostor,
        idleShutdownDelay: const Duration(days: 1),
      );

      try {
        await expectLater(
          service.transcribe(
            TranscriptionRequest(
              inputAudioPath: inputPath,
              normalizedInputAudioPath: normalizedPath,
              outputDirectory: _path(temporaryDirectory, 'output'),
              config: _config(qwenPath: qwenPath, ffmpegPath: ffmpegPath),
              context: 'private lyric context',
            ),
          ),
          throwsA(isA<TranscriptionException>()),
        );
        expect(seen, isEmpty);
      } finally {
        await service.dispose();
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );
}

class _TestIdentity {
  final List<int> certificateDer;
  final Uint8List certificatePem;
  final Uint8List privateKeyPem;

  const _TestIdentity({
    required this.certificateDer,
    required this.certificatePem,
    required this.privateKeyPem,
  });

  static Future<_TestIdentity> load() async {
    const root = 'test/fixtures/qwen_runtime_test_identity';
    final certificatePem = await File('$root/certificate.pem').readAsBytes();
    final privateKeyPem = await File('$root/private_key.pem').readAsBytes();
    final encoded = utf8
        .decode(certificatePem)
        .replaceAll(
          RegExp(
            r'-----BEGIN CERTIFICATE-----|'
            r'-----END CERTIFICATE-----|\s',
          ),
          '',
        );
    return _TestIdentity(
      certificateDer: base64Decode(encoded),
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
    );
  }

  SecurityContext serverContext() => SecurityContext()
    ..useCertificateChainBytes(certificatePem)
    ..usePrivateKeyBytes(privateKeyPem);

  Future<HttpServer> bindServer(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext(),
    );
    server.listen((request) => unawaited(handler(request)));
    return server;
  }
}

class _RuntimeLaunch {
  final String token;
  final HttpServer server;
  final _FakeRuntimeProcess process;

  const _RuntimeLaunch({
    required this.token,
    required this.server,
    required this.process,
  });
}

class _RuntimeRequest {
  final String path;
  final String method;
  final String? authorization;
  final String uri;
  final Map<String, dynamic>? body;

  const _RuntimeRequest({
    required this.path,
    required this.method,
    required this.authorization,
    required this.uri,
    required this.body,
  });
}

class _FakeRuntimeProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final IOSink _stdin = IOSink(_DiscardingConsumer());
  final Future<void> Function() onKill;
  bool _killStarted = false;

  _FakeRuntimeProcess({required this.onKill});

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 90123;

  void emitStdout(String line) {
    _stdout.add(utf8.encode('$line\n'));
  }

  void emitStderr(String line) {
    _stderr.add(utf8.encode('$line\n'));
  }

  void finish(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_stderr.isClosed) unawaited(_stderr.close());
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_killStarted) {
      _killStarted = true;
      unawaited(_terminate());
    }
    return true;
  }

  Future<void> _terminate() async {
    await onKill();
    finish(0);
  }
}

class _ImmediateProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Future<int> _exitCode = Future<int>.value(0);
  final IOSink _stdin = IOSink(_DiscardingConsumer());

  _ImmediateProcess() {
    unawaited(_stdout.close());
    unawaited(_stderr.close());
  }

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  int get pid => 90124;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => false;
}

class _DiscardingConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<void> close() async {}
}

Future<void> _respondJson(
  HttpRequest request,
  int statusCode,
  Object body,
) async {
  request.response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}

String _path(Directory directory, String child) =>
    '${directory.path}${Platform.pathSeparator}$child';

List<int> _wavBytes() => List<int>.filled(44 + 16000 * 2, 0);

TranscriptionConfig _config({
  required String qwenPath,
  required String ffmpegPath,
}) => TranscriptionConfig(
  qwenExecutable: qwenPath,
  qwenModelPath: 'Qwen/Qwen3-ASR-0.6B',
  qwenAlignerModelPath: 'Qwen/Qwen3-ForcedAligner-0.6B',
  ffmpegExecutable: ffmpegPath,
  whisperExecutable: 'unused-whisper',
  modelPath: 'unused-whisper-model',
  language: 'en',
);
