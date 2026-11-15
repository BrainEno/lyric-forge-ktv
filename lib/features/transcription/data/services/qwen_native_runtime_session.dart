import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const qwenRuntimeSessionTokenEnvironment = 'LYRICFORGE_QWEN_SESSION_TOKEN';
const qwenRuntimeReadyPrefix = 'LYRICFORGE_QWEN_READY';

/// In-memory identity material for one child runtime process.
///
/// The public certificate is received over the child's private stdout pipe and
/// pinned before any HTTP request (including Authorization or audio paths) is
/// sent. The credential is used only in HTTPS headers.
class QwenNativeRuntimeSession {
  QwenNativeRuntimeSession({
    required this.port,
    required List<int> certificateDer,
    required String token,
  }) : _certificateFingerprint = sha256.convert(certificateDer).bytes,
       _token = token {
    if (port <= 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Must be a bound TCP port.');
    }
    if (certificateDer.isEmpty || certificateDer.length > 8192) {
      throw ArgumentError.value(
        certificateDer.length,
        'certificateDer',
        'Must contain a bounded DER certificate.',
      );
    }
    if (!_isSessionToken(token)) {
      throw ArgumentError('Must be a 256-bit base64url token.');
    }
  }

  final int port;
  final List<int> _certificateFingerprint;
  final String _token;
  bool _identityRejected = false;

  bool get identityRejected => _identityRejected;

  Uri endpoint(String path) => Uri(
    scheme: 'https',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  );

  HttpClient createHttpClient({
    Duration connectionTimeout = const Duration(seconds: 10),
  }) {
    final client = HttpClient(
      context: SecurityContext(withTrustedRoots: false),
    )..connectionTimeout = connectionTimeout;
    client.findProxy = (_) => 'DIRECT';
    client.badCertificateCallback = (certificate, host, certificatePort) {
      final matches =
          host == InternetAddress.loopbackIPv4.address &&
          certificatePort == port &&
          _constantTimeBytesEqual(
            sha256.convert(certificate.der).bytes,
            _certificateFingerprint,
          );
      if (!matches) _identityRejected = true;
      return matches;
    };
    return client;
  }

  void authorize(HttpClientRequest request) {
    final uri = request.uri;
    if (uri.scheme != 'https' ||
        uri.host != InternetAddress.loopbackIPv4.address ||
        uri.port != port) {
      throw StateError(
        'Refusing to send Qwen session credentials off-session.',
      );
    }
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
  }

  String redact(String text) => text.replaceAll(_token, '[redacted]');

  static bool _isSessionToken(String value) => isQwenRuntimeSessionToken(value);

  static bool _constantTimeBytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

Uint8List decodeQwenRuntimeCertificate(String encodedCertificate) {
  if (encodedCertificate.length > 10924) {
    throw const FormatException('Invalid Qwen runtime certificate size.');
  }
  final bytes = base64Decode(encodedCertificate);
  if (bytes.isEmpty || bytes.length > 8192) {
    throw const FormatException('Invalid Qwen runtime certificate size.');
  }
  return Uint8List.fromList(bytes);
}

({int port, Uint8List certificateDer}) parseQwenRuntimeReadyRecord(
  String line,
) {
  if (line.length > 16384) {
    throw const FormatException('Qwen runtime readiness record is too large.');
  }
  final fields = line.split('\t');
  if (fields.length != 3 || fields[0] != qwenRuntimeReadyPrefix) {
    throw const FormatException('Invalid Qwen runtime readiness record.');
  }
  final port = int.tryParse(fields[1]);
  if (port == null || port <= 0 || port > 65535) {
    throw const FormatException('Invalid Qwen runtime listener port.');
  }
  return (
    port: port,
    certificateDer: decodeQwenRuntimeCertificate(fields[2]),
  );
}

bool isQwenRuntimeSessionToken(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) return false;
  try {
    return base64Url.decode(value).length == 32;
  } on FormatException {
    return false;
  }
}

String createQwenRuntimeSessionToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
