import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed runtime resumes a retained part file with an HTTP byte range',
      () async {
    final source = await File(
      'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
    ).readAsString();

    final partFile = source.indexOf("final part = File(target.path + '.part');");
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
    expect(source, contains("final part = File(target.path + '.part');"));
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
