import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/runtime_sha256.dart';

void main() {
  test('verifies the exact SHA-256 digest of a file', () async {
    final directory = await Directory.systemTemp.createTemp('runtime-sha256-');
    try {
      final file = File('${directory.path}/payload.bin');
      await file.writeAsString('abc');

      expect(
        await verifyFileSha256(
          file,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
        isTrue,
      );
      expect(
        await verifyFileSha256(file, List.filled(64, '0').join()),
        isFalse,
      );
      expect(await verifyFileSha256(file, 'not-a-digest'), isFalse);
      expect(
        await verifyFileSha256(
          File('${directory.path}/missing.bin'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
        isFalse,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
