import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge/features/transcription/data/services/runtime_release_asset_metadata.dart';

void main() {
  group('RuntimeReleaseAssetMetadata', () {
    const assetName = 'lyricforge-asr-runtime-windows-x64-cuda.zip';
    const sha =
        'aeaa33ec39db2642c0db55e061463727b09def1baee60a93c6c83a3480a5a085';

    test('parses GitHub release digest, size and download URL', () {
      final source = jsonEncode({
        'assets': [
          {
            'name': assetName,
            'browser_download_url':
                'https://github.com/BrainEno/lyric-forge-ktv/releases/download/'
                    'asr-runtime-v1/$assetName',
            'size': 1223385752,
            'digest': 'sha256:$sha',
          },
        ],
      });

      final metadata = RuntimeReleaseAssetMetadata.fromReleaseJson(
        source,
        assetName: assetName,
      );

      expect(metadata.name, assetName);
      expect(metadata.sizeBytes, 1223385752);
      expect(metadata.sha256, sha);
      expect(metadata.downloadUri.scheme, 'https');
    });

    test('rejects an asset without a trustworthy SHA-256 digest', () {
      final source = jsonEncode({
        'assets': [
          {
            'name': assetName,
            'browser_download_url': 'https://example.com/runtime.zip',
            'size': 123,
            'digest': null,
          },
        ],
      });

      expect(
        () => RuntimeReleaseAssetMetadata.fromReleaseJson(
          source,
          assetName: assetName,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a release that does not contain the requested platform asset', () {
      final source = jsonEncode({'assets': <Object>[]});

      expect(
        () => RuntimeReleaseAssetMetadata.fromReleaseJson(
          source,
          assetName: assetName,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
