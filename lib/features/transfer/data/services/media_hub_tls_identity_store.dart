import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent self-signed TLS identity for a desktop Media Hub.
///
/// The certificate is a pinned identity, not a public-CA identity. Clients
/// accept it only when its SHA-256 DER fingerprint matches the value delivered
/// through the out-of-band pairing URI or authenticated device discovery.
class MediaHubTlsIdentity {
  final String certificatePem;
  final String privateKeyPem;
  final String fingerprint;

  const MediaHubTlsIdentity({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  SecurityContext createServerContext() => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
}

/// Loads one stable per-installation certificate/key pair, generating it on
/// first use. Tests may inject a temporary [rootDirectory].
class MediaHubTlsIdentityStore {
  final Directory? rootDirectory;

  Future<MediaHubTlsIdentity>? _pending;

  MediaHubTlsIdentityStore({this.rootDirectory});

  Future<MediaHubTlsIdentity> loadOrCreate() {
    return _pending ??= _loadOrCreate();
  }

  Future<MediaHubTlsIdentity> _loadOrCreate() async {
    final root = await _resolveRootDirectory();
    await root.create(recursive: true);
    final certificateFile = File(
      '${root.path}${Platform.pathSeparator}media-hub-certificate.pem',
    );
    final privateKeyFile = File(
      '${root.path}${Platform.pathSeparator}media-hub-private-key.pem',
    );

    if (await certificateFile.exists() && await privateKeyFile.exists()) {
      try {
        final certificatePem = await certificateFile.readAsString();
        final privateKeyPem = await privateKeyFile.readAsString();
        return _identity(certificatePem, privateKeyPem);
      } catch (_) {
        // A partial or unreadable identity is regenerated together, never
        // mixing a certificate from one keypair with a key from another.
      }
    }

    final identity = await _generateValidIdentity();
    final certificateTemporary = File('${certificateFile.path}.tmp');
    final keyTemporary = File('${privateKeyFile.path}.tmp');
    await certificateTemporary.writeAsString(identity.certificatePem, flush: true);
    await keyTemporary.writeAsString(identity.privateKeyPem, flush: true);

    // Do not leave a mismatched pair if either rename fails. The next startup
    // detects the incomplete pair and regenerates it.
    if (await certificateFile.exists()) await certificateFile.delete();
    if (await privateKeyFile.exists()) await privateKeyFile.delete();
    await certificateTemporary.rename(certificateFile.path);
    try {
      await keyTemporary.rename(privateKeyFile.path);
    } catch (_) {
      if (await certificateFile.exists()) await certificateFile.delete();
      if (await keyTemporary.exists()) await keyTemporary.delete();
      rethrow;
    }

    return identity;
  }

  Future<MediaHubTlsIdentity> _generateValidIdentity() async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
        final privateKey = pair.privateKey as RSAPrivateKey;
        final publicKey = pair.publicKey as RSAPublicKey;
        const distinguishedName = <String, String>{
          'CN': 'lyricforge.local',
          'O': 'LyricForge',
        };
        const sans = <String>['lyricforge.local'];
        final csr = X509Utils.generateRsaCsrPem(
          distinguishedName,
          privateKey,
          publicKey,
          san: sans,
        );
        final certificatePem = X509Utils.generateSelfSignedCertificate(
          privateKey,
          csr,
          3650,
          sans: sans,
          extKeyUsage: <ExtendedKeyUsage>[ExtendedKeyUsage.SERVER_AUTH],
        );
        final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);

        // Validate the certificate and private key before replacing any
        // persisted identity. A failed attempt must never leave bad PEM on disk.
        return _identity(certificatePem, privateKeyPem);
      } catch (error) {
        lastError = error;
        // Yield so the native TLS stack can release per-call state before a new
        // keypair/certificate is generated on the next attempt.
        await Future<void>.delayed(Duration.zero);
      }
    }

    throw StateError(
      'Unable to generate a valid Media Hub TLS identity after 3 attempts: '
      '$lastError',
    );
  }

  Future<Directory> _resolveRootDirectory() async {
    final injected = rootDirectory;
    if (injected != null) return injected;

    try {
      final support = await getApplicationSupportDirectory();
      return Directory(
        '${support.path}${Platform.pathSeparator}LyricForge'
        '${Platform.pathSeparator}MediaHub'
        '${Platform.pathSeparator}tls',
      );
    } catch (_) {
      // Flutter tests without a path_provider plugin use an isolated temporary
      // identity; production builds resolve to application support storage.
      return _fallbackTestDirectory ??= await Directory.systemTemp.createTemp(
        'lyricforge-media-hub-tls-',
      );
    }
  }

  static Directory? _fallbackTestDirectory;

  MediaHubTlsIdentity _identity(String certificatePem, String privateKeyPem) {
    const begin = '-----BEGIN CERTIFICATE-----';
    const end = '-----END CERTIFICATE-----';
    final start = certificatePem.indexOf(begin);
    final finish = certificatePem.indexOf(end);
    if (start < 0 || finish <= start) {
      throw const FormatException('Media Hub TLS certificate PEM is invalid');
    }
    final encoded = certificatePem
        .substring(start + begin.length, finish)
        .replaceAll(RegExp(r'\s+'), '');
    final der = base64.decode(encoded);
    final fingerprint = sha256.convert(der).toString();

    // Validate that the certificate and private key can be loaded by the TLS
    // stack before publishing their fingerprint to clients.
    SecurityContext()
      ..useCertificateChainBytes(utf8.encode(certificatePem))
      ..usePrivateKeyBytes(utf8.encode(privateKeyPem));

    return MediaHubTlsIdentity(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      fingerprint: fingerprint,
    );
  }
}

/// Returns the lowercase SHA-256 digest used to pin an X.509 certificate.
String mediaHubTlsFingerprint(List<int> certificateDer) =>
    sha256.convert(certificateDer).toString();
