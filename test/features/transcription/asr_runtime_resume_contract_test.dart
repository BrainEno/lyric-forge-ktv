import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed runtime resumes a retained part file with an HTTP byte range',
      () async {
    final source = await File(
      'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
    ).readAsString();

    final partFile = source.indexOf(
      r"final part = File('${target.path}.part');",
    );
    final partLength = source.indexOf('existing = await part.length();', partFile);
    final range = source.indexOf(
      "request.headers.set(HttpHeaders.rangeHeader, 'bytes=\$existing-');",
      partLength,
    );
    final partial = source.indexOf(
      'existing > 0 && response.statusCode == HttpStatus.partialContent',
      range,
    );
    final append = source.indexOf(
      'mode: append ? FileMode.append : FileMode.write',
      partial,
    );
    final promote = source.indexOf('await part.rename(target.path);', append);

    expect(partFile, greaterThanOrEqualTo(0));
    expect(partLength, greaterThan(partFile));
    expect(range, greaterThan(partLength));
    expect(partial, greaterThan(range));
    expect(append, greaterThan(partial));
    expect(promote, greaterThan(append));
  });

  test('runtime and whisper downloads opt into resumable part files', () async {
    final source = await File(
      'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
    ).readAsString();

    expect(
      RegExp(r'resumable:\s*true').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      source,
      contains(r"final part = File('${target.path}.part');"),
    );
  });

  test('Whisper model download times out and preserves resumable failures', () async {
    final source = await File(
      'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
    ).readAsString();
    final managedModels = await File(
      'lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart',
    ).readAsString();

    expect(source, contains('response.timeout(_downloadTimeout)'));
    expect(source, contains('request.close().timeout(_downloadTimeout)'));
    expect(source, contains('httpClientFactory.create('));
    final clientFactory = await File(
      'lib/features/transcription/data/services/asr_download_http_client_factory.dart',
    ).readAsString();
    expect(
      clientFactory,
      contains('..connectionTimeout = const Duration(seconds: 30)'),
    );
    expect(source, contains('下载 Whisper large-v3 失败，已保留断点文件'));
    expect(source, contains('下载未完成，已保留断点并将自动续传'));
    expect(source, contains('HttpHeaders.contentRangeHeader'));
    expect(
      source,
      contains('component == AsrRuntimeComponent.qwenRuntime && resumable'),
    );
    expect(managedModels, contains('response.timeout(_downloadTimeout)'));
    expect(managedModels, contains('httpClientFactory.create('));
    expect(
      RegExp(
        r'request.close\(\).timeout\(_downloadTimeout\)',
      ).allMatches(managedModels).length,
      greaterThanOrEqualTo(3),
    );
  });

  test('macOS custom storage persists and restores security-scoped bookmarks',
      () async {
    final storage = await File(
      'lib/features/transcription/data/services/local_asr_managed_storage_service.dart',
    ).readAsString();
    final swift = await File('macos/Runner/MainFlutterWindow.swift').readAsString();
    final release = await File('macos/Runner/Release.entitlements').readAsString();

    expect(storage, contains("'schemaVersion': 2"));
    expect(storage, contains("'securityScopedBookmark'"));
    expect(storage, contains('restoreAndStartBookmark'));
    expect(swift, contains('.withSecurityScope'));
    expect(swift, contains('startAccessingSecurityScopedResource'));
    expect(
      release,
      contains('com.apple.security.files.bookmarks.app-scope'),
    );
  });
}
