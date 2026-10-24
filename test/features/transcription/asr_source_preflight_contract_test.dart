import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preflight validates install-time metadata and required model assets', () {
    final checker = File(
      'lib/features/transcription/data/services/asr_download_connection_checker.dart',
    ).readAsStringSync();

    expect(checker, contains('request.followRedirects = false'));
    expect(checker, contains('HuggingFaceFileMetadata.fromHeaders(headers)'));
    expect(checker, contains('fromModelScopeManifest'));
    expect(checker, contains('requiredFile.sha256 == null'));
    expect(checker, contains('modelScopeAlignerManifestAvailable'));
    expect(checker, contains('modelScopeAlignerFileAvailable'));
    expect(checker, contains('report.alignerAvailable'));
    expect(checker, contains('report.requiredModelsAvailable'));
  });

  test('advanced settings passes the resolved model profile to preflight', () {
    final dialog = File(
      'lib/features/transcription/presentation/widgets/transcription_config_dialog.dart',
    ).readAsStringSync();

    expect(dialog, contains('qwenModelId: _qwenModelIdForConnectionProbe()'));
    expect(dialog, contains("return 'Qwen/Qwen3-ASR-0.6B';"));
    expect(dialog, contains("return 'Qwen/Qwen3-ASR-1.7B';"));
    expect(dialog, contains("alignerModelId: 'Qwen/Qwen3-ForcedAligner-0.6B'"));
    expect(dialog, contains('_downloadConnectionMessage = report.summary;'));
  });
}
