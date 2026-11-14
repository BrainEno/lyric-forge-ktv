import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/models/transcription_models.dart';
import 'asr_process_supervisor.dart';
import 'forced_alignment_http_client.dart';

/// Wire contract shared with the patched Qwen runtime
/// (`tool/patches/qwen3-asr-session-auth.patch`, `session_auth.rs`).
///
/// The runtime is launched with [sessionFlag]. LyricForge writes a fresh
/// 32-byte secret to its stdin, the runtime binds `127.0.0.1:0` itself and
/// announces the bound port on its private stdout pipe, and every HTTP
/// exchange is HMAC-SHA256 signed in both directions. The secret never appears
/// in argv, URLs, logs, persisted files or exception details.
abstract final class QwenRuntimeSessionProtocol {
  static const String sessionFlag = '--lyricforge-session-stdin';
  static const String readyPrefix = 'LYRICFORGE_RUNTIME_READY ';
  static const int version = 1;
  static const String loopbackHost = '127.0.0.1';

  static const String timestampHeader = 'x-lyricforge-timestamp';
  static const String nonceHeader = 'x-lyricforge-nonce';
  static const String signatureHeader = 'x-lyricforge-signature';
  static const String proofHeader = 'x-lyricforge-proof';

  static const int secretBytes = 32;
  static const int nonceBytes = 16;

  /// Model/device arguments shared by every Qwen `serve` launch. Listener
  /// arguments are appended by [QwenRuntimePlatformPolicy.listenerArguments]
  /// so no caller can reintroduce a parent-side port reservation.
  static List<String> serveArguments(TranscriptionConfig config) => [
    '--device',
    config.qwenDevice,
    '--dtype',
    config.qwenDtype,
    'serve',
    '--model',
    config.qwenModelPath,
    '--forced-aligner',
    config.qwenAlignerModelPath,
  ];

  static String readyMessage(int port) => 'v1-ready\n$port';

  static String requestMessage({
    required String method,
    required String pathAndQuery,
    required String timestamp,
    required String nonce,
    required String bodySha256,
  }) => 'v1-request\n$method\n$pathAndQuery\n$timestamp\n$nonce\n$bodySha256';

  static String responseMessage({
    required String nonce,
    required int statusCode,
    required String bodySha256,
  }) => 'v1-response\n$nonce\n$statusCode\n$bodySha256';

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  static bool constantTimeEquals(String actual, String expected) {
    var difference = actual.length ^ expected.length;
    final length = max(actual.length, expected.length);
    for (var index = 0; index < length; index++) {
      final a = index < actual.length ? actual.codeUnitAt(index) : 0;
      final b = index < expected.length ? expected.codeUnitAt(index) : 0;
      difference |= a ^ b;
    }
    return difference == 0;
  }

  static String pathAndQuery(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }
}

/// Removes anything that looks like key material before a runtime log line is
/// kept for diagnostics. The runtime never prints the secret; this is defence
/// in depth for third-party output (and also hides 64-hex digests).
abstract final class QwenRuntimeLogRedactor {
  static final RegExp _longHex = RegExp(r'[0-9a-fA-F]{48,}');
  static const int maxLineLength = 1024;

  static String redact(String line) {
    final redacted = line.replaceAll(_longHex, '<redacted>');
    if (redacted.length <= maxLineLength) return redacted;
    return redacted.substring(redacted.length - maxLineLength);
  }
}

/// Per-launch secret. It is generated with [Random.secure], handed to the
/// runtime once over stdin, and zeroed when the session ends.
final class QwenRuntimeSessionSecret {
  QwenRuntimeSessionSecret._(this._key);

  factory QwenRuntimeSessionSecret.generate({Random? random}) {
    final source = random ?? Random.secure();
    while (true) {
      final key = Uint8List(QwenRuntimeSessionProtocol.secretBytes);
      for (var index = 0; index < key.length; index++) {
        key[index] = source.nextInt(256);
      }
      if (key.any((byte) => byte != 0)) return QwenRuntimeSessionSecret._(key);
    }
  }

