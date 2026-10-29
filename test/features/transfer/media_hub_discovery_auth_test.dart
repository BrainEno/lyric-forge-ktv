import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/media_hub_discovery_auth.dart';

void main() {
  group('mediaHubConstantTimeEquals', () {
    test('accepts matching values', () {
      expect(mediaHubConstantTimeEquals('same-token', 'same-token'), isTrue);
      expect(mediaHubConstantTimeEquals('', ''), isTrue);
    });

    test('rejects same-length values that differ at each position', () {
      const expected = '0123456789abcdef';
      expect(mediaHubConstantTimeEquals('1123456789abcdef', expected), isFalse);
      expect(mediaHubConstantTimeEquals('0123456789abcdee', expected), isFalse);
      expect(mediaHubConstantTimeEquals('0123456799abcdef', expected), isFalse);
    });

    test('rejects values with different lengths without prefix matching', () {
      expect(mediaHubConstantTimeEquals('prefix', 'prefix-extra'), isFalse);
      expect(mediaHubConstantTimeEquals('prefix-extra', 'prefix'), isFalse);
      expect(mediaHubConstantTimeEquals('', 'token'), isFalse);
      expect(mediaHubConstantTimeEquals('token', ''), isFalse);
    });
  });

  test('discovery proof matching uses the same comparator', () {
    expect(mediaHubDiscoveryProofMatches('proof-value', 'proof-value'), isTrue);
    expect(
      mediaHubDiscoveryProofMatches('proof-value', 'proof-valuE'),
      isFalse,
    );
    expect(mediaHubDiscoveryProofMatches('short', 'shorter'), isFalse);
  });
}
