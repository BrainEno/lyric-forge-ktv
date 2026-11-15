import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class QwenRuntimeSessionAuth {
  static const requestHeader = 'x-lyricforge-session-auth';
  static const responseProofHeader = 'x-lyricforge-session-proof';

  final Uint8List _secret;
  final Random _random = Random.secure();
  bool _revoked = false;

  QwenRuntimeSessionAuth._(this._secret);

  factory QwenRuntimeSessionAuth.generate() {
    final random = Random.secure();
    final secret = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256), growable: false),
    );
    return QwenRuntimeSessionAuth._(secret);
  }

  String get bootstrapPayload {
    _ensureActive();
    return base64Url.encode(_secret).replaceAll('=', '');
  }

  QwenRuntimeRequestProof signRequest({
    required String method,
    required Uri uri,
    required List<int> body,
  }) {
    _ensureActive();
    final nonce = _randomHex(16);
    final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final bodyHash = sha256.convert(body);
    final canonical =
        'lyricforge-qwen-request-v1\n'
        '${method.toUpperCase()}\n'
        '$path\n'
        '${bodyHash.toString()}\n'
        '$nonce';
    final mac = Hmac(sha256, _secret).convert(utf8.encode(canonical));
    return QwenRuntimeRequestProof(
      nonce: nonce,
      headerValue: '$nonce:${mac.toString()}',
    );
  }

  bool verifyResponse({
    required String nonce,
    required int statusCode,
    required List<int> body,
    required String? proof,
  }) {
    if (_revoked || proof == null) return false;
    final bodyHash = sha256.convert(body);
    final canonical =
        'lyricforge-qwen-response-v1\n$nonce\n$statusCode\n$bodyHash';
    return _verifyCanonical(canonical, proof);
  }

  /// Creates a per-request verifier for SSE events or WebSocket frames.
  ///
  /// Each authenticated stream begins at sequence zero. The verifier rejects
  /// missing, reordered, repeated, or invalidly signed messages and becomes
  /// unusable after its first failure.
  QwenRuntimeStreamProofVerifier createStreamVerifier(String nonce) {
    _ensureActive();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce)) {
      throw ArgumentError.value(
        nonce,
        'nonce',
        'Must be 16-byte lowercase hex.',
      );
    }
    return QwenRuntimeStreamProofVerifier._(this, nonce);
  }

  bool _verifyCanonical(String canonical, String proof) {
    if (_revoked) return false;
    final expected = Hmac(
      sha256,
      _secret,
    ).convert(utf8.encode(canonical)).toString();
    return _constantTimeEquals(expected, proof);
  }

  void revoke() {
    if (_revoked) return;
    _secret.fillRange(0, _secret.length, 0);
    _revoked = true;
  }

  void _ensureActive() {
    if (_revoked) {
      throw StateError('Qwen runtime session credential has been revoked.');
    }
  }

  String _randomHex(int byteCount) {
    final bytes = List<int>.generate(
      byteCount,
      (_) => _random.nextInt(256),
      growable: false,
    );
    return _hex(bytes);
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static bool _constantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    if (leftBytes.length != rightBytes.length) return false;
    var difference = 0;
    for (var i = 0; i < leftBytes.length; i++) {
      difference |= leftBytes[i] ^ rightBytes[i];
    }
    return difference == 0;
  }
}

class QwenRuntimeStreamProofVerifier {
  final QwenRuntimeSessionAuth _auth;
  final String _nonce;
  int _nextSequence = 0;
  bool _failed = false;

  QwenRuntimeStreamProofVerifier._(this._auth, this._nonce);

  /// Verifies one SSE data event using the proof comment's payload.
  ///
  /// [proofComment] is the comment text without the leading colon, optionally
  /// with one leading space, for example
  /// `lyricforge-qwen-stream-proof-v1 <nonce> 0 <hmac>`.
  bool verifySseEvent({
    required String data,
    required String proofComment,
  }) {
    if (_failed || _auth._revoked) return false;
    var comment = proofComment.trim();
    if (comment.startsWith(':')) {
      comment = comment.substring(1).trimLeft();
    }
    final fields = comment.split(RegExp(r'\s+'));
    if (fields.length != 4 ||
        fields[0] != 'lyricforge-qwen-stream-proof-v1' ||
        fields[1] != _nonce) {
      _failed = true;
      return false;
    }
    final sequence = int.tryParse(fields[2]);
    if (sequence == null || fields[2] != sequence.toString()) {
      _failed = true;
      return false;
    }
    final dataHash = sha256.convert(utf8.encode(data));
    final canonical =
        'lyricforge-qwen-stream-v1\n$_nonce\n$sequence\n$dataHash';
    return _verifyNext(sequence, canonical, fields[3]);
  }

  /// Verifies a JSON WebSocket frame carrying `session_sequence` and
  /// `session_proof` fields.
  ///
  /// JSON object keys are sorted recursively before hashing, matching the
  /// Qwen runtime's compact `serde_json` representation.
  bool verifyWebSocketFrame(String frameText) {
    if (_failed || _auth._revoked) return false;
    dynamic decoded;
    try {
      decoded = jsonDecode(frameText);
    } on FormatException {
      _failed = true;
      return false;
    }
    if (decoded is! Map<String, dynamic>) {
      _failed = true;
      return false;
    }
    final sequence = decoded['session_sequence'];
    final proof = decoded['session_proof'];
    if (sequence is! int || proof is! String) {
      _failed = true;
      return false;
    }
    final signedFrame = Map<String, dynamic>.from(decoded)
      ..remove('session_proof');
    final canonicalJson = jsonEncode(_canonicalJsonValue(signedFrame));
    final dataHash = sha256.convert(utf8.encode(canonicalJson));
    final canonical =
        'lyricforge-qwen-ws-response-v1\n$_nonce\n$sequence\n$dataHash';
    return _verifyNext(sequence, canonical, proof);
  }

  bool _verifyNext(int sequence, String canonical, String proof) {
    if (sequence != _nextSequence ||
        !_auth._verifyCanonical(canonical, proof)) {
      _failed = true;
      return false;
    }
    _nextSequence++;
    return true;
  }
}

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJsonValue(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalJsonValue).toList(growable: false);
  }
  return value;
}

class QwenRuntimeRequestProof {
  final String nonce;
  final String headerValue;

  const QwenRuntimeRequestProof({
    required this.nonce,
    required this.headerValue,
  });
}