  /// Builds a secret from known bytes. Intended for protocol tests only.
  factory QwenRuntimeSessionSecret.fromHex(String hex) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) {
      throw ArgumentError('A session secret must be 64 lowercase hex digits.');
    }
    final key = Uint8List(QwenRuntimeSessionProtocol.secretBytes);
    for (var index = 0; index < key.length; index++) {
      key[index] = int.parse(
        hex.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }
    return QwenRuntimeSessionSecret._(key);
  }

  final Uint8List _key;
  bool _revoked = false;

  bool get isRevoked => _revoked;

  /// The single stdin line consumed by the runtime. Never log this value.
  String get stdinLine {
    _ensureActive();
    return _hex(_key);
  }

  String sign(String message) {
    _ensureActive();
    return Hmac(sha256, _key).convert(utf8.encode(message)).toString();
  }

  void revoke() {
    _key.fillRange(0, _key.length, 0);
    _revoked = true;
  }

  void _ensureActive() {
    if (_revoked) {
      throw StateError('The Qwen runtime session secret has been revoked.');
    }
  }

  @override
  String toString() => 'QwenRuntimeSessionSecret(<redacted>)';
}

String _hex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// How an identity probe against `/healthz` ended.
enum QwenRuntimeIdentity {
  /// The response carried a valid proof for this session's secret.
  verified,

  /// No HTTP answer (connection refused/reset or timeout).
  unreachable,

  /// Something answered without a valid proof: never trust it.
  rejected,
}

/// Request headers plus the response check for one signed exchange.
final class QwenRuntimeRequestAuthorization
    implements ForcedAlignmentRequestAuthorization {
  QwenRuntimeRequestAuthorization._(this._session, this.nonce, this.headers);

  final QwenRuntimeSession _session;
  final String nonce;

  @override
  final Map<String, String> headers;

  @override
  bool acceptsResponse({
    required int statusCode,
    required HttpHeaders headers,
    required List<int> body,
  }) {
    final values = headers[QwenRuntimeSessionProtocol.proofHeader];
    if (values == null || values.length != 1) return false;
    return _session.verifyResponse(
      nonce: nonce,
      statusCode: statusCode,
      proof: values.single,
      body: body,
    );
  }
}

/// Platform adapter for the runtime listener. All platforms share one launch
/// interface; they differ only in how the runtime keeps its listener exclusive.
final class QwenRuntimePlatformPolicy {
  const QwenRuntimePlatformPolicy._({
    required this.operatingSystem,
    required this.exclusiveBindMechanism,
  });

  factory QwenRuntimePlatformPolicy.forOperatingSystem(String os) {
    return switch (os) {
      'windows' => const QwenRuntimePlatformPolicy._(
        operatingSystem: 'windows',
        exclusiveBindMechanism:
            'SO_EXCLUSIVEADDRUSE set by the runtime before bind(127.0.0.1:0)',
      ),
      'macos' || 'ios' => QwenRuntimePlatformPolicy._(
        operatingSystem: os,
        exclusiveBindMechanism:
            'BSD bind semantics: no SO_REUSEPORT on the runtime listener',
      ),
      _ => QwenRuntimePlatformPolicy._(
        operatingSystem: os,
        exclusiveBindMechanism:
            'Linux bind semantics: no SO_REUSEPORT on the runtime listener',
      ),
    };
  }

  factory QwenRuntimePlatformPolicy.current() =>
      QwenRuntimePlatformPolicy.forOperatingSystem(Platform.operatingSystem);

  final String operatingSystem;
  final String exclusiveBindMechanism;

  /// The runtime binds port 0 itself; there is no parent-side reservation.
  List<String> listenerArguments() => const [
    '--host',
    QwenRuntimeSessionProtocol.loopbackHost,
    '--port',
    '0',
    QwenRuntimeSessionProtocol.sessionFlag,
  ];
}

/// One authenticated runtime process. Created only by [QwenRuntimeLauncher]
/// after the port announcement and a signed `/healthz` round trip verified.
class QwenRuntimeSession implements ForcedAlignmentRequestAuthenticator {
  QwenRuntimeSession._({
    required this.port,
    required this.generation,
    required QwenRuntimeSessionSecret secret,
    required _RuntimeChild child,
    required AsrProcessSupervisor supervisor,
    required Random random,
    required DateTime Function() clock,
  }) : _secret = secret,
       _child = child,
       _supervisor = supervisor,
       _random = random,
       _clock = clock {
    _child.onExit = _secret.revoke;
  }

