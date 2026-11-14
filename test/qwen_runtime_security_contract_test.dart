import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guards for the local Qwen runtime trust boundary (#415).
///
/// Behaviour is covered by the fake-runtime tests under
/// `test/features/transcription/`; these checks stop a later change from
/// quietly reintroducing a parent-side port reservation, an unauthenticated
/// `/healthz` probe or a second, unauthenticated way to launch `serve`.
void main() {
  const sessionFile =
      'lib/features/transcription/data/services/qwen_runtime_session.dart';
  const managerFile =
      'lib/features/transcription/data/services/managed_asr_runtime_manager.dart';
  const nativeFile =
      'lib/features/transcription/data/services/'
      'qwen3_asr_native_transcription_service.dart';
  const patchFile = 'tool/patches/qwen3-asr-session-auth.patch';

  Future<Map<String, String>> libSources() async {
    final sources = <String, String>{};
    await for (final entity in Directory('lib').list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final path = entity.path.replaceAll(r'\', '/');
        sources[path] = await entity.readAsString();
      }
    }
    return sources;
  }

  test('only the session launcher talks to /healthz or starts serve', () async {
    final sources = await libSources();
    expect(sources, contains(sessionFile));

    for (final MapEntry(key: path, value: source) in sources.entries) {
      if (path == sessionFile) continue;
      expect(
        RegExp(r"""['"]/healthz['"]""").hasMatch(source),
        isFalse,
        reason: '$path must not probe /healthz without a session proof',
      );
      expect(
        source.contains("'serve',"),
        isFalse,
        reason: '$path must launch Qwen serve through QwenRuntimeLauncher',
      );
    }
  });

  test('no transcription code reserves a port for the runtime', () async {
    final sources = await libSources();
    for (final MapEntry(key: path, value: source) in sources.entries) {
      if (!path.startsWith('lib/features/transcription/')) continue;
      expect(
        source.contains('ServerSocket.bind'),
        isFalse,
        reason: '$path: bind-close-rebind is a port hijack race',
      );
      expect(
        source.contains('_reservePort'),
        isFalse,
        reason: '$path: the runtime binds 127.0.0.1:0 itself',
      );
    }

    final session = sources[sessionFile]!;
    expect(session, matches(RegExp(r"'--port',\s*'0',")));
    expect(session, contains('QwenRuntimeSessionProtocol.sessionFlag'));
  });

  test(
    'the session secret is only handled inside the session module',
    () async {
      final sources = await libSources();
      for (final MapEntry(key: path, value: source) in sources.entries) {
        if (path == sessionFile) continue;
        expect(
          source.contains('stdinLine'),
          isFalse,
          reason: '$path must never read the raw session secret',
        );
        expect(
          source.contains('QwenRuntimeSessionSecret'),
          isFalse,
          reason: '$path must not hold or persist session secrets',
        );
      }

      final session = sources[sessionFile]!;
      expect(session, contains('Random.secure()'));
      expect(
        session,
        contains("String toString() => 'QwenRuntimeSessionSecret"),
      );
      expect(session, isNot(contains('print(')));
    },
  );

  test('both runtime clients sign requests and verify responses', () async {
    final native = await File(nativeFile).readAsString();
    final manager = await File(managerFile).readAsString();

    expect(native, contains('session.authorize('));
    expect(native, contains('authorization.acceptsResponse('));
    expect(native, contains('authenticator: session'));
    expect(native, contains('_requireVerifiedSession(session)'));

    final launch = manager.indexOf('_qwenRuntimeLauncher.start(');
    final marker = manager.indexOf(
      'final marker = _qwenReadyMarker(root, profile);',
    );
    expect(launch, greaterThan(0));
    expect(
      marker,
      greaterThan(launch),
      reason: 'the readiness marker is written only after a proven launch',
    );
    expect(manager, contains('await session?.close();'));
  });

  test('the runtime patch authenticates every route and drops CORS', () async {
    final patch = await File(patchFile).readAsString();

    expect(patch, contains('lyricforge_session_stdin: bool,'));
    expect(patch, contains('axum::middleware::from_fn_with_state('));
    expect(patch, contains('crate::session_auth::require_session_auth'));
    expect(patch, contains('+        app = app.layer(cors);'));
    expect(patch, contains('fn session_bind_address('));
    expect(patch, contains('if !ip.is_loopback()'));
    expect(patch, contains('SO_EXCLUSIVEADDRUSE'));
    expect(patch, contains('fn exit_when_stdin_closes()'));
    expect(patch, contains('fn constant_time_eq('));
    expect(patch, contains('"replayed nonce"'));
    expect(
      patch,
      contains('fn session_listener_cannot_be_rebound_by_another_socket()'),
    );
    expect(
      patch,
      contains(
        'fn previous_session_secret_cannot_access_a_restarted_runtime()',
      ),
    );
  });

  test('release builds apply and test the session-auth patch', () async {
    final workflow = await File(
      '.github/workflows/build-asr-runtime.yml',
    ).readAsString();

    expect(
      'tool/patches/qwen3-asr-session-auth.patch'.allMatches(workflow).length,
      greaterThanOrEqualTo(2),
      reason: 'Windows CUDA and macOS Intel bundles must both be patched',
    );
    expect(
      workflow,
      contains(
        'cargo test --release -p qwen3_asr_cli --features cuda '
        '--test session_auth_integration',
      ),
    );
    expect(
      workflow,
      contains(
        'cargo test --release -p qwen3_asr_cli '
        '--test session_auth_integration --features accelerate',
      ),
    );
  });
}
