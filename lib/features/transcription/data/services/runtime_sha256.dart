import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;

/// Verifies a file against an explicitly pinned SHA-256 value.
Future<bool> verifyFileSha256(File file, String expected) async {
  final normalizedExpected = expected.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedExpected)) {
    return false;
  }

  try {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == normalizedExpected;
  } catch (_) {
    return false;
  }
}
