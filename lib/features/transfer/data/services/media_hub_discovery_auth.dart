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
  return _hmac(
    key,
    'discover\n$deviceId\n$requestId',
  );
}

String mediaHubDiscoveryOfferProof({
  required String key,
  required String deviceId,
  required String requestId,
  required int port,
  required String token,
}) {
  return _hmac(
    key,
    'offer\n$deviceId\n$requestId\n$port\n$token',
  );
}

bool mediaHubDiscoveryProofMatches(String actual, String expected) {
  if (actual.length != expected.length) return false;
  var difference = 0;
  for (var index = 0; index < actual.length; index++) {
    difference |= actual.codeUnitAt(index) ^ expected.codeUnitAt(index);
  }
  return difference == 0;
}

String _hmac(String key, String message) {
  final mac = Hmac(sha256, utf8.encode(key));
  return mac.convert(utf8.encode(message)).toString();
}
