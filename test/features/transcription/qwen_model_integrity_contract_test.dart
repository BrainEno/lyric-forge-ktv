import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart',
  ).readAsStringSync();

  test(
    'fetches Hugging Face metadata before trusting an existing model file',
    () {
      final installStart = source.indexOf('Future<String> _installModel');
      final metadataIndex = source.indexOf(
        'var metadata = await _fetchModelFileMetadata',
        installStart,
      );
      final localCheckIndex = source.indexOf(
        'reusable = await _verifyLocalModelFile(target, metadata)',
        installStart,
      );

      expect(installStart, greaterThanOrEqualTo(0));
      expect(metadataIndex, greaterThan(installStart));
      expect(localCheckIndex, greaterThan(metadataIndex));
    },
  );

  test(
    'uses HEAD without redirects so linked ETag and size remain available',
    () {
      expect(source, contains('final request = await client.headUrl(uri);'));
      expect(source, contains('request.followRedirects = false;'));
      expect(source, contains("HttpHeaders.acceptEncodingHeader, 'identity'"));
    },
  );

  test(
    'redacts signed redirect queries but reports host and HTTP response details',
    () {
      expect(source, contains('_downloadResponseDiagnostics(uri, response)'));
      expect(source, contains('_redactDownloadUri(redirect.location)'));
      expect(source, contains("response.headers.value('content-range')"));
      expect(source, contains('redirects='));
      expect(source, contains('response.reasonPhrase'));
    },
  );

  test(
    'validates resumed ranges and final size before accepting the part file',
    () {
      final downloadStart = source.indexOf('Future<void> _downloadModelFile');
      final rangeCheck = source.indexOf(
        r"contentRange.startsWith('bytes $existing-')",
        downloadStart,
      );
      final sizeCheck = source.indexOf(
        'final actualSize = await part.length();',
        downloadStart,
      );
      final integrityCheck = source.indexOf(
        '_verifyLocalModelFile(part, metadata)',
        sizeCheck,
      );
      final rename = source.indexOf(
        'await part.rename(target.path);',
        integrityCheck,
      );

      expect(rangeCheck, greaterThan(downloadStart));
      expect(sizeCheck, greaterThan(rangeCheck));
      expect(integrityCheck, greaterThan(sizeCheck));
      expect(rename, greaterThan(integrityCheck));
    },
  );

  test(
    'keeps short partial files for resume but deletes corrupt full files',
    () {
      expect(source, contains('下载未完成，下次将从断点继续'));
      expect(source, contains('完整性校验失败，已删除损坏文件'));
      expect(source, contains('await part.delete();'));
    },
  );

  test('managed model reuse requires the v2 integrity marker', () {
    expect(source, contains("'schemaVersion': 2"));
    expect(source, contains('requireIntegrityMarker: true'));
    expect(source, contains("decoded['schemaVersion'] != 2"));
    expect(source, contains('metadata.sizeBytes'));
  });

  test('managed model reuse verifies every SHA-256 stored in the marker', () {
    expect(source, contains('_verifyModelMarkerHashes'));
    expect(source, contains('final expectedSha256 = metadata.sha256'));
    expect(source, contains('await _verifySha256(file.path, expectedSha256)'));
    expect(source, contains('未通过 SHA-256 校验；将只重新下载不匹配的文件'));
    expect(source, contains('已校验并复用'));
  });

  test('Whisper reuse requires the pinned SHA-256 before skipping download', () {
    final whisperSource = File(
      'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
    ).readAsStringSync();

    expect(whisperSource, contains('verifyHash: true'));
    expect(
      whisperSource,
      contains('await _verifySha256(path, _whisperModelSha256)'),
    );
    expect(whisperSource, contains('正在校验已有 Whisper large-v3 的 SHA-256（不会下载）'));
    expect(whisperSource, contains('未通过大小或 SHA-256 校验，将重新下载该模型'));
  });

  test('awaits post-install repair before finally cleanup', () {
    expect(source, contains('return await repair(installed);'));
  });
}
