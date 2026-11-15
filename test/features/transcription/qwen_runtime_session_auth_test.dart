import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen_runtime_session_auth.dart';

String _hmac(List<int> key, String canonical) =>
    Hmac(sha256, key).convert(utf8.encode(canonical)).toString();

Object? _sortJsonKeys(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortJsonKeys(value[key]),
    };
  }
  if (value is List) {
    return value.map(_sortJsonKeys).toList(growable: false);
  }
  return value;
}

void main() {
  test('generates independent ephemeral secrets and request proofs', () {
    final first = QwenRuntimeSessionAuth.generate();
    final second = QwenRuntimeSessionAuth.generate();
    addTearDown(first.revoke);
    addTearDown(second.revoke);

    final firstSecret = first.bootstrapPayload;
    final secondSecret = second.bootstrapPayload;
    expect(firstSecret, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(secondSecret, isNot(firstSecret));

    final uri = Uri.parse('http://127.0.0.1:43127/v1/transcribe');
    final body = utf8.encode('{"audio":"/private/song.wav"}');
    final proof = first.signRequest(method: 'POST', uri: uri, body: body);
    final repeat = first.signRequest(method: 'POST', uri: uri, body: body);
    final altered = first.signRequest(
      method: 'POST',
      uri: uri,
      body: utf8.encode('{"audio":"/private/other.wav"}'),
    );

    expect(proof.nonce, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(proof.headerValue, startsWith('${proof.nonce}:'));
    expect(proof.headerValue, isNot(contains(firstSecret)));
    expect(proof.headerValue, isNot(contains('/private/song.wav')));
    expect(repeat.nonce, isNot(proof.nonce));
    expect(repeat.headerValue, isNot(proof.headerValue));
    expect(altered.headerValue, isNot(proof.headerValue));
  });

  test('verifies ordered SSE event proofs and fails closed on tampering', () {
    final auth = QwenRuntimeSessionAuth.generate();
    addTearDown(auth.revoke);
    final request = auth.signRequest(
      method: 'POST',
      uri: Uri.parse('http://127.0.0.1:43127/v1/chat/completions'),
      body: const <int>[],
    );
    final secret = base64Url.decode(base64Url.normalize(auth.bootstrapPayload));
    final verifier = auth.createStreamVerifier(request.nonce);

    String commentFor(int sequence, String data) {
      final dataHash = sha256.convert(utf8.encode(data));
      final proof = _hmac(
        secret,
        'lyricforge-qwen-stream-v1\n${request.nonce}\n$sequence\n$dataHash',
      );
      return 'lyricforge-qwen-stream-proof-v1 '
          '${request.nonce} $sequence $proof';
    }

    expect(
      verifier.verifySseEvent(
        data: '{"text":"hello"}',
        proofComment: commentFor(0, '{"text":"hello"}'),
      ),
      isTrue,
    );
    expect(
      verifier.verifySseEvent(
        data: '[DONE]',
        proofComment: commentFor(1, '[DONE]'),
      ),
      isTrue,
    );
    expect(
      verifier.verifySseEvent(
        data: '[DONE]',
        proofComment: commentFor(1, '[DONE]'),
      ),
      isFalse,
    );

    final alteredVerifier = auth.createStreamVerifier(request.nonce);
    expect(
      alteredVerifier.verifySseEvent(
        data: '{"text":"tampered"}',
        proofComment: commentFor(0, '{"text":"original"}'),
      ),
      isFalse,
    );
    expect(
      alteredVerifier.verifySseEvent(
        data: '{"text":"original"}',
        proofComment: commentFor(0, '{"text":"original"}'),
      ),
      isFalse,
    );

    final reorderedVerifier = auth.createStreamVerifier(request.nonce);
    expect(
      reorderedVerifier.verifySseEvent(
        data: '[DONE]',
        proofComment: commentFor(1, '[DONE]'),
      ),
      isFalse,
    );

    final wrongNonceVerifier = auth.createStreamVerifier(request.nonce);
    final wrongNonce = request.nonce.startsWith('0')
        ? '1${request.nonce.substring(1)}'
        : '0${request.nonce.substring(1)}';
    final wrongNonceComment = commentFor(0, '[DONE]').replaceFirst(
      request.nonce,
      wrongNonce,
    );
    expect(
      wrongNonceVerifier.verifySseEvent(
        data: '[DONE]',
        proofComment: wrongNonceComment,
      ),
      isFalse,
    );
  });

  test('verifies ordered WebSocket frame proofs over canonical JSON', () {
    final auth = QwenRuntimeSessionAuth.generate();
    addTearDown(auth.revoke);
    final request = auth.signRequest(
      method: 'GET',
      uri: Uri.parse('http://127.0.0.1:43127/v1/ws/stream'),
      body: const <int>[],
    );
    final secret = base64Url.decode(base64Url.normalize(auth.bootstrapPayload));
    final verifier = auth.createStreamVerifier(request.nonce);
    final unsignedFrame = <String, dynamic>{
      'type': 'partial',
      'content': <String, dynamic>{'text': '歌词', 'score': 0.125},
      'session_sequence': 0,
    };
    final canonicalJson = jsonEncode(_sortJsonKeys(unsignedFrame));
    final frameHash = sha256.convert(utf8.encode(canonicalJson));
    final frameProof = _hmac(
      secret,
      'lyricforge-qwen-ws-response-v1\n'
      '${request.nonce}\n0\n$frameHash',
    );
    final frame = <String, dynamic>{
      'session_proof': frameProof,
      ...unsignedFrame,
    };

    expect(verifier.verifyWebSocketFrame(jsonEncode(frame)), isTrue);
    expect(verifier.verifyWebSocketFrame(jsonEncode(frame)), isFalse);

    final tamperedVerifier = auth.createStreamVerifier(request.nonce);
    final tamperedFrame = <String, dynamic>{
      ...frame,
      'content': <String, dynamic>{'text': '篡改', 'score': 0.125},
    };
    expect(
      tamperedVerifier.verifyWebSocketFrame(jsonEncode(tamperedFrame)),
      isFalse,
    );

    final otherNonce = request.nonce.startsWith('0')
        ? '1${request.nonce.substring(1)}'
        : '0${request.nonce.substring(1)}';
    final wrongNonceVerifier = auth.createStreamVerifier(otherNonce);
    expect(wrongNonceVerifier.verifyWebSocketFrame(jsonEncode(frame)), isFalse);
  });

  test('authenticates response proof and revokes the session credential', () {
    final auth = QwenRuntimeSessionAuth.generate();
    final proof = auth.signRequest(
      method: 'GET',
      uri: Uri.parse('http://127.0.0.1:43127/healthz'),
      body: const <int>[],
    );
    final encodedSecret = base64Url.normalize(auth.bootstrapPayload);
    final secret = base64Url.decode(encodedSecret);
    final responseBody = utf8.encode('{"ok":true}');
    final bodyHash = sha256.convert(responseBody);
    final responseProof = Hmac(sha256, secret)
        .convert(
          utf8.encode(
            'lyricforge-qwen-response-v1\n${proof.nonce}\n200\n$bodyHash',
          ),
        )
        .toString();

    expect(
      auth.verifyResponse(
        nonce: proof.nonce,
        statusCode: 200,
        body: responseBody,
        proof: responseProof,
      ),
      isTrue,
    );
    expect(
      auth.verifyResponse(
        nonce: proof.nonce,
        statusCode: 503,
        body: responseBody,
        proof: responseProof,
      ),
      isFalse,
    );
    expect(
      auth.verifyResponse(
        nonce: proof.nonce,
        statusCode: 200,
        body: responseBody,
        proof: '$responseProof-guess',
      ),
      isFalse,
    );
    expect(
      auth.verifyResponse(
        nonce: proof.nonce,
        statusCode: 200,
        body: utf8.encode('{"ok":false}'),
        proof: responseProof,
      ),
      isFalse,
    );

    auth.revoke();
    expect(
      auth.verifyResponse(
        nonce: proof.nonce,
        statusCode: 200,
        body: responseBody,
        proof: responseProof,
      ),
      isFalse,
    );
    expect(() => auth.bootstrapPayload, throwsStateError);
    expect(
      () => auth.signRequest(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:43127/healthz'),
        body: const <int>[],
      ),
      throwsStateError,
    );
  });
}
