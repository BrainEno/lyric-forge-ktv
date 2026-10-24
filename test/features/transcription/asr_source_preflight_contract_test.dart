import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ModelScope probe validates the official manifest and target shard', () {
    final checker = File(
      'lib/features/transcription/data/services/asr_download_connection_checker.dart',
    ).readAsStringSync();

    expect(checker, contains('/api/v1/models/Qwen/Qwen3-ASR-1.7B/repo/files'));
    expect(checker, contains("'Revision': 'master'"));
    expect(checker, contains("'Recursive': 'true'"));
    expect(checker, contains('HuggingFaceFileMetadata.fromModelScopeManifest'));
    expect(checker, contains("files['model-00001-of-00002.safetensors']"));
    expect(checker, contains('requiredModelFile.sha256 == null'));
    expect(checker, contains("reachable.contains('Qwen3-ASR (ModelScope 文件清单)')"));
    expect(checker, contains('modelScopeManifestAvailable:'));
    expect(checker, contains('modelScopeFileAvailable:'));
  });

  test('download report is displayed instead of a generic success badge', () {
    final dialog = File(
      'lib/features/transcription/presentation/widgets/transcription_config_dialog.dart',
    ).readAsStringSync();

    expect(dialog, contains('final report = await _downloadConnectionChecker.testConnection('));
    expect(dialog, contains('_downloadConnectionMessage = report.summary;'));
  });
}
