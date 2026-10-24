import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/hugging_face_file_metadata.dart';

void main() {
  group('HuggingFaceFileMetadata', () {
    const lfsSha =
        'd88b0d6a6ff9c3f8151f9d3228f57092aaea997f09af009eefd7373a77b5abb9';

    test('prefers linked LFS metadata and exposes SHA-256', () {
      final metadata = HuggingFaceFileMetadata.fromHeaders({
        'x-linked-etag': '"$lfsSha"',
        'x-linked-size': '497764107',
        'etag': '"fallback"',
        'content-length': '0',
      });

      expect(metadata.etag, lfsSha);
      expect(metadata.sizeBytes, 497764107);
      expect(metadata.sha256, lfsSha);
    });

    test('falls back to ordinary ETag and content length for Git files', () {
      const gitBlob = '43bd404b159de6fba7c2f4d3264347668d43af25';
      final metadata = HuggingFaceFileMetadata.fromHeaders({
        'etag': 'W/"$gitBlob"',
        'content-length': '391',
      });

      expect(metadata.etag, gitBlob);
      expect(metadata.sizeBytes, 391);
      expect(metadata.sha256, isNull);
    });

    test('parses ModelScope manifest size and SHA-256 for file blobs', () {
      const sha256 =
          'a4cd1f1a04d90b757dc7f7dd26254e69a013b19e80efe590a83c6a3bde8608d6';
      final manifest = HuggingFaceFileMetadata.fromModelScopeManifest({
        'Code': 200,
        'Success': true,
        'Message': 'success',
        'Data': {
          'Files': [
            {
              'Name': 'model.safetensors',
              'Path': 'model.safetensors',
              'Size': 1024,
              'Sha256': sha256,
              'Type': 'blob',
            },
            {
              'Name': 'subfolder',
              'Path': 'subfolder',
              'Size': 0,
              'Sha256': '',
              'Type': 'tree',
            },
          ],
        },
      });

      final model = manifest['model.safetensors']!;
      expect(model.source, AsrModelDownloadSource.modelScope);
      expect(model.sizeBytes, 1024);
      expect(model.sha256, sha256);
    });

    test('rejects ModelScope manifests without verifiable file checksums', () {
      expect(
        () => HuggingFaceFileMetadata.fromModelScopeManifest({
          'Success': true,
          'Data': {
            'Files': [
              {
                'Path': 'model.safetensors',
                'Size': 1024,
                'Sha256': 'missing-checksum',
                'Type': 'blob',
              },
            ],
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('ModelScope fallback requires matching size and known SHA-256', () {
      const shaA =
          'a4cd1f1a04d90b757dc7f7dd26254e69a013b19e80efe590a83c6a3bde8608d6';
      const shaB =
          '6e0b9d9e09e2e0238e7ef3cc8a484ab387e91b90f1900bedf88bc92d7929ccfc';
      const fromHuggingFace = HuggingFaceFileMetadata(
        etag: shaA,
        sizeBytes: 1024,
        sha256: shaA,
      );
      const matchingFallback = HuggingFaceFileMetadata(
        etag: shaA,
        sizeBytes: 1024,
        sha256: shaA,
        source: AsrModelDownloadSource.modelScope,
      );
      const changedChecksum = HuggingFaceFileMetadata(
        etag: shaB,
        sizeBytes: 1024,
        sha256: shaB,
        source: AsrModelDownloadSource.modelScope,
      );
      const changedSize = HuggingFaceFileMetadata(
        etag: shaA,
        sizeBytes: 1025,
        sha256: shaA,
        source: AsrModelDownloadSource.modelScope,
      );

      expect(fromHuggingFace.isContentCompatibleWith(matchingFallback), isTrue);
      expect(fromHuggingFace.isContentCompatibleWith(changedChecksum), isFalse);
      expect(fromHuggingFace.isContentCompatibleWith(changedSize), isFalse);
    });

    test('round-trips cached integrity metadata', () {
      final original = HuggingFaceFileMetadata.fromHeaders({
        'x-linked-etag': lfsSha,
        'x-linked-size': '123456',
      });

      final restored = HuggingFaceFileMetadata.fromJson(original.toJson());

      expect(restored.etag, original.etag);
      expect(restored.sizeBytes, original.sizeBytes);
      expect(restored.sha256, original.sha256);
    });

    test('rejects metadata without a trustworthy positive size', () {
      expect(
        () => HuggingFaceFileMetadata.fromHeaders({
          'etag': '"abc"',
          'content-length': '0',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects cached malformed SHA-256 metadata', () {
      expect(
        () => HuggingFaceFileMetadata.fromJson({
          'etag': 'abc',
          'sizeBytes': 42,
          'sha256': 'not-a-sha256',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
