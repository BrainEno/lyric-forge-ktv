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
