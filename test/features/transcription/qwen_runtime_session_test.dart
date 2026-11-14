import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/forced_alignment_http_client.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen_runtime_session.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

import 'fake_qwen_runtime.dart';

const _vectorSecret =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
const _vectorNonce = '00112233445566778899aabbccddeeff';
const _vectorRequestSignature =
    '9834b56ce5c8677230804790699dc42482fca1ca36159f5b83aa3f88c9c5bca2';
const _vectorReadyProof =
    '03b6c26cfcd564c51d9b567e0672666e7b168cfe5db5c99569b72df02ad1ef51';
const _vectorResponseProof =
    '6ee419e9ac5397eec9a2e86f55446f9906317bde57d51c83e65b1c0b11d050ec';

void main() {
  group('Qwen runtime session protocol', () {
    test(
      'Dart signatures match the vectors pinned in the Rust patch',
      () async {
        final secret = QwenRuntimeSessionSecret.fromHex(_vectorSecret);
        final request = secret.sign(
          QwenRuntimeSessionProtocol.requestMessage(
            method: 'POST',
            pathAndQuery: '/v1/transcribe',
            timestamp: '1700000000000',
            nonce: _vectorNonce,
            bodySha256: QwenRuntimeSessionProtocol.sha256Hex(
              utf8.encode('{"audio":"/tmp/a.wav"}'),
            ),
          ),
        );
        final ready = secret.sign(
          QwenRuntimeSessionProtocol.readyMessage(43210),
        );
        final response = secret.sign(
          QwenRuntimeSessionProtocol.responseMessage(
            nonce: _vectorNonce,
            statusCode: 200,
            bodySha256: QwenRuntimeSessionProtocol.sha256Hex(
              utf8.encode('{"ok":true}'),
            ),
          ),
        );

        expect(request, _vectorRequestSignature);
        expect(ready, _vectorReadyProof);
        expect(response, _vectorResponseProof);

        // Both implementations must be pinned to the same canonical strings.
        final patch = await File('tool/patches/qwen3-asr-session-auth.patch')
            .readAsString();
        expect(patch, contains(_vectorRequestSignature));
        expect(patch, contains(_vectorReadyProof));
        expect(patch, contains(_vectorResponseProof));
        expect(patch, contains(QwenRuntimeSessionProtocol.readyPrefix));
        expect(patch, contains(QwenRuntimeSessionProtocol.proofHeader));
        expect(patch, contains(QwenRuntimeSessionProtocol.signatureHeader));
      },
    );

    test('secrets are random, redacted and unusable once revoked', () {
      final first = QwenRuntimeSessionSecret.generate();
      final second = QwenRuntimeSessionSecret.generate();
      final firstLine = first.stdinLine;

      expect(firstLine, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(second.stdinLine, isNot(firstLine));
      expect(first.toString(), isNot(contains(firstLine)));
      expect(first.toString(), contains('<redacted>'));

      first.revoke();
      expect(first.isRevoked, isTrue);
      expect(() => first.sign('x'), throwsStateError);
      expect(() => first.stdinLine, throwsStateError);
    });

    test('log redaction hides key-length hex and bounds line length', () {
      final secret = QwenRuntimeSessionSecret.generate().stdinLine;
      final redacted = QwenRuntimeLogRedactor.redact('token=$secret tail');
      expect(redacted, isNot(contains(secret)));
      expect(redacted, contains('<redacted>'));
      expect(
        QwenRuntimeLogRedactor.redact('x' * 5000).length,
        QwenRuntimeLogRedactor.maxLineLength,
      );
    });

    test('every platform adapter lets the runtime bind port 0 itself', () {
      for (final os in ['windows', 'macos', 'linux']) {
        final policy = QwenRuntimePlatformPolicy.forOperatingSystem(os);
        expect(policy.listenerArguments(), [
          '--host',
          '127.0.0.1',
          '--port',
          '0',
          '--lyricforge-session-stdin',
        ]);
      }
      expect(
        QwenRuntimePlatformPolicy.forOperatingSystem('windows')
            .exclusiveBindMechanism,
        contains('SO_EXCLUSIVEADDRUSE'),
      );
    });
  });

  group('QwenRuntimeLauncher', () {
    late FakeQwenRuntime runtime;
    late List<ImpostorServer> impostors;

    setUp(() {
      impostors = <ImpostorServer>[];
    });

    tearDown(() async {
      await runtime.dispose();
      for (final impostor in impostors) {
        await impostor.close();
      }
    });

    QwenRuntimeLauncher launcher(
      FakeQwenRuntime fake, {
      Duration identityRetryDelay = const Duration(milliseconds: 20),
    }) {
      runtime = fake;
      return QwenRuntimeLauncher(
        startProcess: fake.start,
        supervisor: AsrProcessSupervisor(
          terminationGrace: const Duration(milliseconds: 20),
          streamDrainGrace: const Duration(milliseconds: 20),
        ),
        pollInterval: const Duration(milliseconds: 10),
        identityAttempts: 3,
        identityRetryDelay: identityRetryDelay,
        identityTimeout: const Duration(seconds: 1),
      );
    }

    Future<QwenRuntimeSession> start(
      QwenRuntimeLauncher launcher, {
      Duration startupTimeout = const Duration(seconds: 5),
      bool Function()? isCancelled,
    }) => launcher.start(
      executable: '/opt/runtime/qwen3-asr',
      serveArguments: QwenRuntimeSessionProtocol.serveArguments(
        const TranscriptionConfig(),
      ),
      startupTimeout: startupTimeout,
      isCancelled: isCancelled,
    );

    Matcher launchFailure(QwenRuntimeLaunchFailure failure) => throwsA(
      isA<QwenRuntimeLaunchException>().having(
        (error) => error.failure,
        'failure',
        failure,
      ),
    );

    test('starts an authenticated session on the runtime-owned port', () async {
      final fake = FakeQwenRuntime();
      final session = await start(launcher(fake));
      final process = fake.launches.single;

      expect(session.isAlive, isTrue);
      expect(session.port, process.boundPort);
      expect(process.secretLine, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(process.arguments, containsAllInOrder(['--port', '0']));
      expect(process.arguments, contains('--lyricforge-session-stdin'));
      expect(process.arguments.join(' '), isNot(contains(process.secretLine!)));
      expect(session.toString(), isNot(contains(process.secretLine!)));

      final health = process.requestsTo('/healthz').single;
      expect(health.authorized, isTrue);
      expect(health.headers['x-lyricforge-signature'], isNotNull);
      expect(
        health.headers.values.join(' '),
        isNot(contains(process.secretLine!)),
        reason: 'only an HMAC travels over HTTP, never the secret',
      );

      expect(await _identityOf(session), QwenRuntimeIdentity.verified);
      await session.close();
      expect(session.isAlive, isFalse);
      expect(process.stdinClosed, isTrue);
      expect(process.exited, isTrue);
      expect(
        () => session.authorize('GET', session.endpoint('/healthz'), const []),
        throwsA(isA<QwenRuntimeSessionClosedException>()),
      );
    });

    test('a hijacked port is rejected before any inference request', () async {
      final impostor = await ImpostorServer.start();
      impostors.add(impostor);
      final fake = FakeQwenRuntime(
        behaviorFor: (_) => FakeRuntimeBehavior(announcedPort: impostor.port),
      );

      await expectLater(
        start(launcher(fake)),
        launchFailure(QwenRuntimeLaunchFailure.identityRejected),
      );

      expect(impostor.requests.map((request) => request.path), ['/healthz']);
      expect(impostor.requests.single.body, isEmpty);
      final process = fake.launches.single;
      expect(process.exited, isTrue, reason: 'the runtime must be stopped');
      expect(process.stdinClosed || process.killSignals.isNotEmpty, isTrue);
    });

    test('an unproven port announcement is rejected and cleaned up', () async {
      final fake = FakeQwenRuntime(
        behaviorFor: (_) => FakeRuntimeBehavior(forgeReadyProof: true),
      );

      await expectLater(
        start(launcher(fake)),
        launchFailure(QwenRuntimeLaunchFailure.identityRejected),
      );
      final process = fake.launches.single;
      expect(process.requests, isEmpty);
      expect(process.exited, isTrue);
    });

    test('a /healthz answer without a valid proof is never trusted', () async {
      for (final mode in [FakeProofMode.missing, FakeProofMode.wrong]) {
        final fake = FakeQwenRuntime(
          behaviorFor: (_) => FakeRuntimeBehavior(healthProof: mode),
        );
        await expectLater(
          start(launcher(fake)),
          launchFailure(QwenRuntimeLaunchFailure.identityRejected),
        );
        expect(fake.launches.single.exited, isTrue);
        await fake.dispose();
      }
    });

    test('an unpatched runtime fails closed as unsupported', () async {
      final fake = FakeQwenRuntime(
        behaviorFor: (_) => FakeRuntimeBehavior(
          exitBeforeReadyCode: 2,
          stderrBeforeExit: [
            "error: unexpected argument '--lyricforge-session-stdin' found",
          ],
        ),
      );

      await expectLater(
        start(launcher(fake)),
        launchFailure(QwenRuntimeLaunchFailure.unsupportedRuntime),
      );
    });

    test('startup exit diagnostics never contain the secret', () async {
      final fake = FakeQwenRuntime(
        behaviorFor: (_) => FakeRuntimeBehavior(
          echoSecretToStderr: true,
          exitBeforeReadyCode: 1,
          stderrBeforeExit: ['failed to load model'],
        ),
      );

      QwenRuntimeLaunchException? failure;
      try {
        await start(launcher(fake));
      } on QwenRuntimeLaunchException catch (error) {
        failure = error;
      }
      final secret = fake.launches.single.secretLine!;
      expect(failure?.failure, QwenRuntimeLaunchFailure.exitedDuringStartup);
      expect(failure!.details, contains('failed to load model'));
      expect(failure.details, isNot(contains(secret)));
      expect(failure.toString(), isNot(contains(secret)));
    });

    test('startup timeout and cancellation both stop the runtime', () async {
      final silent = FakeQwenRuntime(
        behaviorFor: (_) => FakeRuntimeBehavior(announce: false),
      );
      await expectLater(
        start(
          launcher(silent),
          startupTimeout: const Duration(milliseconds: 100),
        ),
        launchFailure(QwenRuntimeLaunchFailure.startupTimeout),
      );
      expect(silent.launches.single.exited, isTrue);
      await silent.dispose();

      var cancelled = false;
      final waiting = FakeQwenRuntime(
        behaviorFor: (_) => FakeRuntimeBehavior(announce: false),
      );
      final pending = start(launcher(waiting), isCancelled: () => cancelled);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancelled = true;
      await expectLater(
        pending,
        launchFailure(QwenRuntimeLaunchFailure.cancelled),
      );
      expect(waiting.launches.single.exited, isTrue);
    });

    test('a missing executable reports startFailed', () async {
      runtime = FakeQwenRuntime();
      final launcher = QwenRuntimeLauncher(
        startProcess: (executable, arguments, {workingDirectory}) =>
            throw const ProcessException('qwen3-asr', [], 'not found', 2),
      );
      await expectLater(
        start(launcher),
        launchFailure(QwenRuntimeLaunchFailure.startFailed),
      );
    });

    test('a crashed runtime revokes its secret immediately', () async {
      final fake = FakeQwenRuntime();
      final session = await start(launcher(fake));
      await fake.launches.single.crash();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(session.isAlive, isFalse);
      expect(await _identityOf(session), QwenRuntimeIdentity.rejected);
      expect(
        () => session.authorize('GET', session.endpoint('/healthz'), const []),
        throwsA(isA<QwenRuntimeSessionClosedException>()),
      );
      await session.close();
    });

    test(
      'a restarted runtime gets a fresh secret; old sessions stay dead',
      () async {
        final fake = FakeQwenRuntime();
        final testLauncher = launcher(fake);
        final first = await start(testLauncher);
        await first.close();
        final second = await start(testLauncher);

        expect(fake.launches, hasLength(2));
        expect(fake.launches[0].secretLine, isNot(fake.launches[1].secretLine));
        expect(second.generation, greaterThan(first.generation));
        expect(
          () => first.authorize('GET', second.endpoint('/healthz'), const []),
          throwsA(isA<QwenRuntimeSessionClosedException>()),
        );
        await second.close();
      },
    );

    test('sessions refuse to sign for any other endpoint', () async {
      final fake = FakeQwenRuntime();
      final session = await start(launcher(fake));
      for (final uri in [
        Uri.parse('http://127.0.0.1:${session.port + 1}/v1/transcribe'),
        Uri.parse('http://localhost:${session.port}/v1/transcribe'),
        Uri.parse('https://127.0.0.1:${session.port}/v1/transcribe'),
      ]) {
        expect(
          () => session.authorize('POST', uri, const []),
          throwsArgumentError,
        );
      }
      await session.close();
    });

    test('response verification binds nonce, status and body', () async {
      final fake = FakeQwenRuntime();
      final session = await start(launcher(fake));
      final authorization = session.authorize(
        'POST',
        session.endpoint('/v1/transcribe'),
        utf8.encode('{}'),
      );
      // A proof for another nonce, status or body must not verify.
      expect(
        session.verifyResponse(
          nonce: authorization.nonce,
          statusCode: 200,
          proof: null,
          body: const [],
        ),
        isFalse,
      );
      expect(
        session.verifyResponse(
          nonce: authorization.nonce,
          statusCode: 200,
          proof: 'f' * 64,
          body: utf8.encode('{}'),
        ),
        isFalse,
      );
      await session.close();
    });

    test(
      'forced alignment requests are signed and responses verified',
      () async {
        final fake = FakeQwenRuntime();
        final session = await start(launcher(fake));
        final client = ForcedAlignmentHttpClient(
          endpoint: session.endpoint('/v1/align'),
          authenticator: session,
        );
        final spans = await client.align(
          audioPath: '/tmp/alignment.wav',
          text: 'hello world',
          language: 'English',
          audioDuration: const Duration(seconds: 2),
        );
        client.close(force: true);
        expect(spans.map((span) => span.text), ['hello', 'world']);
        final align = fake.launches.single.requestsTo('/v1/align').single;
        expect(align.authorized, isTrue);

        fake.launches.single.behavior.responseProof = FakeProofMode.missing;
        final unsigned = ForcedAlignmentHttpClient(
          endpoint: session.endpoint('/v1/align'),
          authenticator: session,
        );
        await expectLater(
          unsigned.align(
            audioPath: '/tmp/alignment.wav',
            text: 'hello world',
            language: 'English',
            audioDuration: const Duration(seconds: 2),
          ),
          throwsA(isA<ForcedAlignmentAuthenticationException>()),
        );
        unsigned.close(force: true);
        await session.close();
      },
    );

    test(
      'an unauthenticated alignment client is rejected by the runtime',
      () async {
        final fake = FakeQwenRuntime();
        final session = await start(launcher(fake));
        final client = ForcedAlignmentHttpClient(
          endpoint: session.endpoint('/v1/align'),
        );
        await expectLater(
          client.align(
            audioPath: '/etc/hosts',
            text: 'steal',
            language: 'English',
            audioDuration: const Duration(seconds: 2),
          ),
          throwsA(isA<ForcedAlignmentException>()),
        );
        client.close(force: true);
        final align = fake.launches.single.requestsTo('/v1/align').single;
        expect(align.authorized, isFalse);
        await session.close();
      },
    );
  });
}

Future<QwenRuntimeIdentity> _identityOf(QwenRuntimeSession session) async {
  final client = HttpClient();
  try {
    return await session.checkIdentity(client);
  } finally {
    client.close(force: true);
  }
}
