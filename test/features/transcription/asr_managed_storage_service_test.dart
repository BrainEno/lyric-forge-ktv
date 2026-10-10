import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_asr_managed_storage_service.dart';

void main() {
  test('moves managed ASR tree to another parent and persists the root', () async {
    final sandbox = await Directory.systemTemp.createTemp('lyricforge-asr-root-');
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory('${sandbox.path}${Platform.pathSeparator}support');
    final destination = Directory('${sandbox.path}${Platform.pathSeparator}models-drive');
    await support.create(recursive: true);
    await destination.create(recursive: true);

    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
    );
    final source = await service.resolveRoot();
    final model = File(
      '${source.path}${Platform.pathSeparator}models${Platform.pathSeparator}qwen${Platform.pathSeparator}model.bin',
    );
    await model.parent.create(recursive: true);
    await model.writeAsBytes(List<int>.generate(1024, (index) => index % 251));
    final part = File(
      '${source.path}${Platform.pathSeparator}downloads${Platform.pathSeparator}runtime.zip.part',
    );
    await part.parent.create(recursive: true);
    await part.writeAsBytes(List<int>.filled(333, 7));

    final progress = <int>[];
    final result = await service.moveToParent(
      destination.path,
      onProgress: (copied, total) => progress.add(copied),
    );

    final expected = Directory(
      '${destination.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}ASRRuntime',
    ).absolute.path;
    expect(result.moved, isTrue);
    expect(result.targetRoot, expected);
    expect(result.copiedBytes, 1357);
    expect(result.copiedFiles, 2);
    expect(progress, isNotEmpty);
    expect(progress.last, 1357);
    expect(
      await File(
        '$expected${Platform.pathSeparator}models${Platform.pathSeparator}qwen${Platform.pathSeparator}model.bin',
      ).length(),
      1024,
    );
    expect(
      await File(
        '$expected${Platform.pathSeparator}downloads${Platform.pathSeparator}runtime.zip.part',
      ).length(),
      333,
    );
    expect((await service.resolveRoot()).path, expected);
    expect(await source.exists(), isFalse);
  });

  test('can migrate a custom root back to the default application-support root',
      () async {
    final sandbox = await Directory.systemTemp.createTemp('lyricforge-asr-default-');
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory('${sandbox.path}${Platform.pathSeparator}support');
    final destination = Directory('${sandbox.path}${Platform.pathSeparator}external');
    await support.create(recursive: true);
    await destination.create(recursive: true);

    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
    );
    final source = await service.resolveRoot();
    final file = File(
      '${source.path}${Platform.pathSeparator}bundle${Platform.pathSeparator}qwen3-asr',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('runtime');

    await service.moveToParent(destination.path);
    final custom = await service.inspect();
    expect(custom.isDefault, isFalse);

    final back = await service.moveToDefault();
    final current = await service.inspect();

    expect(back.moved, isTrue);
    expect(current.isDefault, isTrue);
    expect(
      await File(
        '${current.activeRoot}${Platform.pathSeparator}bundle${Platform.pathSeparator}qwen3-asr',
      ).readAsString(),
      'runtime',
    );
  });

  test('refuses to overwrite an existing LyricForge ASRRuntime tree', () async {
    final sandbox = await Directory.systemTemp.createTemp('lyricforge-asr-conflict-');
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory('${sandbox.path}${Platform.pathSeparator}support');
    final destination = Directory('${sandbox.path}${Platform.pathSeparator}destination');
    await support.create(recursive: true);
    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
    );
    final source = await service.resolveRoot();
    await File('${source.path}${Platform.pathSeparator}source.bin')
        .writeAsString('source');

    final conflicting = File(
      '${destination.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}ASRRuntime${Platform.pathSeparator}foreign.bin',
    );
    await conflicting.parent.create(recursive: true);
    await conflicting.writeAsString('do not overwrite');

    await expectLater(
      service.moveToParent(destination.path),
      throwsA(isA<FileSystemException>()),
    );

    expect((await service.resolveRoot()).path, source.path);
    expect(
      await File('${source.path}${Platform.pathSeparator}source.bin').exists(),
      isTrue,
    );
    expect(await conflicting.readAsString(), 'do not overwrite');
  });

  test('refuses a migration target nested inside the current ASR root',
      () async {
    final sandbox = await Directory.systemTemp.createTemp('lyricforge-asr-overlap-');
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory('${sandbox.path}${Platform.pathSeparator}support');
    await support.create(recursive: true);
    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
    );
    final source = await service.resolveRoot();
    final sourceFile = File('${source.path}${Platform.pathSeparator}keep.bin');
    await sourceFile.writeAsString('keep-me');

    final nestedParent = Directory(
      '${source.path}${Platform.pathSeparator}nested-destination',
    );
    await expectLater(
      service.moveToParent(nestedParent.path),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          contains('不能位于当前 ASRRuntime 目录内部'),
        ),
      ),
    );

    expect((await service.resolveRoot()).path, source.path);
    expect(await sourceFile.readAsString(), 'keep-me');
    expect(service.isMoving, isFalse);
  });

  test('persists and restores a macOS security-scoped storage bookmark',
      () async {
    final sandbox = await Directory.systemTemp.createTemp('lyricforge-asr-bookmark-');
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory('${sandbox.path}${Platform.pathSeparator}support');
    final destination = Directory('${sandbox.path}${Platform.pathSeparator}external');
    await support.create(recursive: true);
    await destination.create(recursive: true);

    final bridge = _FakeBookmarkBridge(
      createdBookmark: 'bookmark-v2',
    );
    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
      securityScopedBookmarkBridge: bridge,
      isMacOSResolver: () => true,
    );
    final source = await service.resolveRoot();
    await File('${source.path}${Platform.pathSeparator}keep.bin')
        .writeAsString('keep');

    await service.moveToParent(destination.path);
    final expected = Directory(
      '${destination.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}ASRRuntime',
    ).absolute.path;

    final configFile = File(
      '${support.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}asr-managed-storage.json',
    );
    final config = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(config['schemaVersion'], 2);
    expect(config['securityScopedBookmark'], 'bookmark-v2');
    expect(config['securityScopedParent'], destination.absolute.path);

    final restoreBridge = _FakeBookmarkBridge(
      createdBookmark: 'unused',
      restoredPath: destination.absolute.path,
      restoredBookmark: 'bookmark-v2',
    );
    final restoredService = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
      securityScopedBookmarkBridge: restoreBridge,
      isMacOSResolver: () => true,
    );
    expect((await restoredService.resolveRoot()).path, expected);
    expect(restoreBridge.restoredBookmarks, ['bookmark-v2']);
    expect(
      await File('$expected${Platform.pathSeparator}keep.bin').readAsString(),
      'keep',
    );
  });

  test('reauthorizes a legacy macOS root in place without losing part files',
      () async {
    final sandbox = await Directory.systemTemp.createTemp('lyricforge-asr-legacy-');
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory('${sandbox.path}${Platform.pathSeparator}support');
    final selectedParent = Directory('${sandbox.path}${Platform.pathSeparator}external');
    final legacyRoot = Directory(
      '${selectedParent.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}ASRRuntime',
    );
    await support.create(recursive: true);
    await legacyRoot.create(recursive: true);
    final part = File(
      '${legacyRoot.path}${Platform.pathSeparator}downloads${Platform.pathSeparator}asr-runtime.zip.part',
    );
    await part.parent.create(recursive: true);
    await part.writeAsBytes(List<int>.filled(333, 9));

    final configFile = File(
      '${support.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}asr-managed-storage.json',
    );
    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'managedRoot': legacyRoot.absolute.path,
    }));

    final bridge = _FakeBookmarkBridge(createdBookmark: 'legacy-upgraded');
    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
      securityScopedBookmarkBridge: bridge,
      isMacOSResolver: () => true,
    );

    expect(await service.needsSecurityScopedAuthorization(), isTrue);
    final result = await service.moveToParent(selectedParent.path);
    expect(result.moved, isFalse);
    expect(await part.length(), 333);
    expect(await service.needsSecurityScopedAuthorization(), isFalse);

    final config = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(config['schemaVersion'], 2);
    expect(config['securityScopedBookmark'], 'legacy-upgraded');
    expect(bridge.createdPaths, [selectedParent.absolute.path]);
  });
}

class _FakeBookmarkBridge implements AsrSecurityScopedBookmarkBridge {
  final String createdBookmark;
  final String? restoredPath;
  final String? restoredBookmark;
  final List<String> createdPaths = [];
  final List<String> restoredBookmarks = [];

  _FakeBookmarkBridge({
    required this.createdBookmark,
    this.restoredPath,
    this.restoredBookmark,
  });

  @override
  Future<AsrSecurityScopedBookmarkAccess> createAndStart(String path) async {
    final absolute = Directory(path).absolute.path;
    createdPaths.add(absolute);
    return AsrSecurityScopedBookmarkAccess(
      path: absolute,
      bookmark: createdBookmark,
    );
  }

  @override
  Future<AsrSecurityScopedBookmarkAccess> restoreAndStart(String bookmark) async {
    restoredBookmarks.add(bookmark);
    final path = restoredPath;
    if (path == null) {
      throw StateError('No restored path configured');
    }
    return AsrSecurityScopedBookmarkAccess(
      path: path,
      bookmark: restoredBookmark ?? bookmark,
    );
  }
}