  final int port;

  /// Monotonic launch counter, for diagnostics and stale-session checks.
  final int generation;
  final QwenRuntimeSessionSecret _secret;
  final _RuntimeChild _child;
  final AsrProcessSupervisor _supervisor;
  final Random _random;
  final DateTime Function() _clock;
  bool _closed = false;

  bool get isAlive => !_closed && !_child.exited && !_secret.isRevoked;

  int get pid => _child.process.pid;

  /// Redacted runtime output, safe to include in diagnostics.
  List<String> get logTail => List<String>.unmodifiable(_child.logTail);

  Uri endpoint(String path) => Uri(
    scheme: 'http',
    host: QwenRuntimeSessionProtocol.loopbackHost,
    port: port,
    path: path,
  );

  @override
  QwenRuntimeRequestAuthorization authorize(
    String method,
    Uri uri,
    List<int> body,
  ) {
    if (!isAlive) {
      throw const QwenRuntimeSessionClosedException();
    }
    if (uri.scheme != 'http' ||
        uri.host != QwenRuntimeSessionProtocol.loopbackHost ||
        uri.port != port) {
      throw ArgumentError.value(
        '${uri.scheme}://${uri.host}:${uri.port}',
        'uri',
        'Signed requests may only target this session endpoint.',
      );
    }
    final timestamp = _clock().millisecondsSinceEpoch.toString();
    final nonce = _nonce();
    final signature = _secret.sign(
      QwenRuntimeSessionProtocol.requestMessage(
        method: method.toUpperCase(),
        pathAndQuery: QwenRuntimeSessionProtocol.pathAndQuery(uri),
        timestamp: timestamp,
        nonce: nonce,
        bodySha256: QwenRuntimeSessionProtocol.sha256Hex(body),
      ),
    );
    return QwenRuntimeRequestAuthorization._(this, nonce, {
      QwenRuntimeSessionProtocol.timestampHeader: timestamp,
      QwenRuntimeSessionProtocol.nonceHeader: nonce,
      QwenRuntimeSessionProtocol.signatureHeader: signature,
    });
  }

  bool verifyResponse({
    required String nonce,
    required int statusCode,
    required String? proof,
    required List<int> body,
  }) {
    if (proof == null || _secret.isRevoked) return false;
    final expected = _secret.sign(
      QwenRuntimeSessionProtocol.responseMessage(
        nonce: nonce,
        statusCode: statusCode,
        bodySha256: QwenRuntimeSessionProtocol.sha256Hex(body),
      ),
    );
    return QwenRuntimeSessionProtocol.constantTimeEquals(proof, expected);
  }

  /// Signed `GET /healthz`. Only a response proven with this session's secret
  /// counts; a plain `200 OK` from whatever owns the port is [rejected].
  Future<QwenRuntimeIdentity> checkIdentity(
    HttpClient client, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!isAlive) return QwenRuntimeIdentity.rejected;
    final uri = endpoint('/healthz');
    final authorization = authorize('GET', uri, const <int>[]);
    HttpClientRequest? request;
    try {
      request = await client.getUrl(uri).timeout(timeout);
      authorization.headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final body = await readHttpBody(response).timeout(timeout);
      if (!authorization.acceptsResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: body,
      )) {
        return QwenRuntimeIdentity.rejected;
      }
      if (response.statusCode != HttpStatus.ok) {
        return QwenRuntimeIdentity.rejected;
      }
      final decoded = jsonDecode(utf8.decode(body));
      return decoded is Map && decoded['ok'] == true
          ? QwenRuntimeIdentity.verified
          : QwenRuntimeIdentity.rejected;
    } on FormatException {
      return QwenRuntimeIdentity.rejected;
    } on TimeoutException catch (error) {
      request?.abort(error);
      return QwenRuntimeIdentity.unreachable;
    } on IOException {
      return QwenRuntimeIdentity.unreachable;
    }
  }

  /// Revokes the secret, closes the control pipe (the runtime exits on EOF)
  /// and then terminates the process with the supervisor's bounded escalation.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _secret.revoke();
    await _child.dispose(_supervisor);
  }

  String _nonce() {
    final buffer = StringBuffer();
    for (
      var index = 0;
      index < QwenRuntimeSessionProtocol.nonceBytes;
      index++
    ) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  @override
  String toString() =>
      'QwenRuntimeSession(port: $port, generation: $generation, '
      'alive: $isAlive)';
}

