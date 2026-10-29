import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/media_hub_tls_identity_store.dart';

void main() {
  test('TLS identity persists and its private key matches the certificate', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-tls-identity-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final first = await MediaHubTlsIdentityStore(rootDirectory: root).loadOrCreate();
    final reloaded =
        await MediaHubTlsIdentityStore(rootDirectory: root).loadOrCreate();

    expect(first.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(reloaded.fingerprint, first.fingerprint);
    expect(() => first.createServerContext(), returnsNormally);
    expect(
      await File('${root.path}${Platform.pathSeparator}media-hub-certificate.pem')
          .exists(),
      isTrue,
    );
    expect(
      await File('${root.path}${Platform.pathSeparator}media-hub-private-key.pem')
          .exists(),
      isTrue,
    );
  });

  test('incomplete persisted keypair is replaced rather than reused', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-tls-repair-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final firstStore = MediaHubTlsIdentityStore(rootDirectory: root);
    final first = await firstStore.loadOrCreate();
    final key = File('${root.path}${Platform.pathSeparator}media-hub-private-key.pem');
    await key.writeAsString('not a private key', flush: true);

    final repaired = await MediaHubTlsIdentityStore(rootDirectory: root).loadOrCreate();

    expect(repaired.fingerprint, isNot(first.fingerprint));
    expect(repaired.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(() => repaired.createServerContext(), returnsNormally);
  });
}
