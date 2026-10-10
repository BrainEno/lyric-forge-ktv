import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart',
  ).readAsStringSync();

  test('fetches Hugging Face metadata before trusting an existing model file', () {
    final installStart = source.indexOf('Future<String> _installModel');
    final metadataIndex = source.indexOf(
      'final metadata = await _fetchModelFileMetadata',
      installStart,
    );
    final localCheckIndex = source.indexOf(
      'reusable = await _verifyLocalModelFile(target, metadata)',
      installStart,
    );

    expect(installStart, greaterThanOrEqualTo(0));
    expect(metadataIndex, greaterThan(installStart));
    expect(localCheckIndex, greaterThan(metadataIndex));
  });

  test('uses HEAD without redirects so linked ETag and size remain available', () {
    expect(source, contains('final request = await client.headUrl(uri);'));
    expect(source, contains('request.followRedirects = false;'));
    expect(source, contains("HttpHeaders.acceptEncodingHeader, 'identity'"));
  });

  test('validates resumed ranges and final size before accepting the part file', () {
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
    final rename = source.indexOf('await part.rename(target.path);', integrityCheck);

    expect(rangeCheck, greaterThan(downloadStart));
    expect(sizeCheck, greaterThan(rangeCheck));
    expect(integrityCheck, greaterThan(sizeCheck));
    expect(rename, greaterThan(integrityCheck));
  });

  test('keeps short partial files for resume but deletes corrupt full files', () {
    expect(source, contains('下载未完成，下次将从断点继续'));
    expect(source, contains('完整性校验失败，已删除损坏文件'));
    expect(source, contains('await part.delete();'));
  });

  test('managed model reuse requires the v2 integrity marker', () {
    expect(source, contains("'schemaVersion': 2"));
    expect(source, contains('requireIntegrityMarker: true'));
    expect(source, contains("decoded['schemaVersion'] != 2"));
    expect(source, contains('metadata.sizeBytes'));
  });
}