class QwenRuntimeSessionClosedException implements Exception {
  const QwenRuntimeSessionClosedException();

  @override
  String toString() => 'QwenRuntimeSessionClosedException';
}

enum QwenRuntimeLaunchFailure {
  /// The executable could not be started at all.
  startFailed,

  /// The runtime exited before announcing a port.
  exitedDuringStartup,

  /// The runtime does not understand the session flag (unpatched build).
  unsupportedRuntime,

  /// No port announcement before the startup budget ran out.
  startupTimeout,

  /// The announcement or `/healthz` answer was not proven with the secret.
  identityRejected,

  /// The announced port never answered the signed identity probe.
  identityUnreachable,

  /// The caller cancelled the launch.
  cancelled,
}

class QwenRuntimeLaunchException implements Exception {
  const QwenRuntimeLaunchException(this.failure, {this.details = ''});

  final QwenRuntimeLaunchFailure failure;

  /// Redacted diagnostics (runtime log tail or OS error message).
  final String details;

  @override
  String toString() => 'QwenRuntimeLaunchException(${failure.name}): $details';
}

typedef QwenRuntimeProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Starts Qwen `serve` processes in authenticated session mode.
class QwenRuntimeLauncher {
  QwenRuntimeLauncher({
    QwenRuntimeProcessStarter? startProcess,
    AsrProcessSupervisor? supervisor,
    HttpClient Function()? httpClientFactory,
    QwenRuntimePlatformPolicy? platform,
    Random? random,
    DateTime Function()? clock,
    this.pollInterval = const Duration(milliseconds: 100),
    this.identityAttempts = 10,
    this.identityRetryDelay = const Duration(milliseconds: 200),
    this.identityTimeout = const Duration(seconds: 2),
    this.maxLogLines = 40,
  }) : _startProcess = startProcess ?? _startPlatformProcess,
       _supervisor = supervisor ?? AsrProcessSupervisor(),
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       platform = platform ?? QwenRuntimePlatformPolicy.current(),
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final QwenRuntimeProcessStarter _startProcess;
  final AsrProcessSupervisor _supervisor;
  final HttpClient Function() _httpClientFactory;
  final QwenRuntimePlatformPolicy platform;
  final Random _random;
  final DateTime Function() _clock;
  final Duration pollInterval;
  final int identityAttempts;
  final Duration identityRetryDelay;
  final Duration identityTimeout;
  final int maxLogLines;
  int _generation = 0;

