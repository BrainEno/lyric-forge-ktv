import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the official ModelScope manifest and master download route', () {
    final manager = File(
      'lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart',
    ).readAsStringSync();

    expect(manager, contains(r"'/api/v1/models/$modelId/repo/files'"));
    expect(manager, contains("'Revision': 'master'"));
    expect(manager, contains("'Recursive': 'true'"));
    expect(manager, contains(r"'/models/$modelId/resolve/master/$fileName'"));
    expect(manager, contains('fromModelScopeManifest(jsonDecode(body))'));
    expect(
      manager,
      contains('_modelScopeManifestCache.clear()'),
    );
  });

  test('keeps source fallback guarded by size and known SHA-256', () {
    final manager = File(
      'lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart',
    ).readAsStringSync();
    final metadata = File(
      'lib/features/transcription/data/services/hugging_face_file_metadata.dart',
    ).readAsStringSync();

    expect(
      manager,
      contains('metadata.isContentCompatibleWith(fallbackMetadata)'),
    );
    expect(
      manager,
      contains('if (metadata.sha256 == null || fallbackMetadata.sha256 == null)'),
    );
    expect(metadata, contains('rawSha256.toLowerCase()'));
    expect(metadata, contains('AsrModelDownloadSource.modelScope'));
  });

  test(
    'preflight verifies both selected model repositories and source prerequisites',
    () {
      final checker = File(
        'lib/features/transcription/data/services/asr_download_connection_checker.dart',
      ).readAsStringSync();

      expect(checker, contains(r"name: '$qwenLabel (Hugging Face)'"));
      expect(checker, contains(r"name: '$alignerLabel (Hugging Face)'"));
      expect(checker, contains("reachable.contains('Whisper large-v3')"));
      expect(checker, contains('modelScopeManifestAvailable:'));
      expect(checker, contains('modelScopeFileAvailable:'));
      expect(checker, contains('modelScopeAlignerManifestAvailable:'));
      expect(checker, contains('modelScopeAlignerFileAvailable:'));
      expect(checker, contains('request.followRedirects = false'));
      expect(checker, contains('HuggingFaceFileMetadata.fromHeaders(headers)'));
      expect(checker, contains('report.requiredModelsAvailable'));
    },
  );
}
