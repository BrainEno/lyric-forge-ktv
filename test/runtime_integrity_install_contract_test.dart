import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed runtime install verifies release metadata before extraction', () async {
    final source = await File(
      'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
    ).readAsString();

    // The call may be wrapped across lines, so match the profile argument
    // instead of an exact single-line spelling.
    expect(
      source,
      matches(RegExp(r'_fetchRuntimeReleaseAssetMetadata\(\s*profile')),
    );
    expect(source, contains('metadata.downloadUri'));
    expect(source, contains('resumable: true'));
    expect(source, contains('actualSize != metadata.sizeBytes'));
    expect(source, contains('metadata.sha256'));
    expect(source, contains("await archive.delete();"));
    expect(source, contains('正在校验 LyricForge 识别引擎完整性'));

    final checksumIndex = source.indexOf('metadata.sha256');
    final extractionIndex = source.indexOf('await _extractZip(archive.path, bundle.path)');
    expect(checksumIndex, greaterThanOrEqualTo(0));
    expect(extractionIndex, greaterThan(checksumIndex));
  });
}