  static Future<Process> _startPlatformProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  );

  /// Full argument vector for a launch. It never contains the secret.
  List<String> argumentsFor(List<String> serveArguments) => [
    ...serveArguments,
    ...platform.listenerArguments(),
  ];

  /// Launches the runtime and returns only after its identity is proven.
  ///
  /// On every failure path the secret is revoked, the control pipe is closed
  /// and the process is terminated before the exception propagates.
  Future<QwenRuntimeSession> start({
    required String executable,
    required List<String> serveArguments,
    required Duration startupTimeout,
    String? workingDirectory,
    bool Function()? isCancelled,
    void Function(String line)? onLogLine,
    void Function(Process process)? onProcessStarted,
  }) async {
    bool cancelled() {
      try {
        return isCancelled?.call() ?? false;
      } catch (_) {
        return true;
      }
    }

    if (cancelled()) {
      throw const QwenRuntimeLaunchException(
        QwenRuntimeLaunchFailure.cancelled,
      );
    }

    final generation = ++_generation;
    final secret = QwenRuntimeSessionSecret.generate(random: _random);
    final Process process;
    try {
      process = await _startProcess(
        executable,
        argumentsFor(serveArguments),
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (error) {
      secret.revoke();
      throw QwenRuntimeLaunchException(
        QwenRuntimeLaunchFailure.startFailed,
        details: QwenRuntimeLogRedactor.redact(error.message),
      );
    }

    final child = _RuntimeChild(
      process,
      maxLogLines: maxLogLines,
      onLogLine: onLogLine,
    );
    var handedOff = false;
    try {
      try {
        onProcessStarted?.call(process);
      } catch (_) {
        // Observers must not break the launch or its cleanup.
      }

      try {
        process.stdin.add(utf8.encode('${secret.stdinLine}\n'));
        await process.stdin.flush();
      } catch (_) {
        // The runtime exited before reading its secret; the exit branch
        // below reports it with the (redacted) log tail.
      }

      final stopwatch = Stopwatch()..start();
      final wake = Future.any<void>([
        child.announcement.future.then<void>((_) {}),
        child.exitFuture.then<void>((_) {}),
      ]);
      while (!child.announcement.isCompleted) {
        if (cancelled()) {
          throw const QwenRuntimeLaunchException(
            QwenRuntimeLaunchFailure.cancelled,
          );
        }
        if (child.exited) {
          // Let already-buffered output reach the log tail first.
          await child.drained.timeout(
            const Duration(milliseconds: 200),
            onTimeout: () {},
          );
          if (child.announcement.isCompleted) break;
          throw QwenRuntimeLaunchException(
            child.rejectedSessionFlag
                ? QwenRuntimeLaunchFailure.unsupportedRuntime
                : QwenRuntimeLaunchFailure.exitedDuringStartup,
            details: child.logTail.join('\n'),
          );
        }
        final remaining = startupTimeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          throw QwenRuntimeLaunchException(
            QwenRuntimeLaunchFailure.startupTimeout,
            details: child.logTail.join('\n'),
          );
        }
        await Future.any<void>([
          wake,
          Future<void>.delayed(
            remaining < pollInterval ? remaining : pollInterval,
          ),
        ]);
      }

      final announced = await child.announcement.future;
      final port = announced.verifiedPort(secret);
      if (port == null) {
        throw const QwenRuntimeLaunchException(
          QwenRuntimeLaunchFailure.identityRejected,
          details: 'runtime port announcement was malformed or unproven',
        );
      }

      final session = QwenRuntimeSession._(
        port: port,
        generation: generation,
        secret: secret,
        child: child,
        supervisor: _supervisor,
        random: _random,
        clock: _clock,
      );

      final client = _httpClientFactory()..connectionTimeout = identityTimeout;
      try {
        for (var attempt = 0; attempt < identityAttempts; attempt++) {
          if (cancelled()) {
            throw const QwenRuntimeLaunchException(
              QwenRuntimeLaunchFailure.cancelled,
            );
          }
          if (!session.isAlive) {
            throw QwenRuntimeLaunchException(
              QwenRuntimeLaunchFailure.exitedDuringStartup,
              details: child.logTail.join('\n'),
            );
          }
          final identity = await session.checkIdentity(
            client,
            timeout: identityTimeout,
          );
          switch (identity) {
            case QwenRuntimeIdentity.verified:
              handedOff = true;
              return session;
            case QwenRuntimeIdentity.rejected:
              throw const QwenRuntimeLaunchException(
                QwenRuntimeLaunchFailure.identityRejected,
                details:
                    'the announced port answered without a valid session proof',
              );
            case QwenRuntimeIdentity.unreachable:
              await Future<void>.delayed(identityRetryDelay);
          }
        }
        throw const QwenRuntimeLaunchException(
          QwenRuntimeLaunchFailure.identityUnreachable,
          details: 'the announced port never answered the signed probe',
        );
      } finally {
        client.close(force: true);
      }
    } finally {
      if (!handedOff) {
        secret.revoke();
        await child.dispose(_supervisor);
      }
    }
  }
}

/// Reads a full HTTP body as bytes (proofs cover the exact bytes received).
Future<Uint8List> readHttpBody(Stream<List<int>> response) async {
  final builder = await response.fold<BytesBuilder>(
    BytesBuilder(copy: false),
    (builder, chunk) => builder..add(chunk),
  );
  return builder.takeBytes();
}

class _ReadyAnnouncement {
  const _ReadyAnnouncement(this.payload);

  final String payload;

