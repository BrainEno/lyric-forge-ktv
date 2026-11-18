import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The resume rules themselves are exercised against a real server in
  // resumable_file_download_test.dart; these checks keep every installer on
  // that one implementation.
  const installers = <String>[
    'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
    'lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart',
    'lib/features/transcription/data/services/resilient_asr_runtime_manager.dart',
  ];

  test('every installer downloads through ResumableFileDownload', () async {
    for (final path in installers) {
      final source = await File(path).readAsString();
      expect(source, contains('_downloader.fetch('), reason: path);
      expect(source, contains('cancellation: _transfer'), reason: path);
      expect(source, contains('on ResumableDownloadException'), reason: path);
      // No installer keeps a hand-rolled range request of its own.
      expect(source, isNot(contains('HttpHeaders.rangeHeader')), reason: path);
      expect(source, isNot(contains('_cancelRequested')), reason: path);
    }
  });

  test('runtime and whisper downloads opt into resumable part files', () async {
    final source = await File(installers.first).readAsString();

    expect(
      RegExp(r'resumable:\s*true').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(source, contains('ResumableFileDownload.partFileFor(target)'));
    expect(source, contains('resume: resumable'));
    expect(
      source,
      contains('await ResumableFileDownload.promote(part, target)'),
    );
  });

  test(
    'Whisper model download times out and preserves resumable failures',
    () async {
      final source = await File(installers.first).readAsString();
      final downloader = await File(
        'lib/features/transcription/data/services/resumable_file_download.dart',
      ).readAsString();

      expect(downloader, contains('response.timeout(timeout)'));
      expect(downloader, contains('request.close().timeout(timeout)'));
      expect(downloader, contains('clientFactory.create('));
      expect(source, contains('timeout: _downloadTimeout'));
      final clientFactory = await File(
        'lib/features/transcription/data/services/asr_download_http_client_factory.dart',
      ).readAsString();
      expect(
        clientFactory,
        contains('..connectionTimeout = const Duration(seconds: 30)'),
      );
      expect(
        source,
        contains("AsrRuntimeComponent.whisperModel => 'Whisper large-v3'"),
      );
      expect(source, contains(r"'下载 $label 失败，已保留断点文件'"));
      expect(source, contains('下载未完成，已保留断点并将自动续传'));
      expect(
        source,
        contains('component == AsrRuntimeComponent.qwenRuntime && resumable'),
      );
    },
  );

  test(
    'macOS custom storage persists and restores security-scoped bookmarks',
    () async {
      final storage = await File(
        'lib/features/transcription/data/services/local_asr_managed_storage_service.dart',
      ).readAsString();
      final swift = await File(
        'macos/Runner/MainFlutterWindow.swift',
      ).readAsString();
      final release = await File(
        'macos/Runner/Release.entitlements',
      ).readAsString();

      expect(storage, contains("'schemaVersion': 2"));
      expect(storage, contains("'securityScopedBookmark'"));
      expect(storage, contains('restoreAndStartBookmark'));
      expect(swift, contains('.withSecurityScope'));
      expect(swift, contains('startAccessingSecurityScopedResource'));
      expect(release, contains('com.apple.security.files.bookmarks.app-scope'));
    },
  );
}
