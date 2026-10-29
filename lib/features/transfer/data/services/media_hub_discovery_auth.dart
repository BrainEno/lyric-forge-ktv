import 'dart:convert';

// crypto is already present in the app's resolved dependency graph. Keep the
// discovery implementation dependency-local until the next dependency refresh.
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';

String mediaHubDiscoveryRequestProof({
  required String key,
  required String deviceId,
  required String requestId,
}) {
  return _hmac(key, 'discover\n$deviceId\n$requestId');
}

String mediaHubDiscoveryOfferProof({
  required String key,
  required String deviceId,
  required String requestId,
  required int port,
  required String token,
  required String tlsFingerprint,
}) {
  return _hmac(
    key,
    'offer\n$deviceId\n$requestId\n$port\n$token\n$tlsFingerprint',
  );
}

bool mediaHubConstantTimeEquals(String actual, String expected) {
  var difference = actual.length ^ expected.length;
  final length = actual.length > expected.length
      ? actual.length
      : expected.length;
  for (var index = 0; index < length; index++) {
    final actualCodeUnit = index < actual.length ? actual.codeUnitAt(index) : 0;
    final expectedCodeUnit = index < expected.length
        ? expected.codeUnitAt(index)
        : 0;
    difference |= actualCodeUnit ^ expectedCodeUnit;
  }
  return difference == 0;
}

bool mediaHubDiscoveryProofMatches(String actual, String expected) =>
    mediaHubConstantTimeEquals(actual, expected);

String _hmac(String key, String message) {
  final mac = Hmac(sha256, utf8.encode(key));
  return mac.convert(utf8.encode(message)).toString();
}