  int? verifiedPort(QwenRuntimeSessionSecret secret) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final protocol = decoded['protocol'];
    final port = decoded['port'];
    final proof = decoded['proof'];
    if (protocol != QwenRuntimeSessionProtocol.version ||
        port is! int ||
        port <= 0 ||
        port > 65535 ||
        proof is! String ||
        secret.isRevoked) {
      return null;
    }
    final expected = secret.sign(QwenRuntimeSessionProtocol.readyMessage(port));
    return QwenRuntimeSessionProtocol.constantTimeEquals(proof, expected)
        ? port
        : null;
  }
}

/// Owns the runtime process, its pipes and the redacted log tail.
class _RuntimeChild {
  _RuntimeChild(
    this.process, {
    required int maxLogLines,
    void Function(String line)? onLogLine,
  }) : _maxLogLines = maxLogLines,
       _onLogLine = onLogLine {
    // A runtime that dies early turns stdin writes into broken-pipe errors;
    // they are handled at the write site and must not escape as unhandled.
    unawaited(process.stdin.done.then<void>((_) {}, onError: (Object _) {}));
    exitFuture = process.exitCode.then<int>(
      (code) {
        _markExited();
        return code;
      },
      onError: (Object _) {
        _markExited();
        return -1;
      },
    );
    _stdout = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onStdoutLine,
          onError: (Object _) {},
          onDone: _stdoutDone.complete,
          cancelOnError: false,
        );
    _stderr = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _record,
          onError: (Object _) {},
          onDone: _stderrDone.complete,
          cancelOnError: false,
        );
  }

  final Process process;
  final int _maxLogLines;
  final void Function(String line)? _onLogLine;
  final Completer<_ReadyAnnouncement> announcement =
      Completer<_ReadyAnnouncement>();
  final List<String> logTail = <String>[];
  final Completer<void> _stdoutDone = Completer<void>();
  final Completer<void> _stderrDone = Completer<void>();
  late final Future<int> exitFuture;
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  void Function()? onExit;
  bool exited = false;
  bool rejectedSessionFlag = false;
  bool _disposed = false;

  Future<void> get drained async {
    await Future.wait<void>([_stdoutDone.future, _stderrDone.future]);
  }

  void _markExited() {
    exited = true;
    try {
      onExit?.call();
    } catch (_) {
      // Revocation must not surface as an unhandled async error.
    }
  }

  void _onStdoutLine(String line) {
    if (line.startsWith(QwenRuntimeSessionProtocol.readyPrefix)) {
      // Only the first announcement counts; it is never logged.
      if (!announcement.isCompleted) {
        announcement.complete(
          _ReadyAnnouncement(
            line.substring(QwenRuntimeSessionProtocol.readyPrefix.length),
          ),
        );
      }
      return;
    }
    _record(line);
  }

  void _record(String line) {
    if (_isUnknownSessionFlagError(line)) {
      rejectedSessionFlag = true;
    }
    final safe = QwenRuntimeLogRedactor.redact(line);
    if (_maxLogLines > 0) {
      if (logTail.length >= _maxLogLines) logTail.removeAt(0);
      logTail.add(safe);
    }
    try {
      _onLogLine?.call(safe);
    } catch (_) {
      // Progress observers must not interrupt pipe draining.
    }
  }

  /// clap reports an unpatched runtime as
  /// `error: unexpected argument '--lyricforge-session-stdin' found`.
  static bool _isUnknownSessionFlagError(String line) {
    if (!line.contains(QwenRuntimeSessionProtocol.sessionFlag)) return false;
    final lower = line.toLowerCase();
    return lower.contains('unexpected argument') ||
        lower.contains('unrecognized') ||
        lower.contains('found argument') ||
        lower.contains("wasn't expected");
  }

  Future<void> dispose(AsrProcessSupervisor supervisor) async {
    if (_disposed) return;
    _disposed = true;
    try {
      await process.stdin.close().timeout(const Duration(milliseconds: 500));
    } catch (_) {
      // Closing an already-broken pipe is fine; termination follows.
    }
    if (!exited) {
      await supervisor.terminate(process);
    }
    try {
      await _stdout.cancel();
    } catch (_) {
      // The pipe already reported an error; nothing left to release.
    }
    try {
      await _stderr.cancel();
    } catch (_) {
      // The pipe already reported an error; nothing left to release.
    }
  }
}
