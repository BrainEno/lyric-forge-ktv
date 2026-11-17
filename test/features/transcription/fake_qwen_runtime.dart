import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// How a fake runtime signs its HTTP responses.
enum FakeProofMode { valid, missing, wrong }

/// Behaviour knobs for one fake `qwen3-asr serve` launch.
class FakeRuntimeBehavior {
  FakeRuntimeBehavior({
    this.announce = true,
    this.announcedPort,
    this.forgeReadyProof = false,
    this.exitBeforeReadyCode,
    this.stderrBeforeExit = const [],
    this.responseProof = FakeProofMode.valid,
    this.healthProof = FakeProofMode.valid,
    this.transcribeDelay = Duration.zero,
    this.dropTranscribeConnection = false,
    this.echoSecretToStderr = false,
    this.unalignableTranscribeFailures = 0,
    this.transcribeResult,
  });

  bool announce;
  int? announcedPort;
  bool forgeReadyProof;
  int? exitBeforeReadyCode;
  List<String> stderrBeforeExit;
  FakeProofMode responseProof;
  FakeProofMode healthProof;
  Duration transcribeDelay;
  bool dropTranscribeConnection;
  bool echoSecretToStderr;

  /// How many `/v1/transcribe` requests fail the way the pinned runtime does
  /// when a chunk decodes to punctuation only, before requests succeed.
  int unalignableTranscribeFailures;

  /// Replaces the default `hello world` transcription result.
  Map<String, Object?>? transcribeResult;
}

class FakeRuntimeRequest {
  FakeRuntimeRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
    required this.authorized,
  });

  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;
  final bool authorized;
}

/// Starts [FakeRuntimeProcess]es in place of the real native runtime. It
/// implements the same stdin / stdout / HMAC contract as `session_auth.rs`
/// so the Dart client is exercised without a GPU, models or Rust toolchain.
class FakeQwenRuntime {
  FakeQwenRuntime({FakeRuntimeBehavior Function(int launchIndex)? behaviorFor})
    : _behaviorFor = behaviorFor ?? ((_) => FakeRuntimeBehavior());

  final FakeRuntimeBehavior Function(int launchIndex) _behaviorFor;
  final List<FakeRuntimeProcess> launches = <FakeRuntimeProcess>[];
  final List<List<String>> argumentLog = <List<String>>[];

  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    argumentLog.add(List<String>.unmodifiable(arguments));
    final process = FakeRuntimeProcess(
      executable: executable,
      arguments: arguments,
      behavior: _behaviorFor(launches.length),
      pid: 7000 + launches.length,
    );
    launches.add(process);
    return process;
  }

  Future<void> dispose() async {
    for (final process in launches) {
      await process.crash(0);
    }
  }
}

class FakeRuntimeProcess implements Process {
  FakeRuntimeProcess({
    required this.executable,
    required this.arguments,
    required this.behavior,
    required int pid,
  }) : _pid = pid {
    _stdin = IOSink(_StdinConsumer(this));
  }

  final String executable;
  final List<String> arguments;
  final FakeRuntimeBehavior behavior;
  final int _pid;
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  final List<int> _stdinBytes = <int>[];
  final Completer<void> booted = Completer<void>();
  final List<FakeRuntimeRequest> requests = <FakeRuntimeRequest>[];
  final List<ProcessSignal> killSignals = <ProcessSignal>[];
  final Set<String> _seenNonces = <String>{};
  late final IOSink _stdin;
  HttpServer? _server;
  List<int>? _key;
  bool _secretReceived = false;
  bool stdinClosed = false;
  bool _shuttingDown = false;

  /// Everything LyricForge wrote to the runtime's stdin.
  String get stdinText => utf8.decode(_stdinBytes);

  /// The secret line received over stdin, if any.
  String? get secretLine =>
      _secretReceived ? stdinText.split('\n').first : null;

  bool get exited => _exit.isCompleted;

  int? get boundPort => _server?.port;

