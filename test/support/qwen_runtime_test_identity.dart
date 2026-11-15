import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lyric_forge_ktv/features/transcription/data/services/qwen_native_runtime_session.dart';

/// Loads the self-signed loopback identity shared by authenticated HTTP tests.
class QwenRuntimeTestIdentity {
  QwenRuntimeTestIdentity._({
    required this.certificateDer,
    required this.certificatePath,
    required this.privateKeyPath,
  });

  final Uint8List certificateDer;
  final String certificatePath;
  final String privateKeyPath;

  static Future<QwenRuntimeTestIdentity> load() async {
    final fixtureDirectory = [
      Directory.current.path,
      'test',
      'fixtures',
      'qwen_runtime_test_identity',
    ].join(Platform.pathSeparator);
    final certificateFile = File(
      '$fixtureDirectory${Platform.pathSeparator}certificate.pem',
    );
    final privateKeyFile = File(
      '$fixtureDirectory${Platform.pathSeparator}private_key.pem',
    );
    final certificatePem = await certificateFile.readAsString();
    final match = RegExp(
      r'-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----',
    ).firstMatch(certificatePem);
    if (match == null) {
      throw const FormatException('Test identity certificate is not PEM.');
    }

    final certificateDer = Uint8List.fromList(
      base64.decode(match.group(1)!.replaceAll(RegExp(r'\s+'), '')),
    );
    return QwenRuntimeTestIdentity._(
      certificateDer: certificateDer,
      certificatePath: certificateFile.path,
      privateKeyPath: privateKeyFile.path,
    );
  }

  Future<HttpServer> bindServer() => HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    SecurityContext()
      ..useCertificateChain(certificatePath)
      ..usePrivateKey(privateKeyPath),
  );

  QwenNativeRuntimeSession session(int port) => QwenNativeRuntimeSession(
    port: port,
    certificateDer: certificateDer,
    token: base64Url.encode(List<int>.filled(32, 0x54)).replaceAll('=', ''),
  );
}