  Iterable<FakeRuntimeRequest> requestsTo(String path) =>
      requests.where((request) => request.path == path);

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => _pid;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    unawaited(_shutdown(137));
    return true;
  }

  /// Simulates an unexpected runtime crash.
  Future<void> crash([int code = 139]) => _shutdown(code);

  void _onStdin(List<int> data) {
    _stdinBytes.addAll(data);
    if (_secretReceived || !stdinText.contains('\n')) return;
    _secretReceived = true;
    unawaited(_boot(stdinText.split('\n').first));
  }

  void _onStdinClosed() {
    stdinClosed = true;
    // Like the real runtime: EOF on the control pipe means shut down.
    unawaited(_shutdown(0));
  }

  Future<void> _boot(String secretHex) async {
    try {
      if (_shuttingDown) return;
      final exitCode = behavior.exitBeforeReadyCode;
      if (behavior.echoSecretToStderr) {
        _stderr.add(utf8.encode('debug: received secret $secretHex\n'));
      }
      if (exitCode != null) {
        for (final line in behavior.stderrBeforeExit) {
          _stderr.add(utf8.encode('$line\n'));
        }
        await _shutdown(exitCode);
        return;
      }
      _key = _decodeHex(secretHex);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_shuttingDown) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen((request) => unawaited(_handle(request)));
      if (!behavior.announce) return;
      final port = behavior.announcedPort ?? server.port;
      final proof = behavior.forgeReadyProof
          ? '0' * 64
          : _sign('v1-ready\n$port');
      final payload = jsonEncode({'protocol': 1, 'port': port, 'proof': proof});
      _stdout.add(utf8.encode('LYRICFORGE_RUNTIME_READY $payload\n'));
    } finally {
      if (!booted.isCompleted) booted.complete();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final bodyBytes = await _readAll(request);
    final body = utf8.decode(bodyBytes, allowMalformed: true);
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    final nonce = headers['x-lyricforge-nonce'];
    final authorized = _verify(request, headers, bodyBytes);
    requests.add(
      FakeRuntimeRequest(
        method: request.method,
        path: request.uri.path,
        headers: headers,
        body: body,
        authorized: authorized,
      ),
    );
    final response = request.response;
    try {
      if (!authorized || nonce == null) {
        response.statusCode = HttpStatus.unauthorized;
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'error': {'message': 'unauthorized'},
          }),
        );
        await response.close();
        return;
      }

      var status = HttpStatus.ok;
      Object payload;
      var proofMode = behavior.responseProof;
      switch (request.uri.path) {
        case '/healthz':
          proofMode = behavior.healthProof;
          payload = {'ok': true, 'mock': false};
        case '/v1/transcribe':
          if (behavior.transcribeDelay > Duration.zero) {
            await Future<void>.delayed(behavior.transcribeDelay);
          }
          if (behavior.dropTranscribeConnection) {
            final socket = await response.detachSocket(writeHeaders: false);
            socket.destroy();
            return;
          }
          if (behavior.unalignableTranscribeFailures > 0) {
            behavior.unalignableTranscribeFailures--;
            status = HttpStatus.internalServerError;
            payload = {
              'error': 'forced alignment failed: tokenized word_list is empty',
            };
            break;
          }
          final custom = behavior.transcribeResult;
          if (custom != null) {
            payload = {
              'results': [custom],
            };
            break;
          }
          payload = {
            'results': [
              {
                'language': 'English',
                'text': 'hello world',
                'segments': [
                  {
                    'text': 'hello world',
                    'start': 0.5,
                    'end': 1.5,
                    'words': [
                      {'text': 'hello', 'start': 0.5, 'end': 0.9},
                      {'text': 'world', 'start': 0.9, 'end': 1.5},
                    ],
                  },
                ],
              },
            ],
          };
        case '/v1/align':
          payload = {
            'items': [
              {'text': 'hello', 'start_time': 0.1, 'end_time': 0.4},
              {'text': 'world', 'start_time': 0.4, 'end_time': 0.8},
            ],
          };
        default:
          status = HttpStatus.notFound;
          payload = {'error': 'not found'};
      }

      final bytes = utf8.encode(jsonEncode(payload));
      response.statusCode = status;
      response.headers.contentType = ContentType.json;
      switch (proofMode) {
        case FakeProofMode.valid:
          response.headers.set(
            'x-lyricforge-proof',
            _sign('v1-response\n$nonce\n$status\n${sha256.convert(bytes)}'),
          );
        case FakeProofMode.wrong:
          response.headers.set('x-lyricforge-proof', 'f' * 64);
        case FakeProofMode.missing:
          break;
      }
      response.add(bytes);
      await response.close();
    } catch (_) {
      // The client may have aborted (cancel) or the runtime may be stopping.
    }
  }

  bool _verify(
    HttpRequest request,
    Map<String, String> headers,
    List<int> body,
  ) {
    final key = _key;
    final timestamp = headers['x-lyricforge-timestamp'];
    final nonce = headers['x-lyricforge-nonce'];
    final signature = headers['x-lyricforge-signature'];
    if (key == null || timestamp == null || nonce == null) return false;
    if (signature == null || !_seenNonces.add(nonce)) return false;
    final expected = _sign(
      'v1-request\n${request.method}\n${request.uri.path}\n$timestamp\n'
      '$nonce\n${sha256.convert(body)}',
    );
    return expected == signature;
  }

  String _sign(String message) {
    final key = _key;
    if (key == null) return '0' * 64;
    return Hmac(sha256, key).convert(utf8.encode(message)).toString();
  }

  Future<void> _shutdown(int code) async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    final server = _server;
    _server = null;
    try {
      await server?.close(force: true);
    } catch (_) {}
    // Not awaited: a non-broadcast controller only reports close once its
    // listener (already cancelled during cleanup) has seen the done event.
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_stderr.isClosed) unawaited(_stderr.close());
    if (!_exit.isCompleted) _exit.complete(code);
    if (!booted.isCompleted) booted.complete();
  }
}

/// A port squatter: answers everything with `200 {"ok": true}` and records
/// what it was sent, but knows no session secret.
class ImpostorServer {
  ImpostorServer._(this._server) {
    _server.listen((request) async {
      final body = utf8.decode(await _readAll(request), allowMalformed: true);
      requests.add(
        FakeRuntimeRequest(
          method: request.method,
          path: request.uri.path,
          headers: const {},
          body: body,
          authorized: false,
        ),
      );
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true, 'results': []}));
      await request.response.close();
    });
  }

  static Future<ImpostorServer> start() async =>
      ImpostorServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final List<FakeRuntimeRequest> requests = <FakeRuntimeRequest>[];

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);
}

/// A child process that exits immediately; FFmpeg stand-in that creates its
/// output file (the last argument) like the real normalisation command.
class FakeToolProcess implements Process {
  FakeToolProcess(List<String> arguments, {this.code = 0}) {
    if (code == 0 && arguments.isNotEmpty) {
      File(arguments.last).writeAsBytesSync(List<int>.filled(44 + 32000, 0));
    }
    scheduleMicrotask(() {
      _stdout.close();
      _stderr.close();
      _exit.complete(code);
    });
  }

  final int code;
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  final IOSink _stdin = IOSink(_NullConsumer());

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 9999;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

class _StdinConsumer implements StreamConsumer<List<int>> {
  _StdinConsumer(this._process);

  final FakeRuntimeProcess _process;

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    final done = Completer<void>();
    stream.listen(
      _process._onStdin,
      onDone: done.complete,
      onError: (Object _) => done.complete(),
    );
    return done.future;
  }

  @override
  Future<void> close() async => _process._onStdinClosed();
}

class _NullConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}
}

Future<List<int>> _readAll(Stream<List<int>> stream) =>
    stream.fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));

List<int> _decodeHex(String hex) => [
  for (var index = 0; index + 1 < hex.length; index += 2)
    int.parse(hex.substring(index, index + 2), radix: 16),
];
